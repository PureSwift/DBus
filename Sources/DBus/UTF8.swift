//
//  UTF8.swift
//  DBus
//

internal extension String {

    /// Decode UTF-8 bytes, returning `nil` if they are not valid UTF-8.
    ///
    /// Everything arriving from the bus is untrusted, and the specification requires strings,
    /// object paths and interface names to be valid UTF-8, so invalid input must be rejected
    /// rather than accepted with replacement characters substituted for the bad bytes.
    ///
    /// - Note: `String(validating:as:)` does exactly this, but is only available from macOS 15
    /// while this package supports macOS 13. `String(decoding:as:)` never fails — it substitutes
    /// U+FFFD — so the decoded string is re-encoded and compared against the input. Only input
    /// that was already valid UTF-8 can round trip: any substitution changes the bytes, and a
    /// literal U+FFFD in the input encodes back to the same bytes it came from.
    init?<Bytes: Sequence<UInt8>>(validatingUTF8 bytes: Bytes) {

        let bytes = Array(bytes)
        let decoded = String(decoding: bytes, as: UTF8.self)

        guard Array(decoded.utf8) == bytes
            else { return nil }

        self = decoded
    }
}
