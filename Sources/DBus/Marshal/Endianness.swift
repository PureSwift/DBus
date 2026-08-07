//
//  Endianness.swift
//  DBus
//

/// The byte order of a marshalled D-Bus message.
///
/// Messages are marshalled in the sender's native byte order and converted by the receiver;
/// there is no canonical network order.
///
/// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling
public enum DBusEndianness: UInt8, Sendable, CaseIterable {

    /// Little endian, ASCII 'l'.
    case little = 0x6C

    /// Big endian, ASCII 'B'.
    case big = 0x42
}

public extension DBusEndianness {

    /// The byte order of the current machine.
    static var host: DBusEndianness {

        return _isLittleEndian ? .little : .big
    }
}

/// Determined once, from a value whose byte pattern differs between orders.
internal let _isLittleEndian: Bool = {

    return UInt16(1).littleEndian == 1
}()

internal extension FixedWidthInteger {

    /// The value converted to the given byte order.
    func byteSwapped(to endianness: DBusEndianness) -> Self {

        switch endianness {
        case .little: return self.littleEndian
        case .big: return self.bigEndian
        }
    }

    /// The value interpreted as having been stored in the given byte order.
    init(_ value: Self, from endianness: DBusEndianness) {

        switch endianness {
        case .little: self.init(littleEndian: value)
        case .big: self.init(bigEndian: value)
        }
    }
}

// MARK: - Alignment

internal extension DBusSignature.ValueType {

    /// The alignment requirement of the type, in bytes.
    ///
    /// Every value is preceded by however many zero bytes are needed to bring the current
    /// position to a multiple of this number.
    ///
    /// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling-alignment
    var alignment: Int {

        switch self {
        case .byte: return 1
        case .boolean: return 4 // marshalled as UInt32
        case .int16, .uint16: return 2
        case .int32, .uint32: return 4
        case .int64, .uint64: return 8
        case .double: return 8
        case .fileDescriptor: return 4 // an index into the fd array, marshalled as UInt32
        case .string, .objectPath: return 4 // UInt32 length prefix
        case .signature: return 1 // single byte length prefix
        case .variant: return 1 // the contained signature is a signature, so alignment 1
        case .array, .dictionary: return 4 // UInt32 length prefix; a dictionary is an array of entries
        case .struct: return 8
        }
    }
}

/// Alignment of a `DICT_ENTRY`, which is a struct on the wire and so aligns to 8.
internal let dictionaryEntryAlignment = 8

/// The maximum length of a message, header plus body, in bytes (2^27).
///
/// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-messages
public let maximumMessageLength = 134_217_728

/// The maximum length of the header field array, in bytes (2^26).
public let maximumArrayLength = 67_108_864
