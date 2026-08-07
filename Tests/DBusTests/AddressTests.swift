//
//  AddressTests.swift
//  DBusTests
//

import Testing
@testable import DBus

@Suite struct AddressTests {

    @Test func unixPath() throws {

        let addresses = try DBusAddress.parse("unix:path=/run/user/1000/bus")

        #expect(addresses.count == 1)
        #expect(addresses[0].transport == "unix")
        #expect(addresses[0]["path"] == "/run/user/1000/bus")
        #expect(try addresses[0].unixSocketAddress() == .path("/run/user/1000/bus"))
    }

    @Test func unixAbstract() throws {

        let addresses = try DBusAddress.parse("unix:abstract=/tmp/dbus-XyZ123,guid=deadbeef")

        #expect(addresses[0]["abstract"] == "/tmp/dbus-XyZ123")
        #expect(addresses[0]["guid"] == "deadbeef")
        #expect(try addresses[0].unixSocketAddress() == .abstract("/tmp/dbus-XyZ123"))
    }

    @Test func alternatives() throws {

        let addresses = try DBusAddress.parse("unix:path=/a;unix:abstract=/b;")

        #expect(addresses.count == 2)
        #expect(try addresses[0].unixSocketAddress() == .path("/a"))
        #expect(try addresses[1].unixSocketAddress() == .abstract("/b"))
    }

    @Test func percentEscaping() throws {

        // Values are percent-encoded; anything outside [-0-9A-Za-z_/.\*] may be escaped.
        let addresses = try DBusAddress.parse("unix:path=/tmp/dbus%2Dtest%20one")

        #expect(addresses[0]["path"] == "/tmp/dbus-test one")

        #expect(DBusAddress.unescape("%C3%B1") == "ñ")
        #expect(DBusAddress.unescape("plain") == "plain")
        #expect(DBusAddress.unescape("%2f") == "/") // lowercase hex is accepted
        #expect(DBusAddress.unescape("%2") == nil) // truncated escape
        #expect(DBusAddress.unescape("%ZZ") == nil) // non-hex digits
    }

    @Test func tcpTransportIsRejectedForSockets() throws {

        let addresses = try DBusAddress.parse("tcp:host=127.0.0.1,port=1234")

        #expect(addresses[0].transport == "tcp")
        #expect(addresses[0]["port"] == "1234")

        // Parsing succeeds, but this branch only implements the unix transport.
        #expect(throws: (any Error).self) { try addresses[0].unixSocketAddress() }
    }

    @Test(arguments: [
        "",
        ";",
        "unix", // no colon
        ":path=/a", // no transport
        "unix:path", // parameter without '='
        "unix:=/a" // parameter without a key
    ])
    func invalidAddress(string: String) {

        #expect(throws: (any Error).self, "\(string) should be invalid") {
            try DBusAddress.parse(string)
        }
    }

    @Test func unixAddressWithoutPathIsRejected() throws {

        let addresses = try DBusAddress.parse("unix:guid=abc")

        #expect(throws: (any Error).self) { try addresses[0].unixSocketAddress() }
    }

    // MARK: - Socket Address

    @Test func filesystemSocketAddressBytes() throws {

        let address = DBusUnixSocketAddress.path("/run/user/1000/bus")
        let (bytes, length) = try address.pathBytes()

        // A filesystem path is NUL terminated, and the length covers sun_family plus the
        // terminated path.
        #expect(bytes.last == 0)
        #expect(Array(bytes.dropLast()) == Array("/run/user/1000/bus".utf8))
        #expect(Int(length) == DBusUnixSocketAddress.pathOffset + bytes.count)
    }

    /// The abstract namespace is why this package defines its own socket address type:
    /// `Socket.UnixSocketAddress` writes `sun_path` as a C string and cannot represent it.
    @Test func abstractSocketAddressBytes() throws {

        let address = DBusUnixSocketAddress.abstract("/tmp/dbus-XyZ")
        let (bytes, length) = try address.pathBytes()

        // Leading NUL, then the name, with no terminator: the length delimits the name.
        #expect(bytes.first == 0)
        #expect(Array(bytes.dropFirst()) == Array("/tmp/dbus-XyZ".utf8))
        #expect(bytes.last != 0)
        #expect(Int(length) == DBusUnixSocketAddress.pathOffset + 1 + "/tmp/dbus-XyZ".utf8.count)
    }

    @Test func overlongSocketNameIsRejected() {

        let long = String(repeating: "a", count: DBusUnixSocketAddress.pathCapacity + 1)

        #expect(throws: (any Error).self) { try DBusUnixSocketAddress.path(long).pathBytes() }
        #expect(throws: (any Error).self) { try DBusUnixSocketAddress.abstract(long).pathBytes() }
    }

    @Test func socketAddressDescription() {

        #expect(DBusUnixSocketAddress.path("/a").description == "unix:path=/a")
        #expect(DBusUnixSocketAddress.abstract("b").description == "unix:abstract=b")
    }
}
