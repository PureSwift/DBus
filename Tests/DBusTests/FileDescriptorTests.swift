//
//  FileDescriptorTests.swift
//  DBusTests
//

import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Bionic)
import Bionic
#endif
import Testing
@testable import DBus

/// Tests for `UNIX_FD` marshalling and end-to-end descriptor passing.
///
/// On the wire a `UNIX_FD` is an *index* into the descriptors sent out of band, never the
/// descriptor number itself, so these check the indirection in both directions.
@Suite struct FileDescriptorMarshalTests {

    @Test func marshalsAsIndexNotDescriptorNumber() throws {

        // Deliberately large, unlikely descriptor numbers.
        let arguments: [DBusMessageArgument] = [
            .fileDescriptor(.init(rawValue: 41)),
            .fileDescriptor(.init(rawValue: 57))
        ]

        let (bytes, descriptors) = try DBusMarshaller.marshalWithDescriptors(arguments, endianness: .little)

        // Two UInt32 indices, 0 and 1 — not 41 and 57.
        #expect(bytes == [0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
        #expect(descriptors == [41, 57])
    }

    @Test func unmarshalsIndexBackToDescriptor() throws {

        let bytes: [UInt8] = [0x01, 0x00, 0x00, 0x00] // index 1

        var unmarshaller = DBusUnmarshaller(bytes: bytes,
                                            endianness: .little,
                                            fileDescriptors: [41, 57])

        let value = try unmarshaller.read(.fileDescriptor)

        #expect(value == .fileDescriptor(.init(rawValue: 57)))
    }

    @Test func rejectsOutOfRangeIndex() {

        let bytes: [UInt8] = [0x05, 0x00, 0x00, 0x00] // index 5, but only one descriptor

        var unmarshaller = DBusUnmarshaller(bytes: bytes,
                                            endianness: .little,
                                            fileDescriptors: [41])

        #expect(throws: (any Error).self) { try unmarshaller.read(.fileDescriptor) }
    }

    /// A message with no descriptors must not gain a `UNIX_FDS` header field.
    @Test func omitsHeaderFieldWhenNoDescriptors() throws {

        let message = DBusMessage(type: .methodCall, serial: 1, arguments: [.string("x")])

        let (bytes, descriptors) = try message.encodeWithDescriptors()

        #expect(descriptors.isEmpty)

        let (decoded, _) = try DBusMessage.decode(bytes)
        #expect(decoded.unixFileDescriptorCount == nil)
    }

    /// The header field is derived from what marshalling produced, so it cannot disagree.
    @Test func headerFieldCountsDescriptors() throws {

        var message = DBusMessage(type: .methodCall, serial: 1)
        message.member = DBusMember(rawValue: "Send")!
        message.arguments = [
            .fileDescriptor(.init(rawValue: 3)),
            .string("meta"),
            .fileDescriptor(.init(rawValue: 4))
        ]

        // Deliberately wrong; encoding must ignore it.
        message.unixFileDescriptorCount = 99

        let (bytes, descriptors) = try message.encodeWithDescriptors()

        #expect(descriptors == [3, 4])
        #expect(message.signature.rawValue == "hsh")

        let (decoded, _) = try DBusMessage.decode(bytes, fileDescriptors: descriptors)

        #expect(decoded.unixFileDescriptorCount == 2)
        #expect(decoded.arguments == message.arguments)
    }

    @Test func roundTripsInBothByteOrders() throws {

        for endianness in DBusEndianness.allCases {

            var message = DBusMessage(type: .methodCall, serial: 7)
            message.member = DBusMember(rawValue: "Send")!
            message.arguments = [
                .fileDescriptor(.init(rawValue: 11)),
                .array(DBusMessageArgument.Array(type: .fileDescriptor, [
                    .fileDescriptor(.init(rawValue: 12)),
                    .fileDescriptor(.init(rawValue: 13))
                ])!)
            ]

            let (bytes, descriptors) = try message.encodeWithDescriptors(endianness: endianness)

            #expect(descriptors == [11, 12, 13], "\(endianness)")

            let (decoded, _) = try DBusMessage.decode(bytes, fileDescriptors: descriptors)
            #expect(decoded.arguments == message.arguments, "\(endianness)")
        }
    }

    /// A descriptor inside a variant still resolves through the same index table.
    @Test func handlesDescriptorInsideVariant() throws {

        var message = DBusMessage(type: .methodCall, serial: 1)
        message.member = DBusMember(rawValue: "Send")!
        message.arguments = [
            .variant(DBusMessageArgument.Variant(.fileDescriptor(.init(rawValue: 21))))
        ]

        let (bytes, descriptors) = try message.encodeWithDescriptors()
        #expect(descriptors == [21])

        let (decoded, _) = try DBusMessage.decode(bytes, fileDescriptors: descriptors)
        #expect(decoded.arguments == message.arguments)
    }
}

// MARK: - Live

/// Passing a real descriptor between two connections on the session bus.
@Suite(.serialized, .enabled(if: hasSessionBus, "No session bus is available"))
struct FileDescriptorPassingTests {

    private let testInterface = DBusInterface(rawValue: "com.example.FileDescriptors")!
    private let testPath = DBusObjectPath(rawValue: "/com/example/FileDescriptors")!

    /// A temporary file holding `contents`, open for reading.
    private func makeTemporaryFile(contents: String) throws -> (Int32, String) {

        let path = "/tmp/dbus-fd-test-\(UInt32.random(in: 0 ... .max))"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)

        let descriptor = open(path, O_RDONLY)
        #expect(descriptor >= 0)

        return (descriptor, path)
    }

    private func readAll(_ descriptor: Int32) -> String {

        var buffer = [UInt8](repeating: 0, count: 512)
        let count = read(descriptor, &buffer, buffer.count)

        guard count > 0 else { return "" }

        return String(decoding: buffer[0 ..< count], as: UTF8.self)
    }

    /// The bus must have agreed to descriptor passing during the handshake.
    @Test func negotiatesDescriptorPassing() async throws {

        try await withConnection { connection in
            #expect(await connection.unixFileDescriptorsSupported,
                    "The session bus should agree to NEGOTIATE_UNIX_FD")
        }
    }

    /// The real test: a descriptor sent through the bus refers to the same open file.
    @Test func passesDescriptorThroughTheBus() async throws {

        let (file, path) = try makeTemporaryFile(contents: "contents behind a passed descriptor")
        defer { close(file); unlink(path) }

        try await withConnections { server, client in

            // The server echoes back whatever it can read through the descriptor it receives.
            let received = ReceivedText()

            let implementation = DBusInterfaceImplementation(
                name: testInterface,
                methods: [
                    .init(name: DBusMember(rawValue: "Accept")!,
                          inputSignature: DBusSignature(rawValue: "h")!,
                          outputSignature: DBusSignature(rawValue: "s")!,
                          handler: { call in
                              guard case let .fileDescriptor(descriptor)? = call.arguments.first
                                  else { throw DBusError(name: .invalidArguments, message: "Expected a descriptor") }

                              var buffer = [UInt8](repeating: 0, count: 512)
                              let count = read(descriptor.rawValue, &buffer, buffer.count)
                              close(descriptor.rawValue)

                              let text = count > 0
                                  ? String(decoding: buffer[0 ..< count], as: UTF8.self)
                                  : ""

                              await received.set(text)
                              return [.string(text)]
                          })
                ]
            )

            await server.export(DBusExportedObject([implementation]), at: testPath)

            let name = try #require(await server.uniqueName)

            let reply = try await client.callMethod(
                destination: name,
                path: testPath,
                interface: testInterface,
                method: DBusMember(rawValue: "Accept")!,
                arguments: [.fileDescriptor(.init(rawValue: file))]
            )

            // The server read the file through a descriptor it received over the bus.
            #expect(reply.first?.stringValue == "contents behind a passed descriptor")
            #expect(await received.value == "contents behind a passed descriptor")
        }
    }

    /// Several descriptors in one message must arrive in order.
    @Test func passesSeveralDescriptors() async throws {

        var files = [Int32]()
        var paths = [String]()

        for index in 0 ..< 3 {
            let (file, path) = try makeTemporaryFile(contents: "file \(index)")
            files.append(file)
            paths.append(path)
        }

        defer {
            files.forEach { close($0) }
            paths.forEach { unlink($0) }
        }

        try await withConnections { server, client in

            let implementation = DBusInterfaceImplementation(
                name: testInterface,
                methods: [
                    .init(name: DBusMember(rawValue: "AcceptMany")!,
                          inputSignature: DBusSignature(rawValue: "ah")!,
                          outputSignature: DBusSignature(rawValue: "as")!,
                          handler: { call in
                              guard case let .array(array)? = call.arguments.first
                                  else { throw DBusError(name: .invalidArguments, message: "Expected an array") }

                              var contents = [DBusMessageArgument]()

                              for element in array {
                                  guard case let .fileDescriptor(descriptor) = element
                                      else { continue }

                                  var buffer = [UInt8](repeating: 0, count: 128)
                                  let count = read(descriptor.rawValue, &buffer, buffer.count)
                                  close(descriptor.rawValue)

                                  contents.append(.string(count > 0
                                      ? String(decoding: buffer[0 ..< count], as: UTF8.self)
                                      : ""))
                              }

                              guard let result = DBusMessageArgument.Array(type: .string, contents)
                                  else { throw DBusError(name: .failed, message: "Could not build the reply") }

                              return [.array(result)]
                          })
                ]
            )

            await server.export(DBusExportedObject([implementation]), at: testPath)

            let name = try #require(await server.uniqueName)

            let descriptors = DBusMessageArgument.Array(
                type: .fileDescriptor,
                files.map { .fileDescriptor(.init(rawValue: $0)) }
            )!

            let reply = try await client.callMethod(
                destination: name,
                path: testPath,
                interface: testInterface,
                method: DBusMember(rawValue: "AcceptMany")!,
                arguments: [.array(descriptors)]
            )

            guard case let .array(result)? = reply.first
                else { Issue.record("Expected an array, got \(reply)"); return }

            #expect(result.compactMap { $0.stringValue } == ["file 0", "file 1", "file 2"])
        }
    }

    /// The original descriptor must stay usable; the peer receives its own copy.
    @Test func senderKeepsItsOwnDescriptor() async throws {

        let (file, path) = try makeTemporaryFile(contents: "still readable")
        defer { close(file); unlink(path) }

        try await withConnections { server, client in

            let implementation = DBusInterfaceImplementation(
                name: testInterface,
                methods: [
                    .init(name: DBusMember(rawValue: "Accept")!,
                          inputSignature: DBusSignature(rawValue: "h")!,
                          handler: { call in
                              if case let .fileDescriptor(descriptor)? = call.arguments.first {
                                  close(descriptor.rawValue)
                              }
                              return []
                          })
                ]
            )

            await server.export(DBusExportedObject([implementation]), at: testPath)
            let name = try #require(await server.uniqueName)

            try await client.callMethod(destination: name, path: testPath,
                                        interface: testInterface,
                                        method: DBusMember(rawValue: "Accept")!,
                                        arguments: [.fileDescriptor(.init(rawValue: file))])

            // Rewind and read through the original descriptor.
            lseek(file, 0, SEEK_SET)
            #expect(readAll(file) == "still readable")
        }
    }
}

/// Somewhere for a `Sendable` handler to record what it read.
private actor ReceivedText {

    private(set) var value = ""

    func set(_ text: String) { value = text }
}
