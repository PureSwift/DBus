import Testing
import Foundation
import DBus
import BlueZ
import NetworkManager
import UPower
import Login1
import ScreenSaver

@Suite struct ServiceTests {
    @Test func replySignatures() throws {
        try DBusServiceProxy.validate([.uint32(42)], signature: "u")
        try DBusServiceProxy.validate([], signature: "")
        #expect(throws: DBusProtocolError.self) {
            try DBusServiceProxy.validate([.string("42")], signature: "u")
        }
        #expect(throws: DBusProtocolError.self) {
            try DBusServiceProxy.validate([.uint32(42), .uint32(1)], signature: "u")
        }
        #expect(throws: DBusProtocolError.self) {
            try DBusServiceProxy.validate([], signature: "h")
        }
    }

    @Test func emptyArraySignatureIsPreserved() throws {
        let paths = try #require(DBusMessageArgument.Array(type: .objectPath, []))
        try DBusServiceProxy.validate([.array(paths)], signature: "ao")
        #expect(throws: DBusProtocolError.self) {
            try DBusServiceProxy.validate([.array(paths)], signature: "as")
        }
    }

    @Test func serviceValueHelpers() throws {
        let value = DBusMessageArgument.variant(.init(.variant(.init(.uint32(12)))))
        #expect(value.unwrapped == .uint32(12))
        #expect(value.intValue == 12)
        #expect(DBusMessageArgument.uint64(.max).intValue == nil)
        #expect(DBusMessageArgument.byteArray([0, 128, 255]).bytes == [0, 128, 255])
        guard case .dictionary(let properties) = DBusMessageArgument.options(["Powered": .boolean(true)]) else {
            Issue.record("Expected an options dictionary")
            return
        }
        #expect(properties.first?.key == .string("Powered"))
        #expect(properties.first?.value.unwrapped == .boolean(true))
        try DBusServiceProxy.validate([.options()], signature: "a{sv}")
    }

    @Test func nestedDictionariesAndMultipleResults() throws {
        let optionsType = try #require(DBusSignature(rawValue: "a{sv}")?.first)
        let settings = try #require(DBusMessageArgument.Dictionary(keyType: .string, valueType: optionsType, []))
        try DBusServiceProxy.validate([.dictionary(settings)], signature: "a{sa{sv}}")
        #expect(throws: DBusProtocolError.self) {
            try DBusServiceProxy.validate([.options()], signature: "a{sa{sv}}")
        }
        let path = try #require(DBusObjectPath(rawValue: "/connection"))
        try DBusServiceProxy.validate([.objectPath(path), .objectPath(path)], signature: "oo")
        #expect(throws: DBusProtocolError.self) {
            try DBusServiceProxy.validate([.objectPath(path)], signature: "oo")
        }
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DBUS_SESSION_BUS_ADDRESS"] != nil,
                            "Requires a private session bus"))
struct ServiceWireTests {
    @Test func generatedClients() async throws {
        let server = try await DBusConnection.connect(to: .session)
        do {
            let client = try await DBusConnection.connect(to: .session)
            do {
                let services: [(String, String, String, [DBusInterfaceImplementation.Method], [DBusInterfaceImplementation.Property])] = [
                    ("org.bluez", "/adapter", "org.bluez.Adapter1", [
                        .init(name: try #require(DBusMember(rawValue: "SetDiscoveryFilter")),
                              inputSignature: try #require(DBusSignature(rawValue: "a{sv}")), handler: { call in
                            #expect(call.arguments == [.options(["DuplicateData": .boolean(true)])])
                            return []
                        })
                    ], [.init(name: "Powered", type: .boolean, access: .readwrite,
                              get: { .boolean(true) }, set: { value in #expect(value == .boolean(true)) })]),
                    ("org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager", [
                        .init(name: try #require(DBusMember(rawValue: "AddAndActivateConnection")),
                              inputSignature: try #require(DBusSignature(rawValue: "a{sa{sv}}oo")),
                              outputSignature: try #require(DBusSignature(rawValue: "oo")), handler: { call in
                            #expect(call.arguments.count == 3)
                            #expect(call.arguments[1].pathValue == "/device")
                            #expect(call.arguments[2].pathValue == "/")
                            return [.objectPath(try #require(DBusObjectPath(rawValue: "/settings/1"))),
                                    .objectPath(try #require(DBusObjectPath(rawValue: "/active/1")))]
                        }),
                        .init(name: try #require(DBusMember(rawValue: "GetPermissions")),
                              outputSignature: try #require(DBusSignature(rawValue: "s")),
                              handler: { _ in [.string("malformed")] })
                    ], []),
                    ("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver", "org.freedesktop.ScreenSaver", [
                        .init(name: try #require(DBusMember(rawValue: "Inhibit")),
                              inputSignature: try #require(DBusSignature(rawValue: "ss")),
                              outputSignature: try #require(DBusSignature(rawValue: "u")), handler: { call in
                            #expect(call.arguments == [.string("test.app"), .string("Playing video")])
                            return [.uint32(42)]
                        }),
                        .init(name: try #require(DBusMember(rawValue: "UnInhibit")),
                              inputSignature: try #require(DBusSignature(rawValue: "u")), handler: { call in
                            #expect(call.arguments == [.uint32(42)])
                            return []
                        })
                    ], []),
                    ("org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.UPower", [
                        .init(name: try #require(DBusMember(rawValue: "GetDisplayDevice")),
                              outputSignature: try #require(DBusSignature(rawValue: "o")), handler: { _ in
                            [.objectPath(try #require(DBusObjectPath(rawValue: "/battery")))]
                        })
                    ], [.init(name: "OnBattery", type: .boolean, access: .read, get: { .boolean(true) })]),
                    ("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", [
                        .init(name: try #require(DBusMember(rawValue: "CanSuspend")),
                              outputSignature: try #require(DBusSignature(rawValue: "s")), handler: { _ in [.string("challenge")] })
                    ], [])
                ]
                for (name, path, interface, methods, properties) in services {
                    await server.export(DBusExportedObject([
                        DBusInterfaceImplementation(name: try #require(DBusInterface(rawValue: interface)),
                                                    methods: methods, properties: properties)
                    ]), at: try #require(DBusObjectPath(rawValue: path)))
                    _ = try await server.requestName(try #require(DBusBusName(rawValue: name)))
                }
                let screenSaver = try ScreenSaver(connection: client)
                let adapter = try BlueZ.Adapter(connection: client, path: "/adapter")
                guard case .dictionary(let filter) = DBusMessageArgument.options(["DuplicateData": .boolean(true)]) else {
                    throw DBusProtocolError.invalidValue("Expected dictionary")
                }
                try await adapter.setDiscoveryFilter(filter: filter)
                try await adapter.setPowered(true)
                #expect(try await adapter.powered)
                let manager = try NetworkManager(connection: client)
                let optionsType = try #require(DBusSignature(rawValue: "a{sv}")?.first)
                let settings = try #require(DBusMessageArgument.Dictionary(keyType: .string, valueType: optionsType, []))
                let activation = try await manager.addAndActivateConnection(
                    connection: settings, device: try #require(DBusObjectPath(rawValue: "/device")),
                    specificObject: try #require(DBusObjectPath(rawValue: "/")))
                #expect(activation.path.rawValue == "/settings/1")
                #expect(activation.activeConnection.rawValue == "/active/1")
                do {
                    _ = try await manager.getPermissions()
                    Issue.record("Expected invalid reply signature")
                } catch is DBusProtocolError {}
                let cookie = try await screenSaver.inhibit(applicationName: "test.app", reason: "Playing video")
                #expect(cookie == 42)
                try await screenSaver.unInhibit(cookie: cookie)
                let power = try UPower(connection: client)
                #expect(try await power.onBattery)
                #expect(try await power.getDisplayDevice().rawValue == "/battery")
                let login = try Login1.Manager(connection: client)
                #expect(try await login.canSuspend() == "challenge")
                do {
                    _ = try await login.canReboot()
                    Issue.record("Expected the remote UnknownMethod error")
                } catch let error as DBusError {
                    #expect(error.name == .unknownMethod)
                }
                await client.close()
            } catch {
                await client.close()
                throw error
            }
            await server.close()
        } catch {
            await server.close()
            throw error
        }
    }
}
