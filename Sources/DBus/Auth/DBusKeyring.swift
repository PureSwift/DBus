//
//  DBusKeyring.swift
//  DBus
//

import SystemPackage

/// The shared secrets used by `DBUS_COOKIE_SHA1`.
///
/// Cookies live in `~/.dbus-keyrings/<context>`, one per line, as
/// `<id> <creation time> <cookie>` where the cookie is hexadecimal.
///
/// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#auth-mechanisms-sha
internal struct DBusKeyring {

    /// A single cookie.
    struct Cookie: Equatable {

        /// Identifier, unique within the context.
        let identifier: String

        /// Creation time, as seconds since the Unix epoch.
        let creationTime: UInt64

        /// The secret, as a hexadecimal string.
        let value: String
    }

    /// The cookies in the context, in file order.
    let cookies: [Cookie]

    init(cookies: [Cookie]) {

        self.cookies = cookies
    }

    /// The cookie with the given identifier.
    func cookie(for identifier: String) -> Cookie? {

        return cookies.first { $0.identifier == identifier }
    }
}

internal extension DBusKeyring {

    /// The directory keyrings live in, relative to the home directory.
    static let directoryName = ".dbus-keyrings"

    /// Load the keyring for a context.
    ///
    /// - Parameter context: The cookie context named by the server. Validated, because it
    /// arrives from the peer and is used to build a path.
    static func load(context: String,
                     homeDirectory: String? = ProcessEnvironment.homeDirectory) throws -> DBusKeyring {

        guard isValidContext(context)
            else { throw DBusProtocolError.authenticationFailed("Invalid cookie context '\(context)'") }

        guard let home = homeDirectory
            else { throw DBusProtocolError.authenticationFailed("No home directory for the keyring") }

        let path = "\(home)/\(directoryName)/\(context)"

        guard let contents = readFile(path)
            else { throw DBusProtocolError.authenticationFailed("Could not read the keyring at \(path)") }

        return DBusKeyring(cookies: parse(contents))
    }

    /// Whether a cookie context is safe to use as a path component.
    ///
    /// The specification restricts contexts to `[A-Za-z0-9_-]`, which also keeps a hostile
    /// server from escaping the keyring directory with `../`.
    static func isValidContext(_ context: String) -> Bool {

        guard context.isEmpty == false, context.utf8.count <= 255
            else { return false }

        return context.utf8.allSatisfy { $0.isBusNameElementByte }
    }

    static func parse(_ contents: String) -> [Cookie] {

        var cookies = [Cookie]()

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {

            let fields = line.split(separator: " ", omittingEmptySubsequences: true)

            guard fields.count >= 3,
                let creationTime = UInt64(fields[1])
                else { continue } // skip malformed lines rather than failing the whole keyring

            cookies.append(Cookie(identifier: String(fields[0]),
                                  creationTime: creationTime,
                                  value: String(fields[2])))
        }

        return cookies
    }

    private static func readFile(_ path: String) -> String? {

        guard let descriptor = try? FileDescriptor.open(FilePath(path), .readOnly)
            else { return nil }

        defer { try? descriptor.close() }

        var contents = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {

            guard let count = try? buffer.withUnsafeMutableBytes({ try descriptor.read(into: $0) })
                else { return nil }

            guard count > 0 else { break }

            contents.append(contentsOf: buffer[0 ..< count])

            // A keyring is small; refuse to read an unbounded file.
            guard contents.count <= 64 * 1024
                else { return nil }
        }

        return String(validating: contents, as: UTF8.self)
    }
}

// MARK: - Challenge

internal enum DBusCookieChallenge {

    /// Parse the server's challenge, which is `<context> <cookie id> <server challenge>`.
    static func parse(_ decoded: String) throws -> (context: String, identifier: String, challenge: String) {

        let fields = decoded.split(separator: " ", omittingEmptySubsequences: true)

        guard fields.count == 3
            else { throw DBusProtocolError.authenticationFailed("Malformed cookie challenge '\(decoded)'") }

        return (String(fields[0]), String(fields[1]), String(fields[2]))
    }

    /// A fresh client challenge, as a hexadecimal string.
    static func clientChallenge(byteCount: Int = 16) -> String {

        var generator = SystemRandomNumberGenerator()

        var bytes = [UInt8]()
        bytes.reserveCapacity(byteCount)

        for _ in 0 ..< byteCount {
            bytes.append(UInt8.random(in: .min ... .max, using: &generator))
        }

        return bytes.hexEncoded
    }

    /// The response digest: `SHA1(serverChallenge:clientChallenge:cookie)`, as lowercase hex.
    ///
    /// - Note: The three components are their *textual* hexadecimal forms, joined with colons,
    /// not the bytes they decode to.
    static func digest(serverChallenge: String,
                       clientChallenge: String,
                       cookie: String) -> String {

        return SHA1.hexDigest("\(serverChallenge):\(clientChallenge):\(cookie)")
    }
}
