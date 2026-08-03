//
//  SHA1.swift
//  DBus
//

/// SHA-1, as required by the `DBUS_COOKIE_SHA1` authentication mechanism.
///
/// - Warning: SHA-1 is not collision resistant and must not be used for anything else. It is
/// here only because the D-Bus specification mandates it for this one mechanism.
///
/// Reference: RFC 3174.
internal struct SHA1 {

    private var state: (UInt32, UInt32, UInt32, UInt32, UInt32) = (
        0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
    )

    /// Bytes not yet consumed by a full 64 byte block.
    private var buffer = [UInt8]()

    /// Total message length in bytes, which is appended as a bit count at the end.
    private var length = 0

    init() {

        buffer.reserveCapacity(64)
    }

    /// The digest of a byte sequence.
    static func hash<S: Sequence>(_ bytes: S) -> [UInt8] where S.Element == UInt8 {

        var sha1 = SHA1()
        sha1.update(bytes)
        return sha1.finalize()
    }

    /// The digest of a string's UTF-8 bytes, as lowercase hexadecimal.
    static func hexDigest(_ string: String) -> String {

        return hash(Array(string.utf8)).hexEncoded
    }

    mutating func update<S: Sequence>(_ bytes: S) where S.Element == UInt8 {

        for byte in bytes {

            buffer.append(byte)
            length += 1

            if buffer.count == 64 {
                process(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
    }

    mutating func finalize() -> [UInt8] {

        // Append 0x80, then zeros, until 8 bytes short of a block boundary, then the bit count.
        let bitLength = UInt64(length) * 8

        update([0x80])

        while buffer.count != 56 {
            update([0x00])
        }

        // `update` counts these toward `length`, which no longer matters: the bit count was
        // captured before padding began.
        var lengthBytes = [UInt8]()
        for shift in stride(from: 56, through: 0, by: -8) {
            lengthBytes.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }
        update(lengthBytes)

        var digest = [UInt8]()
        digest.reserveCapacity(20)

        for word in [state.0, state.1, state.2, state.3, state.4] {
            digest.append(UInt8(truncatingIfNeeded: word >> 24))
            digest.append(UInt8(truncatingIfNeeded: word >> 16))
            digest.append(UInt8(truncatingIfNeeded: word >> 8))
            digest.append(UInt8(truncatingIfNeeded: word))
        }

        return digest
    }

    private mutating func process(_ block: [UInt8]) {

        assert(block.count == 64)

        var w = [UInt32](repeating: 0, count: 80)

        for index in 0 ..< 16 {
            let offset = index * 4
            w[index] = UInt32(block[offset]) << 24
                | UInt32(block[offset + 1]) << 16
                | UInt32(block[offset + 2]) << 8
                | UInt32(block[offset + 3])
        }

        for index in 16 ..< 80 {
            w[index] = rotateLeft(w[index - 3] ^ w[index - 8] ^ w[index - 14] ^ w[index - 16], 1)
        }

        var (a, b, c, d, e) = state

        for index in 0 ..< 80 {

            let f: UInt32
            let k: UInt32

            switch index {
            case 0 ..< 20:
                f = (b & c) | (~b & d)
                k = 0x5A827999
            case 20 ..< 40:
                f = b ^ c ^ d
                k = 0x6ED9EBA1
            case 40 ..< 60:
                f = (b & c) | (b & d) | (c & d)
                k = 0x8F1BBCDC
            default:
                f = b ^ c ^ d
                k = 0xCA62C1D6
            }

            let temp = rotateLeft(a, 5) &+ f &+ e &+ k &+ w[index]
            e = d
            d = c
            c = rotateLeft(b, 30)
            b = a
            a = temp
        }

        state = (state.0 &+ a, state.1 &+ b, state.2 &+ c, state.3 &+ d, state.4 &+ e)
    }

    private func rotateLeft(_ value: UInt32, _ amount: UInt32) -> UInt32 {

        return (value << amount) | (value >> (32 - amount))
    }
}

// MARK: - Hex

internal extension Collection where Element == UInt8 {

    /// The bytes as lowercase hexadecimal.
    var hexEncoded: String {

        let digits = Array("0123456789abcdef".utf8)

        var output = [UInt8]()
        output.reserveCapacity(count * 2)

        for byte in self {
            output.append(digits[Int(byte >> 4)])
            output.append(digits[Int(byte & 0x0F)])
        }

        return String(decoding: output, as: UTF8.self)
    }
}

internal extension String {

    /// Decode a hexadecimal string into bytes, or `nil` if it is malformed.
    var hexDecoded: [UInt8]? {

        let characters = Array(utf8)

        guard characters.count % 2 == 0
            else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity(characters.count / 2)

        var index = 0
        while index < characters.count {

            guard let high = characters[index].hexDigitValue,
                let low = characters[index + 1].hexDigitValue
                else { return nil }

            bytes.append(high << 4 | low)
            index += 2
        }

        return bytes
    }

    /// Decode a hexadecimal string into a UTF-8 string.
    var hexDecodedString: String? {

        guard let bytes = hexDecoded
            else { return nil }

        return String(validating: bytes, as: UTF8.self)
    }
}

internal extension UInt8 {

    /// The numeric value of an ASCII hexadecimal digit.
    var hexDigitValue: UInt8? {

        switch self {
        case 0x30 ... 0x39: return self - 0x30 // 0-9
        case 0x41 ... 0x46: return self - 0x41 + 10 // A-F
        case 0x61 ... 0x66: return self - 0x61 + 10 // a-f
        default: return nil
        }
    }
}
