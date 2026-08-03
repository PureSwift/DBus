//
//  ObjectPathTests.swift
//  DBusTests
//
//  Created by Alsey Coleman Miller on 10/21/18.
//

import Foundation
import Testing
@testable import DBus

@Suite struct ObjectPathTests {

    @Test(arguments: [
        "",
        "/com//example/",
        "/com/example/ñanó",
        "/com/example/b$@s1",
        "/com/example/bus1/",
        "/com/example/😀",
        "//",
        "///",
        "\\",
        "/com//example", // multiple '/' cannot occur in sequence
        "/com/example//",
        "//com/example",
        "com/example", // must begin with '/'
        "/com/exa mple",
        "/com/example/bus-1" // '-' is legal in bus names but not object paths
    ])
    func invalid(string: String) throws {

        #expect(DBusObjectPath(rawValue: string) == nil, "\(string) should be invalid")

        let error = try #require(throws: DBusError.self) {
            try DBusObjectPath.validate(string)
        }

        #expect(error.name == .invalidArguments)
    }

    @Test(arguments: [
        ("/", [String]()),
        ("/com", ["com"]),
        ("/com/example/bus1", ["com", "example", "bus1"]),
        ("/_", ["_"]),
        ("/a0/B1", ["a0", "B1"])
    ])
    func valid(string: String, elements: [String]) throws {

        #expect(throws: Never.self) { try DBusObjectPath.validate(string) }

        let objectPath = try #require(DBusObjectPath(rawValue: string))

        #expect(objectPath.map { $0.rawValue } == elements)
        #expect(objectPath.rawValue == string)
        #expect(objectPath.description == string)
        #expect(objectPath.hashValue == string.hashValue)

        #expect(objectPath.count == elements.count)

        for (offset, element) in objectPath.enumerated() {
            #expect(elements[offset] == element.rawValue)
        }

        // Building from elements must produce an equal value.
        let fromElements = DBusObjectPath(elements.compactMap { DBusObjectPath.Element(rawValue: $0) })
        #expect(fromElements.map { $0.rawValue } == elements)
        #expect(fromElements == objectPath)
        #expect(fromElements.rawValue == objectPath.rawValue)
    }

    @Test func empty() {

        let objectPath = DBusObjectPath()

        #expect(objectPath.rawValue == "/")
        #expect(objectPath.isEmpty)
        #expect(objectPath == [])
        #expect(DBusObjectPath() == DBusObjectPath(rawValue: "/"))
        #expect(DBusObjectPath() != DBusObjectPath(rawValue: "/com/example")!)

        // Mutating a copy must not disturb the original.
        var mutable = DBusObjectPath()
        #expect(mutable == objectPath)
        mutable.append(DBusObjectPath.Element(rawValue: "mutation1")!)
        mutable.removeLast()
        #expect(mutable == objectPath)
        #expect(mutable.rawValue == objectPath.rawValue)
    }

    /// The cached string is dropped on mutation, so `rawValue` must rebuild it correctly from
    /// many tasks at once without observing a torn value.
    @Test func concurrentReadsAndCopies() async {

        let string = "/com/example/bus1"

        let objectPath = DBusObjectPath([
            DBusObjectPath.Element(rawValue: "com")!,
            DBusObjectPath.Element(rawValue: "example")!,
            DBusObjectPath.Element(rawValue: "bus1")!
        ])

        // Built by mutation, so its cached string is nil and `rawValue` has to be rebuilt.
        var built: DBusObjectPath = []
        #expect(built.rawValue == "/")
        built.append(DBusObjectPath.Element(rawValue: "example")!)
        #expect(built.rawValue == "/example")
        built.append(DBusObjectPath.Element(rawValue: "mutation")!)

        let shared = built
        let readCopy = objectPath

        await withTaskGroup(of: Void.self) { group in

            for index in 0 ..< 100 {

                group.addTask {

                    #expect(shared.rawValue == "/example/mutation")
                    #expect(readCopy.rawValue == string)

                    var copy = shared
                    copy.append(DBusObjectPath.Element(rawValue: "n\(index)")!)
                    #expect(copy.rawValue == "/example/mutation/n\(index)")
                    #expect(shared.rawValue == "/example/mutation")

                    var mutateCopy = readCopy
                    mutateCopy.append(DBusObjectPath.Element(rawValue: "mutation")!)
                    #expect(readCopy != mutateCopy)
                    #expect(mutateCopy.rawValue != string)
                }
            }
        }

        #expect(objectPath.rawValue == string)
        #expect(shared.rawValue == "/example/mutation")
    }

    @Test func namespaceContainment() {

        let parent = DBusObjectPath(rawValue: "/com/example")!

        #expect(parent.isEqualToOrDescendant(of: parent))
        #expect(DBusObjectPath(rawValue: "/com/example/thing")!.isEqualToOrDescendant(of: parent))
        #expect(!DBusObjectPath(rawValue: "/com")!.isEqualToOrDescendant(of: parent))
        #expect(!DBusObjectPath(rawValue: "/com/other")!.isEqualToOrDescendant(of: parent))

        // The root is an ancestor of everything.
        #expect(parent.isEqualToOrDescendant(of: DBusObjectPath()))
    }
}
