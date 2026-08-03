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
}
