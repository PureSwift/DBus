//
//  NameTests.swift
//  DBusTests
//

import Testing
@testable import DBus

/// Tests for `DBusMember` and `DBusBusName`.
///
/// Both types validated purely by delegating to `dbus_validate_member` /
/// `dbus_validate_bus_name` before the pure-Swift rewrite, so these rules had no coverage.
@Suite struct NameTests {

    // MARK: - Member

    @Test(arguments: [
        "GetItems",
        "ItemsChanged",
        "a",
        "_",
        "_7",
        "Get",
        "GetAll",
        "PropertiesChanged",
        "Introspect",
        "A1_b2_C3"
    ])
    func validMember(string: String) throws {

        #expect(throws: Never.self) { try DBusMember.validate(string) }
        #expect(DBusMember(rawValue: string)?.rawValue == string)
        #expect(DBusMember(rawValue: string)?.description == string)
    }

    @Test(arguments: [
        "", // must be at least 1 byte
        "1", // may not begin with a digit
        "1Get",
        "Get.All", // must not contain a period
        ".",
        "Get-All", // '-' is legal in bus names but not members
        "Get Items",
        "Getñ", // ASCII only
        "Get😀"
    ])
    func invalidMember(string: String) throws {

        #expect(DBusMember(rawValue: string) == nil, "\(string) should be invalid")

        let error = try #require(throws: DBusError.self) {
            try DBusMember.validate(string)
        }

        #expect(error.name == .invalidArguments)
    }

    @Test func memberLengthLimit() {

        #expect(DBusMember(rawValue: String(repeating: "a", count: 255)) != nil)
        #expect(DBusMember(rawValue: String(repeating: "a", count: 256)) == nil)
    }

    // MARK: - Bus Name

    @Test(arguments: [
        "org.freedesktop.DBus",
        "com.example.MusicPlayer1",
        "a.b",
        "org._7_zip.Archiver",
        "com.example.Music-Player", // '-' is discouraged but legal
        ":1.0", // unique connection name
        ":1.42",
        ":0.1",
        "org.freedesktop.NetworkManager"
    ])
    func validBusName(string: String) throws {

        #expect(throws: Never.self) { try DBusBusName.validate(string) }
        #expect(DBusBusName(rawValue: string)?.rawValue == string)
    }

    @Test(arguments: [
        "", // must be at least 1 byte
        "org", // must contain at least one period
        ".org.freedesktop", // must not begin with a period
        "org.freedesktop.", // no trailing period
        "org..freedesktop", // no empty element
        "org.7zip.Archiver", // a well known name may not have an element beginning with a digit
        "1.0", // only legal with the ':' prefix
        ":", // a colon alone is not a name
        ":1", // still needs at least two elements
        "org.freedesktop.DBus@",
        "org.freedesktopñ.DBus"
    ])
    func invalidBusName(string: String) throws {

        #expect(DBusBusName(rawValue: string) == nil, "\(string) should be invalid")

        let error = try #require(throws: DBusError.self) {
            try DBusBusName.validate(string)
        }

        #expect(error.name == .invalidArguments)
    }

    @Test func busNameLengthLimit() {

        let long = String(repeating: "a", count: 128) + "." + String(repeating: "b", count: 126)
        #expect(long.utf8.count == 255)
        #expect(DBusBusName(rawValue: long) != nil)
        #expect(DBusBusName(rawValue: long + "c") == nil)
    }

    /// Only elements of a unique connection name may begin with a digit.
    @Test func uniqueNames() {

        #expect(DBusBusName(rawValue: ":1.0")?.isUnique == true)
        #expect(DBusBusName(rawValue: "org.freedesktop.DBus")?.isUnique == false)
        #expect(DBusBusName(rawValue: ":1.0") != nil)
        #expect(DBusBusName(rawValue: "1.0") == nil)
    }
}
