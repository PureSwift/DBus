//
//  MatchRuleTests.swift
//  DBusTests
//

import Testing
@testable import DBus

@Suite struct MatchRuleTests {

    private let interface = DBusInterface(rawValue: "com.example.Thing")!
    private let member = DBusMember(rawValue: "Changed")!
    private let path = DBusObjectPath(rawValue: "/com/example/thing")!

    private func signal(interface: String = "com.example.Thing",
                        member: String = "Changed",
                        path: String = "/com/example/thing",
                        arguments: [DBusMessageArgument] = []) -> DBusMessage {

        return DBusMessage(signal: DBusMessage.Signal(
            path: DBusObjectPath(rawValue: path)!,
            interface: DBusInterface(rawValue: interface)!,
            name: DBusMember(rawValue: member)!
        ), arguments: arguments)
    }

    // MARK: - Encoding

    @Test func signalRuleEncoding() {

        let rule = DBusMatchRule.signal(interface: interface, member: member, path: path)

        #expect(rule.rawValue
                == "type='signal',interface='com.example.Thing',member='Changed',path='/com/example/thing'")
    }

    @Test func emptyRuleEncodesToEmptyString() {

        #expect(DBusMatchRule().rawValue == "")
    }

    @Test func allFieldsEncoding() {

        var rule = DBusMatchRule(type: .methodCall,
                                 sender: DBusBusName(rawValue: "com.example.Sender")!,
                                 interface: interface,
                                 member: member,
                                 path: path,
                                 destination: DBusBusName(rawValue: ":1.5")!,
                                 eavesdrop: true)
        rule.arguments = [0: "first", 2: "third"]
        rule.argument0Namespace = "com.example"
        rule.argument0Path = "/com/example/"

        #expect(rule.rawValue == [
            "type='method_call'",
            "sender='com.example.Sender'",
            "interface='com.example.Thing'",
            "member='Changed'",
            "path='/com/example/thing'",
            "destination=':1.5'",
            "arg0='first'",
            "arg2='third'",
            "arg0namespace='com.example'",
            "arg0path='/com/example/'",
            "eavesdrop='true'"
        ].joined(separator: ","))
    }

    @Test func pathNamespaceEncoding() {

        let rule = DBusMatchRule(pathNamespace: DBusObjectPath(rawValue: "/com/example")!)

        #expect(rule.rawValue == "path_namespace='/com/example'")
    }

    @Test func messageTypeNames() {

        #expect(DBusMessageType.methodCall.matchRuleName == "method_call")
        #expect(DBusMessageType.methodReturn.matchRuleName == "method_return")
        #expect(DBusMessageType.error.matchRuleName == "error")
        #expect(DBusMessageType.signal.matchRuleName == "signal")
    }

    /// A literal apostrophe cannot appear inside single quotes, so it is written by closing the
    /// quote, escaping it, and reopening.
    @Test func apostropheEscaping() {

        #expect(DBusMatchRule.escape("plain") == "'plain'")
        #expect(DBusMatchRule.escape("it's") == "'it'\\''s'")
        #expect(DBusMatchRule.escape("'") == "''\\'''")
        #expect(DBusMatchRule.escape("") == "''")

        var rule = DBusMatchRule()
        rule.arguments = [0: "it's"]
        #expect(rule.rawValue == "arg0='it'\\''s'")
    }

    /// The rule string is the key used to reference count AddMatch, so it must be stable.
    @Test func argumentOrderIsDeterministic() {

        var rule = DBusMatchRule()
        rule.arguments = [3: "d", 1: "b", 0: "a", 2: "c"]

        #expect(rule.rawValue == "arg0='a',arg1='b',arg2='c',arg3='d'")
        #expect(rule.rawValue == rule.rawValue)
    }

    @Test func nameOwnerChangedConvenience() {

        let rule = DBusMatchRule.nameOwnerChanged(name: DBusBusName(rawValue: "com.example.App")!)

        #expect(rule.rawValue == [
            "type='signal'",
            "sender='org.freedesktop.DBus'",
            "interface='org.freedesktop.DBus'",
            "member='NameOwnerChanged'",
            "path='/org/freedesktop/DBus'",
            "arg0='com.example.App'"
        ].joined(separator: ","))
    }

    @Test func propertiesChangedConvenience() {

        let rule = DBusMatchRule.propertiesChanged(interface: interface, path: path)

        #expect(rule.interface == DBusWellKnown.propertiesInterface)
        #expect(rule.member?.rawValue == "PropertiesChanged")
        #expect(rule.arguments[0] == "com.example.Thing")
        #expect(rule.path == path)
    }

    // MARK: - Matching

    @Test func emptyRuleMatchesEverything() {

        #expect(DBusMatchRule().matches(signal()))
        #expect(DBusMatchRule().matches(DBusMessage(type: .methodCall)))
    }

    @Test func typeMatching() {

        #expect(DBusMatchRule(type: .signal).matches(signal()))
        #expect(!DBusMatchRule(type: .methodCall).matches(signal()))
    }

    @Test func interfaceMemberPathMatching() {

        let rule = DBusMatchRule.signal(interface: interface, member: member, path: path)

        #expect(rule.matches(signal()))
        #expect(!rule.matches(signal(interface: "com.example.Other")))
        #expect(!rule.matches(signal(member: "Other")))
        #expect(!rule.matches(signal(path: "/com/example/other")))
    }

    @Test func pathNamespaceMatching() {

        let rule = DBusMatchRule(pathNamespace: DBusObjectPath(rawValue: "/com/example")!)

        #expect(rule.matches(signal(path: "/com/example")), "The namespace itself matches")
        #expect(rule.matches(signal(path: "/com/example/thing")))
        #expect(rule.matches(signal(path: "/com/example/thing/nested")))
        #expect(!rule.matches(signal(path: "/com/other")))
        #expect(!rule.matches(signal(path: "/com")), "A parent is not in the namespace")

        // A path that shares a textual prefix but not a path prefix must not match.
        #expect(!rule.matches(signal(path: "/com/exampleother")))
    }

    @Test func argumentMatching() {

        var rule = DBusMatchRule()
        rule.arguments = [0: "hello", 1: "world"]

        #expect(rule.matches(signal(arguments: [.string("hello"), .string("world")])))
        #expect(!rule.matches(signal(arguments: [.string("hello")])), "Missing argument 1")
        #expect(!rule.matches(signal(arguments: [.string("hello"), .string("other")])))
        #expect(!rule.matches(signal(arguments: [.string("hello"), .int32(2)])),
                "Only string-like arguments can be matched")
    }

    @Test func objectPathArgumentIsMatchable() {

        var rule = DBusMatchRule()
        rule.arguments = [0: "/com/example/thing"]

        #expect(rule.matches(signal(arguments: [
            .objectPath(DBusObjectPath(rawValue: "/com/example/thing")!)
        ])))
    }

    @Test func argument0NamespaceMatching() {

        var rule = DBusMatchRule()
        rule.argument0Namespace = "com.example"

        #expect(rule.matches(signal(arguments: [.string("com.example")])))
        #expect(rule.matches(signal(arguments: [.string("com.example.App")])))
        #expect(!rule.matches(signal(arguments: [.string("com.examplefoo")])),
                "A textual prefix is not a namespace prefix")
        #expect(!rule.matches(signal(arguments: [.string("org.example.App")])))
        #expect(!rule.matches(signal(arguments: [])))
    }

    @Test func argument0PathMatching() {

        var rule = DBusMatchRule()
        rule.argument0Path = "/aa/bb/"

        // Equal, or either one a path prefix of the other where the shorter ends in '/'.
        #expect(rule.matches(signal(arguments: [.string("/aa/bb/")])))
        #expect(rule.matches(signal(arguments: [.string("/aa/bb/cc")])))
        #expect(rule.matches(signal(arguments: [.string("/aa/")])))
        #expect(!rule.matches(signal(arguments: [.string("/aa/cc/")])))
    }

    @Test func senderAndDestinationMatching() {

        var message = signal()
        message.sender = DBusBusName(rawValue: ":1.5")!
        message.destination = DBusBusName(rawValue: ":1.9")!

        #expect(DBusMatchRule(sender: DBusBusName(rawValue: ":1.5")!).matches(message))
        #expect(!DBusMatchRule(sender: DBusBusName(rawValue: ":1.6")!).matches(message))
        #expect(DBusMatchRule(destination: DBusBusName(rawValue: ":1.9")!).matches(message))
        #expect(!DBusMatchRule(destination: DBusBusName(rawValue: ":1.8")!).matches(message))
    }
}
