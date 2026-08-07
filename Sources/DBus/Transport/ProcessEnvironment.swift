//
//  ProcessEnvironment.swift
//  DBus
//

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Bionic)
import Bionic
#endif

/// Access to environment variables and process credentials, without Foundation.
internal enum ProcessEnvironment {

    /// The value of the named environment variable, or `nil` if unset.
    static func value(for name: String) -> String? {

        guard let pointer = name.withCString({ getenv($0) })
            else { return nil }

        let value = String(cString: pointer)

        // An empty variable is treated as unset, which is what the reference implementation does
        // for the bus address variables.
        return value.isEmpty ? nil : value
    }

    /// The real user ID of the calling process.
    ///
    /// Used as the credential for SASL `EXTERNAL` authentication.
    static var userID: UInt32 {

        return UInt32(getuid())
    }

    /// The login name of the calling user.
    ///
    /// Used as the credential for SASL `DBUS_COOKIE_SHA1`, which identifies the user whose
    /// keyring holds the shared secret.
    static var userName: String {

        if let name = passwordEntry(\.pw_name) {
            return name
        }

        // Fall back to the environment, then to the numeric uid, which some servers accept.
        return value(for: "LOGNAME") ?? value(for: "USER") ?? String(userID)
    }

    /// The calling user's home directory, where the keyring lives.
    static var homeDirectory: String? {

        // `HOME` wins, matching the reference implementation, so a test can redirect it.
        if let home = value(for: "HOME") {
            return home
        }

        return passwordEntry(\.pw_dir)
    }

    /// Read a field from the calling user's password database entry.
    private static func passwordEntry(_ field: KeyPath<passwd, UnsafeMutablePointer<CChar>?>) -> String? {

        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?

        // Sized generously; `getpwuid_r` fails with ERANGE if the buffer is too small.
        var buffer = [CChar](repeating: 0, count: 4096)

        let status = buffer.withUnsafeMutableBufferPointer { pointer in
            getpwuid_r(getuid(), &entry, pointer.baseAddress!, pointer.count, &result)
        }

        guard status == 0, result != nil,
            let value = entry[keyPath: field]
            else { return nil }

        let string = String(cString: value)

        return string.isEmpty ? nil : string
    }
}
