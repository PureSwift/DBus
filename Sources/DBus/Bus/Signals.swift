//
//  Signals.swift
//  DBus
//

// MARK: - Match Rules

public extension DBusConnection {

    /// Ask the bus to start delivering messages that satisfy the rule.
    ///
    /// - Note: The bus reference counts match rules per connection, so adding the same rule
    /// twice requires removing it twice.
    func addMatch(_ rule: DBusMatchRule) async throws {

        try await callBus("AddMatch", arguments: [.string(rule.rawValue)])
    }

    /// Ask the bus to stop delivering messages that satisfy the rule.
    func removeMatch(_ rule: DBusMatchRule) async throws {

        try await callBus("RemoveMatch", arguments: [.string(rule.rawValue)])
    }
}

// MARK: - Subscriptions

public extension DBusConnection {

    /// Subscribe to signals matching a rule.
    ///
    /// Installs the match rule with the bus, then yields every matching message until the
    /// stream is cancelled or the connection closes. Cancelling the stream, or simply dropping
    /// it, removes the match rule.
    ///
    /// ```swift
    /// let signals = try await connection.signals(matching: .nameOwnerChanged())
    /// for await signal in signals {
    ///     print(signal.arguments)
    /// }
    /// ```
    ///
    /// - Parameter bufferingPolicy: How many messages to hold if the consumer falls behind.
    /// Unbounded by default, so no signal is silently dropped; bound it when subscribing to a
    /// high volume rule.
    func signals(matching rule: DBusMatchRule,
                 bufferingPolicy: AsyncStream<DBusMessage>.Continuation.BufferingPolicy = .unbounded)
        async throws -> AsyncStream<DBusMessage> {

        // Install the rule with the bus first, so a failure surfaces here rather than as a
        // stream that silently never yields.
        try await addMatchIfNeeded(rule)

        let identifier = nextSubscriptionID()

        let (stream, continuation) = AsyncStream<DBusMessage>.makeStream(bufferingPolicy: bufferingPolicy)

        continuation.onTermination = { [weak self] _ in
            // Runs on whichever task terminated the stream, so hop back onto the actor.
            Task { await self?.endSubscription(identifier) }
        }

        subscriptions[identifier] = Subscription(rule: rule, continuation: continuation)

        return stream
    }

    /// Subscribe to a signal by interface and member.
    func signals(interface: DBusInterface,
                 member: DBusMember? = nil,
                 path: DBusObjectPath? = nil,
                 sender: DBusBusName? = nil) async throws -> AsyncStream<DBusMessage> {

        return try await signals(matching: .signal(interface: interface,
                                                   member: member,
                                                   path: path,
                                                   sender: sender))
    }
}

// MARK: - Internal

internal extension DBusConnection {

    /// Install the rule with the bus unless another subscription already did.
    func addMatchIfNeeded(_ rule: DBusMatchRule) async throws {

        let key = rule.rawValue
        let count = matchRuleCounts[key] ?? 0

        if count == 0 {
            try await addMatch(rule)
        }

        matchRuleCounts[key] = count + 1
    }

    /// Tear down a subscription and, if it was the last one using its rule, remove the match.
    func endSubscription(_ identifier: UInt64) async {

        guard let subscription = subscriptions.removeValue(forKey: identifier)
            else { return }

        let key = subscription.rule.rawValue
        let count = matchRuleCounts[key] ?? 0

        guard count > 1 else {

            matchRuleCounts[key] = nil

            // Best effort: the connection may already be closing, and there is nowhere to
            // report a failure to at this point.
            if isConnected {
                try? await removeMatch(subscription.rule)
            }

            return
        }

        matchRuleCounts[key] = count - 1
    }

    /// The number of active subscriptions, for tests.
    var subscriptionCount: Int {

        return subscriptions.count
    }
}
