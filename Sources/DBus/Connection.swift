//
//  Connection.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import Foundation
import Socket

/// A connection to a D-Bus peer, usually a message bus daemon.
///
/// The connection owns a socket, performs the SASL handshake, and runs a read loop that frames
/// incoming bytes into messages and matches replies to the calls that are waiting for them.
///
/// - Note: An actor rather than a class. All mutable state — the serial counter, the table of
/// outstanding calls, the read buffer — is isolated, so the connection can be shared freely.
public actor DBusConnection {

    // MARK: - Properties

    /// The unique name the bus assigned to this connection, once `Hello` has completed.
    public private(set) var uniqueName: DBusBusName?

    /// The server's GUID, from the SASL handshake.
    public private(set) var serverGUID: String?

    /// Whether the server agreed to Unix file descriptor passing.
    ///
    /// - Note: Negotiated but not yet acted on; descriptors are not transferred.
    public private(set) var unixFileDescriptorsSupported = false

    /// Whether the connection is still usable.
    public private(set) var isConnected = false

    // MARK: - Internal Properties

    private let socket: Socket

    /// The serial to assign to the next outgoing message.
    private var lastSerial: UInt32 = 0

    /// Calls waiting for a reply, keyed by the serial of the call.
    private var pendingReplies: [UInt32: CheckedContinuation<DBusMessage, Error>] = [:]

    /// Serials that have been sent but not yet awaited.
    private var outstanding: Set<UInt32> = []

    /// Replies that arrived before the caller began waiting.
    private var earlyReplies: [UInt32: Result<DBusMessage, Error>] = [:]

    /// Bytes received but not yet framed into a complete message.
    private var readBuffer: [UInt8] = []

    /// The task draining the socket.
    private var readTask: Task<Void, Never>?

    /// Invoked for messages that are not replies and that nothing else consumed.
    internal var messageHandler: (@Sendable (DBusMessage) -> Void)?

    /// Active signal subscriptions, keyed by an identifier private to this connection.
    internal var subscriptions: [UInt64: Subscription] = [:]

    /// How many subscriptions reference each match rule string.
    ///
    /// `AddMatch` and `RemoveMatch` are reference counted by the bus per connection, but
    /// counting here keeps the number of round trips down and makes removal exact.
    internal var matchRuleCounts: [String: Int] = [:]

    /// The identifier to assign to the next subscription.
    private var lastSubscriptionID: UInt64 = 0

    /// Objects exported by this connection, keyed by object path.
    internal var exportedObjects: [DBusObjectPath: DBusExportedObject] = [:]

    /// How many bytes to request per read.
    private static let readChunkSize = 16 * 1024

    /// The default time to wait for a reply, matching the reference implementation.
    public static let defaultTimeout: Duration = .seconds(25)

    // MARK: - Initialization

    private init(socket: Socket) {

        self.socket = socket
    }

    deinit {

        readTask?.cancel()
    }

    /// A live signal subscription.
    internal struct Subscription {

        let rule: DBusMatchRule

        let continuation: AsyncStream<DBusMessage>.Continuation
    }

    /// Allocate an identifier for a new subscription.
    internal func nextSubscriptionID() -> UInt64 {

        lastSubscriptionID += 1
        return lastSubscriptionID
    }
}

// MARK: - Connecting

public extension DBusConnection {

    /// Connect to a well known bus.
    static func connect(to busType: DBusBusType,
                        mechanisms: [DBusAuthenticationMechanism] = [.external, .anonymous]) async throws -> DBusConnection {

        let addresses = try DBusAddress.addresses(for: busType)

        var lastError: Error = DBusProtocolError.invalidAddress("No addresses")

        // An address string may list alternatives; try each in turn.
        for address in addresses {

            do {
                return try await connect(to: try address.unixSocketAddress(), mechanisms: mechanisms)
            }
            catch {
                lastError = error
            }
        }

        throw lastError
    }

    /// Connect to a bus at a specific socket address.
    static func connect(to address: DBusUnixSocketAddress,
                        mechanisms: [DBusAuthenticationMechanism] = [.external, .anonymous]) async throws -> DBusConnection {

        let socket = try await Socket(DBusUnixProtocol.stream)

        do {
            try await socket.connect(to: address)
        }
        catch {
            await socket.close()
            throw error
        }

        let connection = DBusConnection(socket: socket)

        do {
            try await connection.handshake(mechanisms: mechanisms)
            try await connection.hello()
        }
        catch {
            await connection.close()
            throw error
        }

        return connection
    }

    /// Parse an address string and connect to the first alternative that works.
    static func connect(to addressString: String,
                        mechanisms: [DBusAuthenticationMechanism] = [.external, .anonymous]) async throws -> DBusConnection {

        let addresses = try DBusAddress.parse(addressString)

        var lastError: Error = DBusProtocolError.invalidAddress(addressString)

        for address in addresses {

            do {
                return try await connect(to: try address.unixSocketAddress(), mechanisms: mechanisms)
            }
            catch {
                lastError = error
            }
        }

        throw lastError
    }
}

// MARK: - Handshake

internal extension DBusConnection {

    /// Run the SASL handshake, then start the read loop.
    func handshake(mechanisms: [DBusAuthenticationMechanism]) async throws {

        var client = DBusSASLClient(mechanisms: mechanisms, userID: ProcessEnvironment.userID)
        var buffer = DBusSASLLineBuffer()

        try await writeAll(client.start())

        while client.isReady == false {

            // Drain any lines already buffered before reading more.
            if let line = try buffer.next() {

                let response = try DBusSASLResponse(line: line)

                if let reply = try client.handle(response) {
                    try await writeAll(reply)
                }

                continue
            }

            let data = try await socket.read(DBusConnection.readChunkSize)

            guard data.isEmpty == false
                else { throw DBusProtocolError.endOfStream }

            buffer.append(data)
        }

        serverGUID = client.serverGUID
        unixFileDescriptorsSupported = client.unixFileDescriptorsSupported

        // Bytes after the final CRLF are the first bytes of the message stream.
        readBuffer = buffer.remainder
        isConnected = true

        startReading()
    }

    /// Send `Hello` to obtain a unique name, which every connection must do first.
    func hello() async throws {

        let call = DBusMessage.MethodCall(
            destination: DBusBusName(rawValue: "org.freedesktop.DBus")!,
            path: DBusObjectPath(rawValue: "/org/freedesktop/DBus")!,
            interface: DBusInterface(rawValue: "org.freedesktop.DBus")!,
            method: DBusMember(rawValue: "Hello")!
        )

        let reply = try await send(DBusMessage(methodCall: call))

        guard case let .string(name)? = reply.arguments.first,
            let busName = DBusBusName(rawValue: name)
            else { throw DBusProtocolError.invalidValue("Hello did not return a unique name") }

        uniqueName = busName
    }
}

// MARK: - Sending

public extension DBusConnection {

    /// Send a method call and wait for its reply.
    ///
    /// - Throws: The `DBusError` carried by an error reply, or `DBusProtocolError` if the
    /// connection fails or the reply does not arrive within `timeout`.
    func send(_ message: DBusMessage,
              timeout: Duration? = DBusConnection.defaultTimeout) async throws -> DBusMessage {

        let serial = try await transmit(message)

        return try await awaitReply(serial: serial, timeout: timeout)
    }

    /// Send a message without waiting for a reply.
    ///
    /// - Returns: The serial assigned to the message.
    @discardableResult
    func send(oneWay message: DBusMessage) async throws -> UInt32 {

        var message = message
        message.flags.insert(.noReplyExpected)

        return try await transmit(message, expectsReply: false)
    }

    /// Set the handler invoked for messages that are not replies to outstanding calls.
    ///
    /// - Note: Signals are only delivered once a matching rule has been added with `AddMatch`,
    /// which this branch does not yet wrap.
    func setMessageHandler(_ handler: (@Sendable (DBusMessage) -> Void)?) {

        self.messageHandler = handler
    }

    /// Close the connection and fail every outstanding call.
    ///
    /// - Note: `isConnected` is cleared *before* the socket is closed. Closing releases the
    /// file descriptor number immediately, while the pending read is aborted asynchronously, so
    /// the loop can wake up after a new connection has already been given the same number. It
    /// re-checks `isConnected` at the top of every iteration and so never issues another read
    /// against the reused descriptor.
    ///
    /// Waiting here for the read loop to finish would be stronger, but `Socket.remove` skips
    /// aborting the pending read if the descriptor has already been removed, so the wait can
    /// never be guaranteed to end.
    func close() async {

        guard isConnected || readTask != nil
            else { return } // already closed

        isConnected = false

        failAll(with: DBusError(name: .disconnected, message: "The connection was closed"))

        readTask?.cancel()
        readTask = nil

        await socket.close()
    }
}

// MARK: - Internal

private extension DBusConnection {

    /// Assign a serial and write the message.
    @discardableResult
    func transmit(_ message: DBusMessage, expectsReply: Bool = true) async throws -> UInt32 {

        guard isConnected
            else { throw DBusError(name: .disconnected, message: "The connection is not open") }

        var message = message
        message.serial = nextSerial()

        let bytes = try message.encode()

        // Register before writing: `writeAll` suspends, so the reply can arrive before this
        // call resumes.
        if expectsReply {
            outstanding.insert(message.serial)
        }

        do {
            try await writeAll(bytes)
        }
        catch {
            outstanding.remove(message.serial)
            earlyReplies[message.serial] = nil
            throw error
        }

        return message.serial
    }

    /// The next serial. Serials wrap and never take the value zero, which means "unset".
    func nextSerial() -> UInt32 {

        lastSerial = lastSerial &+ 1

        if lastSerial == 0 {
            lastSerial = 1
        }

        return lastSerial
    }

    func awaitReply(serial: UInt32, timeout: Duration?) async throws -> DBusMessage {

        // A timer that fails the call if no reply arrives. Both this and the read loop run on
        // the actor, and each removes the entry before resuming, so the continuation is
        // resumed exactly once.
        let timeoutTask: Task<Void, Never>? = timeout.map { duration in
            Task { [weak self] in
                try? await Task.sleep(for: duration)
                await self?.timeoutReply(serial: serial)
            }
        }

        defer { timeoutTask?.cancel() }

        let reply: DBusMessage = try await withCheckedThrowingContinuation { continuation in

            if let early = earlyReplies.removeValue(forKey: serial) {
                outstanding.remove(serial)
                continuation.resume(with: early)
            } else {
                pendingReplies[serial] = continuation
            }
        }

        // An error reply is surfaced as a thrown `DBusError`.
        if let error = DBusError(message: reply) {
            throw error
        }

        return reply
    }

    func timeoutReply(serial: UInt32) {

        guard let continuation = pendingReplies.removeValue(forKey: serial)
            else { return }

        outstanding.remove(serial)
        continuation.resume(throwing: DBusError(name: .noReply,
                                                message: "Did not receive a reply within the timeout"))
    }

    func writeAll(_ bytes: [UInt8]) async throws {

        var offset = 0

        while offset < bytes.count {

            let written = try await socket.write(Data(bytes[offset...]))

            guard written > 0
                else { throw DBusProtocolError.endOfStream }

            offset += written
        }
    }

    // MARK: Reading

    func startReading() {

        readTask = Task { [weak self] in

            while let self = self, await self.isConnected, Task.isCancelled == false {

                do {
                    let data = try await self.readChunk()

                    guard data.isEmpty == false else {
                        await self.disconnected(DBusProtocolError.endOfStream)
                        return
                    }

                    await self.received(Array(data))
                }
                catch {
                    await self.disconnected(error)
                    return
                }
            }
        }
    }

    nonisolated func readChunk() async throws -> Data {

        return try await socket.read(DBusConnection.readChunkSize)
    }

    /// Append received bytes and dispatch every complete message they contain.
    func received(_ bytes: [UInt8]) {

        readBuffer.append(contentsOf: bytes)

        while true {

            let length: Int?

            do { length = try DBusMessage.length(from: readBuffer) }
            catch {
                // The stream is unframeable from here on; there is no way to resynchronise.
                disconnected(error)
                return
            }

            guard let messageLength = length, readBuffer.count >= messageLength
                else { return }

            let messageBytes = Array(readBuffer[0 ..< messageLength])
            readBuffer.removeFirst(messageLength)

            do {
                let (message, _) = try DBusMessage.decode(messageBytes)
                dispatch(message)
            }
            catch {
                // A single malformed message is not fatal to the framing, because its length
                // was read from the header; skip it and carry on.
                continue
            }
        }
    }

    func dispatch(_ message: DBusMessage) {

        // Replies are matched by the serial of the call they answer.
        if message.type == .methodReturn || message.type == .error,
            let replySerial = message.replySerial,
            outstanding.contains(replySerial) {

            if let continuation = pendingReplies.removeValue(forKey: replySerial) {
                outstanding.remove(replySerial)
                continuation.resume(returning: message)
            } else {
                // The caller has not started waiting yet.
                earlyReplies[replySerial] = .success(message)
            }

            return
        }

        switch message.type {

        case .signal:
            // The bus delivers the union of every rule installed, so each subscription decides
            // for itself whether this message is one it asked for.
            var delivered = false

            for subscription in subscriptions.values where subscription.rule.matches(message) {
                subscription.continuation.yield(message)
                delivered = true
            }

            if delivered == false {
                messageHandler?(message)
            }

        case .methodCall:
            handleMethodCall(message)

        default:
            // A reply whose call is no longer outstanding, e.g. one that already timed out.
            messageHandler?(message)
        }
    }

    func disconnected(_ error: Error) {

        guard isConnected else { return }

        isConnected = false
        failAll(with: error)
    }

    func failAll(with error: Error) {

        let pending = pendingReplies
        pendingReplies.removeAll()

        for serial in outstanding where pending[serial] == nil {
            earlyReplies[serial] = .failure(error)
        }

        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }

        outstanding.removeAll()

        // Signal subscribers see the stream end rather than hang forever.
        let closing = subscriptions
        subscriptions.removeAll()
        matchRuleCounts.removeAll()

        for subscription in closing.values {
            subscription.continuation.finish()
        }
    }
}
