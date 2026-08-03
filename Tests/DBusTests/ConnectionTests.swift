//
//  ConnectionTests.swift
//  DBusTests
//

import Testing
@testable import DBus

/// End-to-end tests against a real message bus.
///
/// These are the strongest check on the marshaller: the bus daemon is a reference
/// implementation, so if it accepts our `Hello` and answers our calls, the wire format is right
/// in a way no self-written round-trip test can establish.
///
/// Serialized because each test opens real sockets; running them concurrently would multiply
/// connections against the daemon for no added coverage.
@Suite(.serialized, .enabled(if: hasSessionBus, "No session bus is available"))
struct ConnectionTests {

    private var interface: DBusInterface { DBusInterface(rawValue: "org.freedesktop.DBus")! }
    private var path: DBusObjectPath { DBusObjectPath(rawValue: "/org/freedesktop/DBus")! }
    private var destination: DBusBusName { DBusBusName(rawValue: "org.freedesktop.DBus")! }

    private func call(_ method: String, arguments: [DBusMessageArgument] = []) -> DBusMessage {

        return DBusMessage(methodCall: DBusMessage.MethodCall(destination: destination,
                                                              path: path,
                                                              interface: interface,
                                                              method: DBusMember(rawValue: method)!),
                           arguments: arguments)
    }

    /// A successful `Hello` proves the whole stack: socket, SASL, header marshalling and framing.
    @Test func helloAssignsUniqueName() async throws {

        try await withConnection { connection in

            let uniqueName = await connection.uniqueName

            #expect(uniqueName != nil)
            #expect(uniqueName?.isUnique == true, "\(uniqueName?.rawValue ?? "nil") should start with ':'")
            #expect(await connection.serverGUID != nil)
            #expect(await connection.isConnected)
        }
    }

    @Test func listNames() async throws {

        try await withConnection { connection in

            let names = try await connection.listNames()

            #expect(names.contains("org.freedesktop.DBus"), "The bus daemon must own its own name")

            let ownName = try #require(await connection.uniqueName).rawValue
            #expect(names.contains(ownName), "Our own unique name should be listed")
        }
    }

    /// `GetAll` returns `a{sv}`, which the libdbus-backed implementation could not decode at all.
    @Test func getAllProperties() async throws {

        try await withConnection { connection in

            let reply = try await connection.send(
                DBusMessage(methodCall: DBusMessage.MethodCall(
                    destination: destination,
                    path: path,
                    interface: DBusWellKnown.propertiesInterface,
                    method: DBusMember(rawValue: "GetAll")!),
                    arguments: [.string("org.freedesktop.DBus")])
            )

            #expect(reply.type == .methodReturn)
            #expect(reply.signature.rawValue == "a{sv}")

            guard case let .dictionary(properties)? = reply.arguments.first
                else { Issue.record("Expected a dictionary, got \(reply.arguments)"); return }

            #expect(properties.keyType == .string)
            #expect(properties.valueType == .variant)

            // Every value must be a variant carrying a decodable payload.
            for entry in properties {
                #expect(entry.key.stringValue != nil)
                #expect(entry.value.variantValue != nil, "\(entry.key) is not a variant")
            }
        }
    }

    /// Round-trips a value through the daemon and back, checking the bus agrees with our encoding.
    @Test func getNameOwner() async throws {

        try await withConnection { connection in

            let owner = try await connection.getNameOwner(destination)
            #expect(owner.rawValue == "org.freedesktop.DBus")

            #expect(try await connection.nameHasOwner(destination))
            #expect(try await connection.getBusID().isEmpty == false)
        }
    }

    /// An error reply must surface as a thrown `DBusError`, not as a returned message.
    @Test func errorReplyThrows() async throws {

        try await withConnection { connection in

            let error = await #expect(throws: DBusError.self) {
                try await connection.getNameOwner(DBusBusName(rawValue: "org.example.DoesNotExist")!)
            }

            #expect(error?.name == .nameHasNoOwner)
        }
    }

    @Test func unknownMethodThrows() async throws {

        try await withConnection { connection in

            let error = await #expect(throws: DBusError.self) {
                try await connection.send(call("ThisMethodDoesNotExist"))
            }

            #expect(error?.name == .unknownMethod)
        }
    }

    /// Serials must stay distinct so replies match the right call, including under concurrency.
    @Test func concurrentCalls() async throws {

        try await withConnection { connection in

            // Built outside the group so the closures capture a value, not `self`.
            let message = call("GetId")

            let ids = try await withThrowingTaskGroup(of: String.self) { group -> Set<String> in

                for _ in 0 ..< 20 {
                    group.addTask {
                        let reply = try await connection.send(message)
                        guard let id = reply.arguments.first?.stringValue
                            else { throw DBusProtocolError.invalidValue("No id") }
                        return id
                    }
                }

                var ids = Set<String>()
                for try await id in group {
                    ids.insert(id)
                }
                return ids
            }

            // Every call asks for the same value, so a mismatched reply shows up as a second id.
            #expect(ids.count == 1, "Replies were mismatched: \(ids)")
        }
    }

    @Test func sendAfterCloseThrows() async throws {

        guard let address = sessionBusAddress else { return }

        let connection = try await DBusConnection.connect(to: address)
        await connection.close()

        #expect(await connection.isConnected == false)

        let error = await #expect(throws: DBusError.self) {
            try await connection.send(call("ListNames"))
        }

        #expect(error?.name == .disconnected)
    }

    /// Closing twice must be safe; the second call has nothing left to tear down.
    @Test func closeIsIdempotent() async throws {

        guard let address = sessionBusAddress else { return }

        let connection = try await DBusConnection.connect(to: address)
        await connection.close()
        await connection.close()

        #expect(await connection.isConnected == false)
    }

    /// The system bus is a different daemon with different permissions, so it exercises the
    /// same path against a second reference implementation.
    @Test func systemBus() async throws {

        let connection: DBusConnection

        do { connection = try await DBusConnection.connect(to: .system) }
        catch {
            // A container may have no system bus; that is not a failure of this code.
            return
        }

        #expect(await connection.uniqueName?.isUnique == true)

        let names = try await connection.listNames()
        #expect(names.contains("org.freedesktop.DBus"))

        await connection.close()
    }
}
