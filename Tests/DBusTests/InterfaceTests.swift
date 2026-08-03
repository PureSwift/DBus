//
//  InterfaceTests.swift
//  DBusTests
//
//  Created by Alsey Coleman Miller on 10/24/18.
//

import Testing
@testable import DBus

@Suite struct InterfaceTests {

    @Test(arguments: [
        "org.7-zip.Plugin", // '-' is legal in bus names but not interface names
        "org.7zip.Plugin", // an element may not begin with a digit
        "com.example..MusicPlayer1.Track",
        "com.example.MusicPlayer1.Track.",
        "com.example.",
        "com.example.MusicPlayer1.Track@",
        "com.example.MusicPlayer1.Trackñ",
        "",
        "/",
        ".",
        "..",
        "com", // must contain at least one period
        "com.",
        "a.",
        "a.ñ",
        "a.😀",
        ".com.example"
    ])
    func invalid(string: String) throws {

        #expect(DBusInterface(rawValue: string) == nil, "\(string) should be invalid")

        let error = try #require(throws: DBusError.self) {
            try DBusInterface.validate(string)
        }

        #expect(error.name == .invalidArguments)
    }

    @Test(arguments: [
        ("org._7_zip.Plugin", ["org", "_7_zip", "Plugin"]),
        ("a.b", ["a", "b"]),
        ("com.example", ["com", "example"]),
        ("com.example.MusicPlayer1", ["com", "example", "MusicPlayer1"]),
        ("com.example.MusicPlayer1.Track", ["com", "example", "MusicPlayer1", "Track"])
    ])
    func valid(string: String, elements: [String]) throws {

        #expect(throws: Never.self) { try DBusInterface.validate(string) }

        let interface = try #require(DBusInterface(rawValue: string))

        #expect(interface.rawValue == string)
        #expect(interface.rawValue == String(interface.elements))
        #expect(interface.elements.map { $0.rawValue } == elements)
        #expect(Array(interface) == interface.elements)
        #expect(interface.count > 1)
        #expect(interface == DBusInterface(interface.elements))
        #expect(interface.hashValue == string.hashValue)

        // Mutating clears the cached string.
        var mutable = interface
        mutable.append(DBusInterface.Element(rawValue: "Object1")!)
        #expect(mutable.string == nil)
        #expect(mutable != interface)
        #expect(mutable.rawValue != interface.rawValue)
        #expect(mutable.elements != interface.elements)
    }

    @Test func requiresAtLeastTwoElements() {

        #expect(DBusInterface([]) == nil)
        #expect(DBusInterface([DBusInterface.Element(rawValue: "com")!]) == nil)
        #expect(DBusInterface([
            DBusInterface.Element(rawValue: "com")!,
            DBusInterface.Element(rawValue: "example")!
        ]) != nil)
    }

    /// The limit is 255 bytes and applies to the whole name.
    @Test func rejectsOverlongName() {

        let long = String(repeating: "a", count: 128) + "." + String(repeating: "b", count: 126)
        #expect(long.utf8.count == 255)
        #expect(DBusInterface(rawValue: long) != nil)

        #expect(DBusInterface(rawValue: long + "c") == nil)
    }

    @Test func elementRules() {

        // Only "[A-Z][a-z][0-9]_", and never leading with a digit.
        #expect(DBusInterface.Element(rawValue: "_7_zip") != nil)
        #expect(DBusInterface.Element(rawValue: "Track1") != nil)
        #expect(DBusInterface.Element(rawValue: "7zip") == nil)
        #expect(DBusInterface.Element(rawValue: "") == nil)
        #expect(DBusInterface.Element(rawValue: "a-b") == nil)
        #expect(DBusInterface.Element(rawValue: "a.b") == nil)
    }

    /// Error names follow interface name syntax.
    @Test func errorNamesUseInterfaceSyntax() {

        #expect(DBusError.Name(rawValue: "org.freedesktop.DBus.Error.Failed") != nil)
        #expect(DBusError.Name(rawValue: "NotNamespaced") == nil)
        #expect(DBusError.Name(rawValue: "") == nil)
    }
}
