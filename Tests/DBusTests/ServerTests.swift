//
//  ServerTests.swift
//  DBusTests
//

import Testing
@testable import DBus

/// Mutable state for the exported test object, kept in an actor so the handler closures are
/// `Sendable`.
private actor TestState {

    var greeting = "hello"
    var counter: UInt32 = 0

    func setGreeting(_ value: String) { greeting = value }
    func increment() -> UInt32 { counter += 1; return counter }
}

// MARK: - Introspection XML

/// These need no bus and so run in parallel with everything else.
@Suite struct IntrospectionTests {

    private let testInterface = DBusInterface(rawValue: "com.example.TestObject")!

    @Test func emptyNode() {

        let xml = DBusIntrospection.xml(for: nil)

        #expect(xml.hasPrefix("<!DOCTYPE node PUBLIC"))
        #expect(xml.contains("<interface name=\"org.freedesktop.DBus.Peer\">"))
        #expect(xml.contains("<interface name=\"org.freedesktop.DBus.Introspectable\">"))
        // Properties is only advertised for a real object.
        #expect(!xml.contains("org.freedesktop.DBus.Properties"))
        #expect(xml.hasSuffix("</node>\n"))
    }

    @Test func objectNode() {

        let implementation = DBusInterfaceImplementation(
            name: testInterface,
            methods: [
                .init(name: DBusMember(rawValue: "Echo")!,
                      inputSignature: DBusSignature(rawValue: "s")!,
                      outputSignature: DBusSignature(rawValue: "s")!,
                      inputNames: ["input"],
                      outputNames: ["output"],
                      handler: { _ in [] }),
                .init(name: DBusMember(rawValue: "Reset")!, handler: { _ in [] })
            ],
            properties: [
                .init(name: "Greeting", type: .string, access: .readwrite, get: { .string("") }, set: { _ in }),
                .init(name: "Counter", type: .uint32, access: .read, get: { .uint32(0) })
            ],
            signals: [
                .init(name: DBusMember(rawValue: "Bounced")!,
                      signature: DBusSignature(rawValue: "su")!,
                      argumentNames: ["text", "count"])
            ]
        )

        let xml = DBusIntrospection.xml(for: DBusExportedObject([implementation]), children: ["child"])

        #expect(xml.contains("<interface name=\"com.example.TestObject\">"), "\(xml)")
        #expect(xml.contains("<method name=\"Echo\">"), "\(xml)")
        #expect(xml.contains("<arg name=\"input\" type=\"s\" direction=\"in\"/>"), "\(xml)")
        #expect(xml.contains("<arg name=\"output\" type=\"s\" direction=\"out\"/>"), "\(xml)")
        #expect(xml.contains("<method name=\"Reset\"/>"), "A method with no arguments is self-closing")
        #expect(xml.contains("<property name=\"Counter\" type=\"u\" access=\"read\"/>"), "\(xml)")
        #expect(xml.contains("<property name=\"Greeting\" type=\"s\" access=\"readwrite\"/>"), "\(xml)")
        #expect(xml.contains("<signal name=\"Bounced\">"), "\(xml)")
        #expect(xml.contains("<arg name=\"text\" type=\"s\"/>"), "Signal arguments have no direction")
        #expect(xml.contains("<node name=\"child\"/>"), "\(xml)")
        #expect(xml.contains("org.freedesktop.DBus.Properties"), "\(xml)")
    }

    @Test func escapesXML() {

        #expect(DBusIntrospection.escape("a<b>c&d\"e'f") == "a&lt;b&gt;c&amp;d&quot;e&apos;f")
    }

    @Test func isDeterministic() {

        let implementation = DBusInterfaceImplementation(
            name: testInterface,
            methods: (0 ..< 10).map { index in
                .init(name: DBusMember(rawValue: "Method\(index)")!, handler: { _ in [] })
            }
        )

        let object = DBusExportedObject([implementation])

        #expect(DBusIntrospection.xml(for: object) == DBusIntrospection.xml(for: object))
    }

    @Test func machineIDIsReadable() throws {

        // Present on any system with a working D-Bus installation.
        guard let machineID = MachineID.current else { return }

        #expect(machineID.count == 32, "Expected a 32 character hex UUID, got '\(machineID)'")
        #expect(!machineID.contains("\n"))
    }
}

// MARK: - Live

@Suite(.serialized, .enabled(if: hasSessionBus, "No session bus is available"))
struct ServerTests {

    private let testInterface = DBusInterface(rawValue: "com.example.TestObject")!
    private let testPath = DBusObjectPath(rawValue: "/com/example/TestObject")!

    /// Build the exported test object and register it on the connection.
    private func export(on connection: DBusConnection, state: TestState) async {

        let implementation = DBusInterfaceImplementation(
            name: testInterface,
            methods: [
                .init(name: DBusMember(rawValue: "Echo")!,
                      inputSignature: DBusSignature(rawValue: "s")!,
                      outputSignature: DBusSignature(rawValue: "s")!,
                      handler: { call in
                          guard case let .string(text)? = call.arguments.first
                              else { throw DBusError(name: .invalidArguments, message: "Expected a string") }
                          return [.string(text)]
                      }),
                .init(name: DBusMember(rawValue: "Increment")!,
                      outputSignature: DBusSignature(rawValue: "u")!,
                      handler: { _ in [.uint32(await state.increment())] }),
                .init(name: DBusMember(rawValue: "Fail")!,
                      handler: { _ in
                          throw DBusError(name: .notSupported, message: "Deliberate failure")
                      }),
                .init(name: DBusMember(rawValue: "Throw")!,
                      handler: { _ in
                          // A non-DBusError must become org.freedesktop.DBus.Error.Failed.
                          throw DBusProtocolError.endOfStream
                      })
            ],
            properties: [
                .init(name: "Greeting", type: .string, access: .readwrite,
                      get: { .string(await state.greeting) },
                      set: { value in
                          guard case let .string(text) = value
                              else { throw DBusError(name: .invalidArguments, message: "Expected a string") }
                          await state.setGreeting(text)
                      }),
                .init(name: "ReadOnly", type: .uint32, access: .read, get: { .uint32(42) })
            ],
            signals: [
                .init(name: DBusMember(rawValue: "Bounced")!, signature: DBusSignature(rawValue: "s")!)
            ]
        )

        await connection.export(DBusExportedObject([implementation]), at: testPath)
    }

    /// Run `body` with a server connection exporting the test object, plus a client connection.
    private func withServerAndClient(
        _ body: (DBusConnection, DBusConnection, DBusBusName) async throws -> Void
    ) async throws {

        try await withConnections { server, client in

            await export(on: server, state: TestState())

            let name = try #require(await server.uniqueName)

            try await body(server, client, name)
        }
    }

    private func call(_ client: DBusConnection,
                      _ name: DBusBusName,
                      _ method: String,
                      arguments: [DBusMessageArgument] = []) async throws -> [DBusMessageArgument] {

        return try await client.callMethod(destination: name,
                                           path: testPath,
                                           interface: testInterface,
                                           method: DBusMember(rawValue: method)!,
                                           arguments: arguments)
    }

    // MARK: Method dispatch

    @Test func callExportedMethod() async throws {

        try await withServerAndClient { _, client, name in

            let reply = try await call(client, name, "Echo", arguments: [.string("round trip")])
            #expect(reply.first?.stringValue == "round trip")
        }
    }

    @Test func exportedMethodStateIsPreserved() async throws {

        try await withServerAndClient { _, client, name in

            var values = [UInt32]()

            for _ in 0 ..< 3 {
                let reply = try await call(client, name, "Increment")
                guard case let .uint32(value)? = reply.first
                    else { Issue.record("Expected a uint32, got \(reply)"); return }
                values.append(value)
            }

            #expect(values == [1, 2, 3])
        }
    }

    @Test func handlerErrorBecomesErrorReply() async throws {

        try await withServerAndClient { _, client, name in

            let thrown = await #expect(throws: DBusError.self) {
                try await call(client, name, "Fail")
            }

            #expect(thrown?.name == .notSupported)
            #expect(thrown?.message == "Deliberate failure")

            // A thrown error that is not a DBusError is reported as Failed.
            let generic = await #expect(throws: DBusError.self) {
                try await call(client, name, "Throw")
            }

            #expect(generic?.name == .failed)
        }
    }

    @Test func unknownMemberAndPathErrors() async throws {

        try await withServerAndClient { _, client, name in

            let unknownMethod = await #expect(throws: DBusError.self) {
                try await call(client, name, "Nope")
            }
            #expect(unknownMethod?.name == .unknownMethod)

            let unknownInterface = await #expect(throws: DBusError.self) {
                try await client.callMethod(destination: name, path: testPath,
                                            interface: DBusInterface(rawValue: "com.example.Missing")!,
                                            method: DBusMember(rawValue: "Echo")!)
            }
            #expect(unknownInterface?.name == .unknownInterface)

            let unknownObject = await #expect(throws: DBusError.self) {
                try await client.callMethod(destination: name,
                                            path: DBusObjectPath(rawValue: "/com/example/Missing")!,
                                            interface: testInterface,
                                            method: DBusMember(rawValue: "Echo")!)
            }
            #expect(unknownObject?.name == .unknownObject)
        }
    }

    @Test func wrongArgumentSignatureIsRejected() async throws {

        try await withServerAndClient { _, client, name in

            let error = await #expect(throws: DBusError.self) {
                try await call(client, name, "Echo", arguments: [.int32(5)])
            }

            #expect(error?.name == .invalidArguments)
        }
    }

    // MARK: Standard interfaces, served by us

    @Test func peerPing() async throws {

        try await withServerAndClient { _, client, name in

            try await client.ping(destination: name, path: testPath)

            // Ping is answered even at a path with no exported object.
            try await client.ping(destination: name, path: DBusObjectPath(rawValue: "/anything")!)
        }
    }

    @Test func peerGetMachineID() async throws {

        try await withServerAndClient { _, client, name in

            let reply = try await client.callMethod(destination: name, path: testPath,
                                                    interface: DBusWellKnown.peerInterface,
                                                    method: DBusMember(rawValue: "GetMachineId")!)

            #expect(reply.first?.stringValue?.count == 32)
        }
    }

    @Test func introspectOverTheBus() async throws {

        try await withServerAndClient { _, client, name in

            let xml = try await client.introspect(destination: name, path: testPath)

            #expect(xml.contains("com.example.TestObject"), "\(xml)")
            #expect(xml.contains("<method name=\"Echo\">"), "\(xml)")
            #expect(xml.contains("<property name=\"Greeting\" type=\"s\" access=\"readwrite\"/>"), "\(xml)")
            #expect(xml.contains("<signal name=\"Bounced\">"), "\(xml)")
        }
    }

    @Test func propertiesGetSetGetAll() async throws {

        try await withServerAndClient { _, client, name in

            let initial = try await client.getProperty(destination: name, path: testPath,
                                                       interface: testInterface, name: "Greeting")
            #expect(initial == .string("hello"))

            try await client.setProperty(destination: name, path: testPath,
                                         interface: testInterface, name: "Greeting",
                                         value: .string("goodbye"))

            let updated = try await client.getProperty(destination: name, path: testPath,
                                                       interface: testInterface, name: "Greeting")
            #expect(updated == .string("goodbye"))

            let all = try await client.getAllProperties(destination: name, path: testPath,
                                                        interface: testInterface)
            #expect(all["Greeting"] == .string("goodbye"))
            #expect(all["ReadOnly"] == .uint32(42))
        }
    }

    @Test func writingReadOnlyPropertyFails() async throws {

        try await withServerAndClient { _, client, name in

            let error = await #expect(throws: DBusError.self) {
                try await client.setProperty(destination: name, path: testPath,
                                             interface: testInterface, name: "ReadOnly",
                                             value: .uint32(1))
            }

            #expect(error?.name == .propertyReadOnly)
        }
    }

    @Test func settingPropertyWithWrongTypeFails() async throws {

        try await withServerAndClient { _, client, name in

            let error = await #expect(throws: DBusError.self) {
                try await client.setProperty(destination: name, path: testPath,
                                             interface: testInterface, name: "Greeting",
                                             value: .int32(5))
            }

            #expect(error?.name == .invalidArguments)
        }
    }

    @Test func unknownPropertyFails() async throws {

        try await withServerAndClient { _, client, name in

            let error = await #expect(throws: DBusError.self) {
                try await client.getProperty(destination: name, path: testPath,
                                             interface: testInterface, name: "Missing")
            }

            #expect(error?.name == .unknownProperty)
        }
    }

    /// The bus daemon's own introspection must parse too, which checks we can be a client of a
    /// reference server as well as a server ourselves.
    @Test func introspectTheBusDaemon() async throws {

        try await withConnection { client in

            let xml = try await client.introspect(destination: DBusWellKnown.busName,
                                                  path: DBusWellKnown.busPath)

            #expect(xml.contains("org.freedesktop.DBus"), "\(xml)")
            #expect(xml.contains("<method name=\"Hello\">"), "\(xml)")
        }
    }

    // MARK: Object tree

    @Test func childNodesAppearInIntrospection() async throws {

        try await withConnection { connection in

            let root = DBusObjectPath(rawValue: "/com/example")!
            let child = DBusObjectPath(rawValue: "/com/example/child")!
            let grandchild = DBusObjectPath(rawValue: "/com/example/child/deep")!

            await connection.export(DBusExportedObject(), at: root)
            await connection.export(DBusExportedObject(), at: child)
            await connection.export(DBusExportedObject(), at: grandchild)

            #expect(await connection.childNodeNames(of: root) == ["child"], "Only direct children")
            #expect(await connection.childNodeNames(of: child) == ["deep"])
            #expect(await connection.childNodeNames(of: grandchild) == [])
        }
    }

    @Test func unexport() async throws {

        try await withConnection { connection in

            await export(on: connection, state: TestState())

            #expect(await connection.exportedObject(at: testPath) != nil)

            await connection.unexport(at: testPath)

            #expect(await connection.exportedObject(at: testPath) == nil)
        }
    }
}
