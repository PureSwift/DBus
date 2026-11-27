import Testing
import Foundation
import DBus
import Avahi
import SecretService
import DesktopNotifications
import StatusNotifier
import FreedesktopPortal
import MPRIS
import Polkit
import UDisks2

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DBUS_SESSION_BUS_ADDRESS"] != nil,
                            "Requires a private session bus"))
struct RemainingServiceWireTests {
    @Test func generatedServices() async throws {
        let server = try await DBusConnection.connect(to: .session)
        do {
            let client = try await DBusConnection.connect(to: .session)
            do {
                try await exerciseServices(server: server, client: client)
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

    private func exerciseServices(server: DBusConnection, client: DBusConnection) async throws {
        let path = try #require(DBusObjectPath(rawValue: "/result"))
        let strings = try #require(DBusMessageArgument.Array(type: .string, []))
        let paths = try #require(DBusMessageArgument.Array(type: .objectPath, []))
        let options = try #require(DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant, []))
        let details = try #require(DBusMessageArgument.Dictionary(keyType: .string, valueType: .string, []))
        let subject = try #require(DBusMessageArgument.Structure([.string("unix-process"), .dictionary(options)]))
        let authorization = try #require(DBusMessageArgument.Structure([.boolean(true), .boolean(false), .dictionary(details)]))
        typealias Fixture = (destination: String, path: String, interface: String, method: String,
                             input: [DBusMessageArgument], output: [DBusMessageArgument])
        let fixtures: [Fixture] = [
            ("org.freedesktop.Avahi", "/", "org.freedesktop.Avahi.Server2", "ServiceBrowserPrepare",
             [.int32(-1), .int32(-1), .string("_hap._tcp"), .string("local"), .uint32(0)], [.objectPath(path)]),
            ("org.freedesktop.secrets", "/org/freedesktop/secrets", "org.freedesktop.Secret.Service", "OpenSession",
             [.string("plain"), .variant(.init(.string("")))], [.variant(.init(.string(""))), .objectPath(path)]),
            ("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify",
             [.string("Test"), .uint32(0), .string(""), .string("Title"), .string("Body"),
              .array(strings), .dictionary(options), .int32(-1)], [.uint32(42)]),
            ("org.example.StatusItem", "/StatusNotifierItem", "org.kde.StatusNotifierItem", "Activate",
             [.int32(12), .int32(34)], []),
            ("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings", "Read",
             [.string("org.freedesktop.appearance"), .string("color-scheme")], [.variant(.init(.uint32(1)))]),
            ("org.mpris.MediaPlayer2.TestPlayer", "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Seek",
             [.int64(-1000)], []),
            ("org.freedesktop.PolicyKit1", "/org/freedesktop/PolicyKit1/Authority", "org.freedesktop.PolicyKit1.Authority", "CheckAuthorization",
             [.struct(subject), .string("org.example.action"), .dictionary(details), .uint32(0), .string("")],
             [.struct(authorization)]),
            ("org.freedesktop.UDisks2", "/org/freedesktop/UDisks2/Manager", "org.freedesktop.UDisks2.Manager", "GetBlockDevices",
             [.dictionary(options)], [.array(paths)])
        ]
        for fixture in fixtures {
            let method = DBusInterfaceImplementation.Method(
                name: try #require(DBusMember(rawValue: fixture.method)),
                inputSignature: DBusSignature(fixture.input.map(\.type)),
                outputSignature: DBusSignature(fixture.output.map(\.type)), handler: { call in
                    #expect(call.arguments == fixture.input)
                    return fixture.output
                })
            await server.export(DBusExportedObject([
                DBusInterfaceImplementation(name: try #require(DBusInterface(rawValue: fixture.interface)), methods: [method])
            ]), at: try #require(DBusObjectPath(rawValue: fixture.path)))
            _ = try await server.requestName(try #require(DBusBusName(rawValue: fixture.destination)))
        }
        let avahi = try Avahi.Server2(connection: client)
        #expect(try await avahi.serviceBrowserPrepare(interfaceIndex: -1, protocolIndex: -1,
                                                     type: "_hap._tcp", domain: "local", flags: 0) == path)
        let secrets = try SecretService.Service(connection: client)
        let session = try await secrets.openSession(algorithm: "plain", input: .init(.string("")))
        #expect(session.output.element == .string(""))
        #expect(session.result == path)
        let notifications = try DesktopNotifications(connection: client)
        #expect(try await notifications.notify(appName: "Test", replacesId: 0, appIcon: "", summary: "Title",
                                              body: "Body", actions: strings, hints: options, timeout: -1) == 42)
        let item = try StatusNotifier.Item(connection: client, destination: "org.example.StatusItem")
        try await item.activate(x: 12, y: 34)
        let settings = try FreedesktopPortal.Settings(connection: client)
        #expect(try await settings.read(namespace: "org.freedesktop.appearance", key: "color-scheme").element == .uint32(1))
        let player = try MPRIS.Player(connection: client, destination: "org.mpris.MediaPlayer2.TestPlayer")
        try await player.seek(offset: -1000)
        let authority = try Polkit.Authority(connection: client)
        #expect(try await authority.checkAuthorization(subject: subject, actionID: "org.example.action", details: details,
                                                      flags: 0, cancellationID: "") == authorization)
        let disks = try UDisks2.Manager(connection: client)
        #expect(try await disks.getBlockDevices(options: options) == paths)
        #expect(throws: DBusProtocolError.self) {
            _ = try MPRIS.Player(connection: client, destination: "invalid")
        }
    }
}
