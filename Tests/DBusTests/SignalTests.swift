//
//  SignalTests.swift
//  DBusTests
//

import Testing
@testable import DBus

/// Live tests for match rules and signal delivery.
///
/// A connection receives no broadcast signals until it installs a match rule, so these exercise
/// `AddMatch`, the bus's routing, and our local demultiplexing between subscriptions.
@Suite(.serialized, .enabled(if: hasSessionBus, "No session bus is available"))
struct SignalTests {

    /// Await the next signal satisfying `predicate`, or fail after a timeout.
    ///
    /// The bus can deliver unrelated traffic that the rule also matches, so tests filter rather
    /// than assume the first message is the one they want.
    private func next(from stream: AsyncStream<DBusMessage>,
                      timeout: Duration = .seconds(10),
                      where predicate: @escaping @Sendable (DBusMessage) -> Bool)
        async throws -> DBusMessage? {

        return try await withThrowingTaskGroup(of: DBusMessage?.self) { group in

            group.addTask {
                for await message in stream where predicate(message) {
                    return message
                }
                return nil
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }

            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Requesting a well known name makes the bus broadcast `NameOwnerChanged`, which is the
    /// simplest signal to provoke on demand.
    @Test func receivesNameOwnerChanged() async throws {

        let wellKnownName = DBusBusName(rawValue: "com.example.SwiftDBusSignalTest")!

        try await withConnections { observer, owner in

            let stream = try await observer.signals(matching: .nameOwnerChanged(name: wellKnownName))

            let ownerName = try #require(await owner.uniqueName)

            let result = try await owner.requestName(wellKnownName)
            #expect(result == .primaryOwner)

            let signal = try await next(from: stream) { message in
                message.arguments.first?.stringValue == wellKnownName.rawValue
            }

            let received = try #require(signal, "No NameOwnerChanged arrived")

            #expect(received.member?.rawValue == "NameOwnerChanged")
            #expect(received.interface == DBusWellKnown.busInterface)
            #expect(received.arguments.count == 3)

            // Arguments are (name, old owner, new owner); the new owner is the requester.
            #expect(received.arguments[0].stringValue == wellKnownName.rawValue)
            #expect(received.arguments[1].stringValue == "", "There was no previous owner")
            #expect(received.arguments[2].stringValue == ownerName.rawValue)

            let release = try await owner.releaseName(wellKnownName)
            #expect(release == .released)
        }
    }

    /// A signal emitted by an exported object must reach a subscriber on another connection.
    @Test func receivesSignalFromExportedObject() async throws {

        let path = DBusObjectPath(rawValue: "/com/example/Emitter")!
        let interface = DBusInterface(rawValue: "com.example.Emitter")!
        let member = DBusMember(rawValue: "Pinged")!

        try await withConnections { emitter, observer in

            let stream = try await observer.signals(interface: interface, member: member, path: path)

            try await emitter.emit(DBusMessage.Signal(path: path, interface: interface, name: member),
                                   arguments: [.string("payload"), .uint32(7)])

            let signal = try await next(from: stream) { _ in true }
            let received = try #require(signal, "No signal arrived")

            #expect(received.type == .signal)
            #expect(received.path == path)
            #expect(received.interface == interface)
            #expect(received.member == member)
            #expect(received.arguments == [.string("payload"), .uint32(7)])
            #expect(received.sender == (await emitter.uniqueName))
        }
    }

    /// `PropertiesChanged` carries `a{sv}`, so this checks a real dictionary makes the trip.
    @Test func receivesPropertiesChanged() async throws {

        let path = DBusObjectPath(rawValue: "/com/example/Props")!
        let interface = DBusInterface(rawValue: "com.example.Props")!

        try await withConnections { emitter, observer in

            let stream = try await observer.signals(matching: .propertiesChanged(interface: interface,
                                                                                 path: path))

            try await emitter.emitPropertiesChanged(at: path,
                                                    interface: interface,
                                                    changed: ["Greeting": .string("hi"),
                                                              "Count": .uint32(3)],
                                                    invalidated: ["Stale"])

            let signal = try await next(from: stream) { _ in true }
            let received = try #require(signal, "No PropertiesChanged arrived")

            #expect(received.signature.rawValue == "sa{sv}as")
            #expect(received.arguments[0].stringValue == interface.rawValue)

            guard case let .dictionary(changed) = received.arguments[1]
                else { Issue.record("Expected a{sv}, got \(received.arguments[1])"); return }

            var values = [String: DBusMessageArgument]()
            for entry in changed {
                if let key = entry.key.stringValue, let value = entry.value.variantValue {
                    values[key] = value
                }
            }

            #expect(values["Greeting"] == .string("hi"))
            #expect(values["Count"] == .uint32(3))

            guard case let .array(invalidated) = received.arguments[2]
                else { Issue.record("Expected as, got \(received.arguments[2])"); return }

            #expect(invalidated.compactMap { $0.stringValue } == ["Stale"])
        }
    }

    /// Two subscriptions on one connection must each receive only what their own rule matches.
    @Test func subscriptionsAreDemultiplexed() async throws {

        let path = DBusObjectPath(rawValue: "/com/example/Multi")!
        let interface = DBusInterface(rawValue: "com.example.Multi")!
        let first = DBusMember(rawValue: "First")!
        let second = DBusMember(rawValue: "Second")!

        try await withConnections { emitter, observer in

            let firstStream = try await observer.signals(interface: interface, member: first, path: path)
            let secondStream = try await observer.signals(interface: interface, member: second, path: path)

            #expect(await observer.subscriptionCount == 2)

            try await emitter.emit(DBusMessage.Signal(path: path, interface: interface, name: second),
                                   arguments: [.string("to second")])

            // The second stream gets it; the first must not.
            let received = try #require(try await next(from: secondStream) { _ in true })
            #expect(received.member == second)
            #expect(received.arguments.first?.stringValue == "to second")

            let leaked = try await next(from: firstStream, timeout: .seconds(1)) { _ in true }
            #expect(leaked == nil, "A signal leaked into the wrong subscription")
        }
    }

    /// Ending a subscription must remove its match rule, and must not disturb another
    /// subscription that shares the same rule.
    @Test func endingSubscriptionRemovesMatch() async throws {

        let rule = DBusMatchRule.nameOwnerChanged()

        try await withConnection { connection in

            do {
                let stream = try await connection.signals(matching: rule)
                #expect(await connection.subscriptionCount == 1)
                #expect(await connection.matchRuleCounts[rule.rawValue] == 1)

                // A second subscription on the same rule shares the bus-side match.
                let shared = try await connection.signals(matching: rule)
                #expect(await connection.subscriptionCount == 2)
                #expect(await connection.matchRuleCounts[rule.rawValue] == 2)

                _ = stream
                _ = shared
            }

            // Dropping both streams tears the subscriptions down asynchronously.
            var attempts = 0
            while await connection.subscriptionCount > 0, attempts < 50 {
                try await Task.sleep(for: .milliseconds(100))
                attempts += 1
            }

            #expect(await connection.subscriptionCount == 0, "Subscriptions were not cleaned up")
            #expect(await connection.matchRuleCounts[rule.rawValue] == nil,
                    "The match rule reference count was not cleared")
        }
    }

    /// A rule the bus rejects must surface as an error from `signals(matching:)`, not as a
    /// stream that silently never yields.
    @Test func invalidMatchRuleThrows() async throws {

        try await withConnection { connection in

            // arg64 is beyond the maximum index the specification allows.
            var rule = DBusMatchRule(type: .signal)
            rule.arguments = [64: "too far"]

            await #expect(throws: DBusError.self) {
                try await connection.signals(matching: rule)
            }

            #expect(await connection.subscriptionCount == 0, "A failed AddMatch must not leave a subscription")
        }
    }
}
