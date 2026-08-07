//
//  MessageTests.swift
//  DBusTests
//
//  Created by Alsey Coleman Miller on 11/3/18.
//

import Testing
@testable import DBus

@Suite struct MessageTests {

    /// Encode and decode in both byte orders and check the message survives intact.
    private func assertRoundTrip(_ message: DBusMessage,
                                 sourceLocation: SourceLocation = #_sourceLocation) throws {

        for endianness in DBusEndianness.allCases {

            let bytes = try message.encode(endianness: endianness)

            // The total length must be derivable from the first 16 bytes alone.
            #expect(try DBusMessage.length(from: bytes) == bytes.count,
                    "\(endianness)", sourceLocation: sourceLocation)

            let (decoded, length) = try DBusMessage.decode(bytes)

            #expect(length == bytes.count, "\(endianness)", sourceLocation: sourceLocation)
            #expect(decoded == message, "\(endianness)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Header

    @Test func methodCallRoundTrip() throws {

        var message = DBusMessage(methodCall: DBusMessage.MethodCall(
            destination: DBusBusName(rawValue: "org.freedesktop.DBus")!,
            path: DBusObjectPath(rawValue: "/org/freedesktop/DBus")!,
            interface: DBusInterface(rawValue: "org.freedesktop.DBus")!,
            method: DBusMember(rawValue: "ListNames")!
        ))
        message.serial = 1

        try assertRoundTrip(message)
    }

    /// `MethodCall` and `Signal` had only an internal memberwise initializer before the rewrite,
    /// so `DBusMessage.init(methodCall:)` could not be reached from outside the module.
    @Test func methodCallIsPubliclyConstructible() {

        let methodCall = DBusMessage.MethodCall(
            path: DBusObjectPath(rawValue: "/org/example")!,
            method: DBusMember(rawValue: "Ping")!
        )

        #expect(methodCall.destination == nil)
        #expect(methodCall.interface == nil)
        #expect(DBusMessage(methodCall: methodCall).type == .methodCall)

        let signal = DBusMessage.Signal(
            path: DBusObjectPath(rawValue: "/org/example")!,
            interface: DBusInterface(rawValue: "org.example.Thing")!,
            name: DBusMember(rawValue: "Changed")!
        )

        #expect(DBusMessage(signal: signal).type == .signal)
    }

    @Test func signalRoundTrip() throws {

        var message = DBusMessage(signal: DBusMessage.Signal(
            path: DBusObjectPath(rawValue: "/org/freedesktop/DBus")!,
            interface: DBusInterface(rawValue: "org.freedesktop.DBus")!,
            name: DBusMember(rawValue: "NameAcquired")!
        ), arguments: [.string(":1.42")])

        message.serial = 7
        message.sender = DBusBusName(rawValue: "org.freedesktop.DBus")!

        try assertRoundTrip(message)
    }

    @Test func allHeaderFieldsRoundTrip() throws {

        var message = DBusMessage(type: .methodCall)
        message.serial = 0xDEADBEEF
        message.flags = [.noReplyExpected, .noAutoStart, .allowInteractiveAuthorization]
        message.path = DBusObjectPath(rawValue: "/com/example/bus1")!
        message.interface = DBusInterface(rawValue: "com.example.MusicPlayer1")!
        message.member = DBusMember(rawValue: "Play")!
        message.replySerial = 12345
        message.destination = DBusBusName(rawValue: "com.example.MusicPlayer1")!
        message.sender = DBusBusName(rawValue: ":1.99")!
        message.arguments = [.string("track"), .uint32(3)]

        try assertRoundTrip(message)
        #expect(message.signature.rawValue == "su")
    }

    @Test func errorMessage() throws {

        var originalMessage = DBusMessage(type: .methodCall)
        originalMessage.serial = .random(in: 1 ..< .max)
        originalMessage.sender = DBusBusName(rawValue: ":1.5")!

        let error = DBusError(name: .failed, message: "Test Error")
        let errorMessage = DBusMessage(replyTo: originalMessage, error: error)

        #expect(errorMessage.type == .error)
        #expect(errorMessage.replySerial == originalMessage.serial)
        #expect(errorMessage.destination == originalMessage.sender)
        #expect(DBusError(message: errorMessage) == error)

        try assertRoundTrip(errorMessage)
    }

    @Test func methodReturn() throws {

        var call = DBusMessage(type: .methodCall)
        call.serial = 42
        call.sender = DBusBusName(rawValue: ":1.5")!

        let reply = DBusMessage(methodReturn: call, arguments: [.boolean(true)])

        #expect(reply.type == .methodReturn)
        #expect(reply.replySerial == 42)
        #expect(reply.destination == call.sender)

        try assertRoundTrip(reply)
    }

    @Test func errorFromNonErrorMessageIsNil() {

        #expect(DBusError(message: DBusMessage(type: .methodCall)) == nil)
    }

    // MARK: - Body

    @Test func basicValueArguments() throws {

        var message = DBusMessage(type: .methodCall, serial: 1)
        message.arguments = [
            .byte(.max),
            .boolean(true),
            .int16(.max),
            .uint16(.max),
            .int32(.max),
            .uint32(.max),
            .int64(.max),
            .uint64(.max),
            .double(0.1111),
            .string("Test String"),
            .objectPath(DBusObjectPath(rawValue: "/com/example/bus1")!),
            .signature(DBusSignature(rawValue: "a{s(ai)}")!)
        ]

        try assertRoundTrip(message)
    }

    @Test func arrayArguments() throws {

        var message = DBusMessage(type: .methodCall, serial: 1)
        message.arguments = [
            .array(DBusMessageArgument.Array([.int16(1), .int16(2), .int16(3)])!),
            .array(DBusMessageArgument.Array(type: .int16)),
            .array(DBusMessageArgument.Array(type: .string, [.string("1"), .string("2")])!),
            .array(DBusMessageArgument.Array(type: .array(.string), [
                .array(DBusMessageArgument.Array(type: .string, [.string("A1"), .string("A2")])!)
            ])!),
            .array(DBusMessageArgument.Array(type: .struct([.int32, .string]), [
                .struct(DBusMessageArgument.Structure([.int32(1), .string("Test String 1")])!),
                .struct(DBusMessageArgument.Structure([.int32(2), .string("Test String 2")])!)
            ])!)
        ]

        try assertRoundTrip(message)
    }

    @Test func structureArguments() throws {

        var message = DBusMessage(type: .methodCall, serial: 1)
        message.arguments = [
            .struct(DBusMessageArgument.Structure([.int32(1), .string("Test String")])!),
            .struct(DBusMessageArgument.Structure([
                .int32(1),
                .string("Test String 1"),
                .objectPath(DBusObjectPath(rawValue: "/com/example/bus1")!),
                .struct(DBusMessageArgument.Structure([
                    .int32(2),
                    .string("Test String 2"),
                    .objectPath(DBusObjectPath(rawValue: "/com/example/bus2")!)
                ])!)
            ])!)
        ]

        try assertRoundTrip(message)
    }

    /// The shape returned by `org.freedesktop.DBus.Properties.GetAll`, which crashed the
    /// libdbus-backed implementation because `variant` and `dict` were unimplemented.
    @Test func variantAndDictionaryArguments() throws {

        var message = DBusMessage(type: .methodReturn, serial: 1)
        message.replySerial = 1
        message.arguments = [
            .dictionary(DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant, [
                .init(key: .string("Name"),
                      value: .variant(DBusMessageArgument.Variant(.string("Example")))),
                .init(key: .string("Version"),
                      value: .variant(DBusMessageArgument.Variant(.uint32(2)))),
                .init(key: .string("Paths"),
                      value: .variant(DBusMessageArgument.Variant(
                        .array(DBusMessageArgument.Array(type: .objectPath, [
                            .objectPath(DBusObjectPath(rawValue: "/a")!)
                        ])!))))
            ])!)
        ]

        #expect(message.signature.rawValue == "a{sv}")
        try assertRoundTrip(message)
    }

    @Test func emptyBodyHasNoSignatureField() throws {

        var message = DBusMessage(type: .methodCall, serial: 1)
        message.member = DBusMember(rawValue: "Ping")!

        let bytes = try message.encode()
        let (decoded, _) = try DBusMessage.decode(bytes)

        #expect(decoded.arguments.isEmpty)
        #expect(decoded.signature.rawValue == "")
    }

    // MARK: - Framing

    @Test func lengthRequiresSixteenBytes() throws {

        let message = DBusMessage(type: .methodCall, serial: 1,
                                  member: DBusMember(rawValue: "Ping")!)
        let bytes = try message.encode()

        for count in 0 ..< DBusMessage.minimumHeaderLength {
            #expect(try DBusMessage.length(from: Array(bytes.prefix(count))) == nil)
        }

        #expect(try DBusMessage.length(from: Array(bytes.prefix(16))) == bytes.count)
    }

    @Test func decodeIgnoresTrailingBytes() throws {

        let message = DBusMessage(type: .methodCall, serial: 1,
                                  member: DBusMember(rawValue: "Ping")!,
                                  arguments: [.string("x")])
        var bytes = try message.encode()
        let expectedLength = bytes.count
        bytes.append(contentsOf: [0xAA, 0xBB, 0xCC])

        let (decoded, length) = try DBusMessage.decode(bytes)
        #expect(length == expectedLength)
        #expect(decoded == message)
    }

    @Test func rejectsTruncatedMessage() throws {

        let message = DBusMessage(type: .methodCall, serial: 1,
                                  member: DBusMember(rawValue: "Ping")!,
                                  arguments: [.string("hello")])
        let bytes = try message.encode()

        for count in 0 ..< bytes.count {
            #expect(throws: (any Error).self, "Should reject \(count) of \(bytes.count) bytes") {
                try DBusMessage.decode(Array(bytes.prefix(count)))
            }
        }
    }

    @Test func rejectsInvalidByteOrder() throws {

        var bytes = try DBusMessage(type: .methodCall, serial: 1).encode()
        bytes[0] = 0x58 // 'X'

        #expect(throws: DBusProtocolError.invalidByteOrder(0x58)) {
            try DBusMessage.decode(bytes)
        }
    }

    @Test func rejectsInvalidMessageType() throws {

        var bytes = try DBusMessage(type: .methodCall, serial: 1).encode()
        bytes[1] = 99

        #expect(throws: DBusProtocolError.invalidMessageType(99)) {
            try DBusMessage.decode(bytes)
        }
    }

    @Test func rejectsInvalidProtocolVersion() throws {

        var bytes = try DBusMessage(type: .methodCall, serial: 1).encode()
        bytes[3] = 2

        #expect(throws: DBusProtocolError.invalidProtocolVersion(2)) {
            try DBusMessage.decode(bytes)
        }
    }

    /// Unknown header field codes must be skipped rather than rejected, so that additions to
    /// the specification do not break this implementation.
    @Test func ignoresUnknownHeaderField() throws {

        var message = DBusMessage(type: .methodCall, serial: 1)
        message.member = DBusMember(rawValue: "Ping")!

        // Encode by hand with an extra field, code 200.
        var fields = Array(message.headerFieldsArgument())
        fields.append(.struct(DBusMessageArgument.Structure([
            .byte(200),
            .variant(DBusMessageArgument.Variant(.string("ignored")))
        ])!))

        let array = DBusMessageArgument.Array(type: .struct([.byte, .variant]), fields)!

        var marshaller = DBusMarshaller(endianness: .little)
        marshaller.append(DBusEndianness.little.rawValue)
        marshaller.append(DBusMessageType.methodCall.rawValue)
        marshaller.append(UInt8(0))
        marshaller.append(DBusMessage.protocolVersion)
        marshaller.appendUnaligned(UInt32(0)) // body length
        marshaller.appendUnaligned(UInt32(1)) // serial
        try marshaller.append(.array(array))
        marshaller.pad(to: 8)

        let (decoded, _) = try DBusMessage.decode(marshaller.bytes)
        #expect(decoded.member == message.member)
        #expect(decoded.serial == 1)
    }
}
