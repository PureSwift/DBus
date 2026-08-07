//
//  SASL.swift
//  DBus
//

/// A SASL authentication mechanism.
///
/// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#auth-mechanisms
public enum DBusAuthenticationMechanism: String, Sendable, CaseIterable {

    /// Authenticate using out-of-band credentials, i.e. the peer's uid as reported by the
    /// kernel. This is what local Unix socket connections use.
    case external = "EXTERNAL"

    /// No authentication. Accepted only by servers configured to allow it.
    case anonymous = "ANONYMOUS"

    /// Prove knowledge of a shared secret from the user's keyring, without transmitting it.
    ///
    /// Used where the peer's credentials cannot be obtained out of band, such as over TCP.
    case cookieSHA1 = "DBUS_COOKIE_SHA1"
}

// MARK: - Commands

/// A line of the SASL handshake.
///
/// The handshake is a line protocol: ASCII commands terminated by `\r\n`, exchanged before any
/// D-Bus messages are sent.
internal enum DBusSASLResponse: Equatable {

    /// Authentication succeeded; the argument is the server's GUID.
    case ok(String)

    /// Authentication failed; the argument lists the mechanisms the server supports.
    case rejected([String])

    /// The server sent challenge data.
    case data(String)

    /// The server encountered an error.
    case error(String)

    /// The server agreed to Unix file descriptor passing.
    case agreeUnixFD

    init(line: String) throws {

        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)

        guard let command = parts.first
            else { throw DBusProtocolError.authenticationFailed("Empty response") }

        let argument = parts.count > 1 ? String(parts[1]) : ""

        switch command {
        case "OK":
            self = .ok(argument)
        case "REJECTED":
            self = .rejected(argument.split(separator: " ").map(String.init))
        case "DATA":
            self = .data(argument)
        case "ERROR":
            self = .error(argument)
        case "AGREE_UNIX_FD":
            self = .agreeUnixFD
        default:
            throw DBusProtocolError.authenticationFailed("Unknown response '\(command)'")
        }
    }
}

// MARK: - Client

/// The client side of the SASL handshake, as a state machine.
///
/// Kept free of I/O so it can be driven by tests without a socket.
internal struct DBusSASLClient {

    enum State: Equatable {

        /// Waiting for the reply to an `AUTH` command.
        case authenticating(DBusAuthenticationMechanism)

        /// Waiting for the reply to `NEGOTIATE_UNIX_FD`.
        case negotiatingUnixFileDescriptors

        /// `BEGIN` has been sent; the connection carries messages from here on.
        case ready

        /// The handshake failed.
        case failed
    }

    /// Mechanisms to try, in preference order.
    private var remaining: [DBusAuthenticationMechanism]

    /// The user ID offered for `EXTERNAL`.
    let userID: UInt32

    /// Whether to ask the server for file descriptor passing.
    let negotiateUnixFileDescriptors: Bool

    private(set) var state: State

    /// The server's GUID, once authenticated.
    private(set) var serverGUID: String?

    /// Whether the server agreed to file descriptor passing.
    private(set) var unixFileDescriptorsSupported = false

    /// The login name offered for `DBUS_COOKIE_SHA1`.
    let userName: String

    /// Where to load keyrings from. Injected so tests need not touch the real home directory.
    let keyringLoader: @Sendable (String) throws -> DBusKeyring

    /// The client challenge generated for the current cookie exchange, kept for tests.
    private(set) var clientChallenge: String?

    init(mechanisms: [DBusAuthenticationMechanism] = [.external, .cookieSHA1, .anonymous],
         userID: UInt32,
         userName: String = ProcessEnvironment.userName,
         negotiateUnixFileDescriptors: Bool = true,
         keyringLoader: @escaping @Sendable (String) throws -> DBusKeyring = { try DBusKeyring.load(context: $0) }) {

        precondition(mechanisms.isEmpty == false, "At least one mechanism is required")

        self.remaining = mechanisms
        self.userID = userID
        self.userName = userName
        self.negotiateUnixFileDescriptors = negotiateUnixFileDescriptors
        self.keyringLoader = keyringLoader
        self.state = .authenticating(mechanisms[0])
    }
}

internal extension DBusSASLClient {

    /// The bytes to send before anything else.
    ///
    /// - Note: The leading NUL byte is required by the specification. It is not part of the
    /// SASL protocol; historically it carried credentials via `SCM_CREDS`, and on Linux the
    /// kernel supplies them through `SO_PEERCRED` instead, but the byte must still be sent.
    mutating func start() -> [UInt8] {

        guard case let .authenticating(mechanism) = state
            else { preconditionFailure("Already started") }

        return [0x00] + command(auth: mechanism)
    }

    /// Advance the state machine with a response from the server.
    ///
    /// - Returns: The bytes to send in reply, or `nil` if there is nothing to send.
    mutating func handle(_ response: DBusSASLResponse) throws -> [UInt8]? {

        switch (state, response) {

        // MARK: Authenticating

        case let (.authenticating, .ok(guid)):

            serverGUID = guid

            if negotiateUnixFileDescriptors {
                state = .negotiatingUnixFileDescriptors
                return line("NEGOTIATE_UNIX_FD")
            } else {
                state = .ready
                return line("BEGIN")
            }

        case let (.authenticating(mechanism), .rejected(offered)):

            // Drop the mechanism that just failed, then keep only those the server offers.
            remaining.removeAll { $0 == mechanism }
            let supported = remaining.filter { offered.contains($0.rawValue) }

            guard let next = supported.first else {
                state = .failed
                throw DBusProtocolError.authenticationRejected(
                    "No supported mechanism; server offered \(offered.joined(separator: ", "))")
            }

            state = .authenticating(next)
            return command(auth: next)

        case let (.authenticating, .error(message)):

            state = .failed
            throw DBusProtocolError.authenticationFailed(message.isEmpty ? "Server error" : message)

        case let (.authenticating(mechanism), .data(hex)):

            // Only DBUS_COOKIE_SHA1 uses a challenge/response exchange.
            guard mechanism == .cookieSHA1 else {
                state = .failed
                return line("CANCEL")
            }

            do {
                return try cookieResponse(challenge: hex)
            }
            catch {
                // Cancel rather than drop the connection, so the server can offer another
                // mechanism; the REJECTED that follows drives the fallback.
                state = .authenticating(mechanism)
                return line("CANCEL")
            }

        // MARK: Negotiating file descriptors

        case (.negotiatingUnixFileDescriptors, .agreeUnixFD):

            unixFileDescriptorsSupported = true
            state = .ready
            return line("BEGIN")

        case (.negotiatingUnixFileDescriptors, .error):

            // A server that does not support fd passing answers ERROR. That is not fatal.
            unixFileDescriptorsSupported = false
            state = .ready
            return line("BEGIN")

        // MARK: Anything else

        default:
            state = .failed
            throw DBusProtocolError.authenticationFailed("Unexpected response \(response) in state \(state)")
        }
    }

    /// Whether the handshake has completed and messages may now be exchanged.
    var isReady: Bool {

        return state == .ready
    }
}

private extension DBusSASLClient {

    func command(auth mechanism: DBusAuthenticationMechanism) -> [UInt8] {

        switch mechanism {

        case .external:
            // The credential is the uid written as ASCII decimal, then hex encoded:
            // uid 1000 is "1000", which is sent as "31303030".
            return line("AUTH EXTERNAL \(String(userID).hexEncodedASCII)")

        case .anonymous:
            // The trace string is optional and purely informational.
            return line("AUTH ANONYMOUS \("DBus".hexEncodedASCII)")

        case .cookieSHA1:
            // The server uses the login name to find the keyring holding the shared secret.
            return line("AUTH DBUS_COOKIE_SHA1 \(userName.hexEncodedASCII)")
        }
    }

    /// Answer a `DBUS_COOKIE_SHA1` challenge.
    ///
    /// The server sends `<context> <cookie id> <server challenge>`, hex encoded. The reply is
    /// `<client challenge> <digest>`, also hex encoded, where the digest proves knowledge of
    /// the cookie without sending it.
    private mutating func cookieResponse(challenge hex: String) throws -> [UInt8] {

        guard let decoded = hex.hexDecodedString
            else { throw DBusProtocolError.authenticationFailed("Cookie challenge is not valid hex") }

        let (context, identifier, serverChallenge) = try DBusCookieChallenge.parse(decoded)

        let keyring = try keyringLoader(context)

        guard let cookie = keyring.cookie(for: identifier)
            else { throw DBusProtocolError.authenticationFailed("No cookie \(identifier) in context \(context)") }

        let clientChallenge = DBusCookieChallenge.clientChallenge()
        self.clientChallenge = clientChallenge

        let digest = DBusCookieChallenge.digest(serverChallenge: serverChallenge,
                                                clientChallenge: clientChallenge,
                                                cookie: cookie.value)

        return line("DATA \("\(clientChallenge) \(digest)".hexEncodedASCII)")
    }

    func line(_ string: String) -> [UInt8] {

        return Swift.Array(string.utf8) + [0x0D, 0x0A] // CR LF
    }
}

// MARK: - Hex

internal extension String {

    /// The UTF-8 bytes of the string, hex encoded as uppercase ASCII.
    ///
    /// SASL sends binary data as hexadecimal text.
    var hexEncodedASCII: String {

        let digits = Swift.Array("0123456789abcdef".utf8)

        var bytes = [UInt8]()
        bytes.reserveCapacity(utf8.count * 2)

        for byte in utf8 {
            bytes.append(digits[Int(byte >> 4)])
            bytes.append(digits[Int(byte & 0x0F)])
        }

        return String(decoding: bytes, as: UTF8.self)
    }
}

// MARK: - Line Buffer

/// Splits a stream of bytes into `\r\n` terminated SASL lines.
internal struct DBusSASLLineBuffer {

    private var bytes: [UInt8] = []

    /// The maximum length of a single line, to bound memory use against a hostile peer.
    static let maximumLineLength = 8192

    mutating func append<S: Sequence>(_ newBytes: S) where S.Element == UInt8 {

        bytes.append(contentsOf: newBytes)
    }

    /// Remove and return the next complete line, if one is available.
    mutating func next() throws -> String? {

        // Find CR LF.
        var index = 0
        while index + 1 < bytes.count {

            if bytes[index] == 0x0D, bytes[index + 1] == 0x0A {

                let lineBytes = Swift.Array(bytes[0 ..< index])
                bytes.removeFirst(index + 2)

                guard let line = String(validatingUTF8: lineBytes)
                    else { throw DBusProtocolError.authenticationFailed("Response is not valid UTF-8") }

                return line
            }

            index += 1
        }

        guard bytes.count <= Self.maximumLineLength
            else { throw DBusProtocolError.authenticationFailed("Response line is too long") }

        return nil
    }

    /// Bytes received after the last complete line, which belong to the message stream.
    var remainder: [UInt8] {

        return bytes
    }
}
