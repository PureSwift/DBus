//
//  Unmarshaller.swift
//  DBus
//

/// Decodes D-Bus values from the wire format.
///
/// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling
internal struct DBusUnmarshaller {

    /// The byte order the values were written in.
    let endianness: DBusEndianness

    /// The bytes being decoded.
    let bytes: [UInt8]

    /// The current read position within `bytes`.
    private(set) var offset: Int

    /// The position alignment is measured from. See `DBusMarshaller.origin`.
    private let origin: Int

    /// Descriptors received out of band with this message, which `UNIX_FD` values index into.
    let fileDescriptors: [Int32]

    init(bytes: [UInt8],
         endianness: DBusEndianness,
         offset: Int = 0,
         origin: Int = 0,
         fileDescriptors: [Int32] = []) {

        self.bytes = bytes
        self.endianness = endianness
        self.offset = offset
        self.origin = origin
        self.fileDescriptors = fileDescriptors
    }
}

// MARK: - Primitives

internal extension DBusUnmarshaller {

    /// Whether every byte has been consumed.
    var isAtEnd: Bool {

        return offset >= bytes.count
    }

    /// The number of bytes remaining.
    var remaining: Int {

        return bytes.count - offset
    }

    /// Skip padding until the position is a multiple of `alignment`.
    ///
    /// - Note: The specification requires padding bytes to be zero, and requires receivers to
    /// reject messages where they are not.
    mutating func align(to alignment: Int) throws {

        precondition(alignment > 0)

        let position = origin + offset
        let remainder = position % alignment

        guard remainder != 0 else { return }

        let padding = alignment - remainder

        guard remaining >= padding
            else { throw DBusProtocolError.endOfStream }

        for index in offset ..< (offset + padding) {

            guard bytes[index] == 0
                else { throw DBusProtocolError.invalidPadding }
        }

        offset += padding
    }

    mutating func readByte() throws -> UInt8 {

        guard remaining >= 1
            else { throw DBusProtocolError.endOfStream }

        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {

        guard count >= 0, remaining >= count
            else { throw DBusProtocolError.endOfStream }

        defer { offset += count }
        return Swift.Array(bytes[offset ..< offset + count])
    }

    mutating func readInteger<T: FixedWidthInteger>(_ type: T.Type = T.self) throws -> T {

        try align(to: MemoryLayout<T>.size)
        return try readIntegerUnaligned(type)
    }

    mutating func readIntegerUnaligned<T: FixedWidthInteger>(_ type: T.Type = T.self) throws -> T {

        let size = MemoryLayout<T>.size

        guard remaining >= size
            else { throw DBusProtocolError.endOfStream }

        var value = T.zero
        withUnsafeMutableBytes(of: &value) { destination in
            for index in 0 ..< size {
                destination[index] = bytes[offset + index]
            }
        }
        offset += size

        return T(value, from: endianness)
    }

    /// Read a `STRING` or `OBJECT_PATH`: a `UInt32` byte count, the UTF-8 bytes, then a NUL.
    mutating func readString() throws -> String {

        let length = try readInteger(UInt32.self)
        return try readString(length: Int(length))
    }

    /// Read a `SIGNATURE`: a single byte count, the ASCII bytes, then a NUL.
    mutating func readSignatureString() throws -> String {

        let length = try readByte()
        return try readString(length: Int(length))
    }

    private mutating func readString(length: Int) throws -> String {

        let utf8 = try readBytes(length)

        // The terminating NUL is not counted in the length but is always present.
        guard try readByte() == 0
            else { throw DBusProtocolError.invalidString }

        // Strings on the bus must be valid UTF-8; reject rather than substitute replacement
        // characters, which would silently corrupt object paths and interface names.
        guard let string = String(validating: utf8, as: UTF8.self)
            else { throw DBusProtocolError.invalidString }

        return string
    }
}

// MARK: - Values

internal extension DBusUnmarshaller {

    /// Read the complete values described by a signature.
    mutating func read(signature: DBusSignature) throws -> [DBusMessageArgument] {

        var arguments = [DBusMessageArgument]()
        arguments.reserveCapacity(signature.count)

        for type in signature {
            arguments.append(try read(type))
        }

        return arguments
    }

    /// Read a single complete value of the given type.
    mutating func read(_ type: DBusSignature.ValueType) throws -> DBusMessageArgument {

        switch type {

        case .byte:
            return .byte(try readByte())

        case .boolean:
            let value = try readInteger(UInt32.self)
            // Only 0 and 1 are legal; anything else is invalid per the specification.
            switch value {
            case 0: return .boolean(false)
            case 1: return .boolean(true)
            default: throw DBusProtocolError.invalidValue("Boolean value \(value) is not 0 or 1")
            }

        case .int16:
            return .int16(try readInteger(Int16.self))
        case .uint16:
            return .uint16(try readInteger(UInt16.self))
        case .int32:
            return .int32(try readInteger(Int32.self))
        case .uint32:
            return .uint32(try readInteger(UInt32.self))
        case .int64:
            return .int64(try readInteger(Int64.self))
        case .uint64:
            return .uint64(try readInteger(UInt64.self))

        case .double:
            return .double(Double(bitPattern: try readInteger(UInt64.self)))

        case .fileDescriptor:
            // The wire carries an index into the descriptors delivered out of band.
            let index = Int(try readInteger(UInt32.self))

            guard index < fileDescriptors.count
                else { throw DBusProtocolError.invalidValue("File descriptor index \(index) is out of range; \(fileDescriptors.count) were received") }

            return .fileDescriptor(DBusMessageArgument.FileDescriptor(rawValue: fileDescriptors[index]))

        case .string:
            return .string(try readString())

        case .objectPath:
            let string = try readString()
            guard let objectPath = DBusObjectPath(rawValue: string)
                else { throw DBusProtocolError.invalidValue("Invalid object path '\(string)'") }
            return .objectPath(objectPath)

        case .signature:
            let string = try readSignatureString()
            guard let signature = DBusSignature(rawValue: string)
                else { throw DBusProtocolError.invalidSignature(string) }
            return .signature(signature)

        case let .array(elementType):

            var elements = [DBusMessageArgument]()
            try readArray(elementAlignment: elementType.alignment) { unmarshaller in
                elements.append(try unmarshaller.read(elementType))
            }

            guard let array = DBusMessageArgument.Array(type: elementType, elements)
                else { throw DBusProtocolError.invalidValue("Array elements do not match the declared type") }

            return .array(array)

        case let .dictionary(dictionaryType):

            var entries = [DBusMessageArgument.Dictionary.Entry]()
            try readArray(elementAlignment: dictionaryEntryAlignment) { unmarshaller in
                try unmarshaller.align(to: dictionaryEntryAlignment)
                let key = try unmarshaller.read(dictionaryType.key)
                let value = try unmarshaller.read(dictionaryType.value)
                entries.append(DBusMessageArgument.Dictionary.Entry(key: key, value: value))
            }

            guard let dictionary = DBusMessageArgument.Dictionary(keyType: dictionaryType.key,
                                                                  valueType: dictionaryType.value,
                                                                  entries)
                else { throw DBusProtocolError.invalidValue("Dictionary entries do not match the declared type") }

            return .dictionary(dictionary)

        case let .struct(structureType):

            try align(to: 8)

            var elements = [DBusMessageArgument]()
            elements.reserveCapacity(structureType.count)

            for elementType in structureType {
                elements.append(try read(elementType))
            }

            guard let structure = DBusMessageArgument.Structure(elements)
                else { throw DBusProtocolError.invalidValue("Empty struct") }

            return .struct(structure)

        case .variant:

            let signatureString = try readSignatureString()

            guard let signature = DBusSignature(rawValue: signatureString)
                else { throw DBusProtocolError.invalidSignature(signatureString) }

            guard signature.count == 1
                else { throw DBusProtocolError.invalidValue("Variant must contain exactly one complete type, found \(signature.count)") }

            let element = try read(signature[0])

            return .variant(DBusMessageArgument.Variant(element))
        }
    }

    /// Read an `ARRAY` body, invoking `element` once per element.
    ///
    /// - Note: The length prefix counts only the element data. Padding between the length and
    /// the first element is present even for an empty array and is not part of the length.
    private mutating func readArray(elementAlignment: Int,
                                    _ element: (inout DBusUnmarshaller) throws -> ()) throws {

        let length = Int(try readInteger(UInt32.self))

        guard length <= maximumArrayLength
            else { throw DBusProtocolError.invalidValue("Array length \(length) exceeds the maximum") }

        try align(to: elementAlignment)

        let start = offset

        guard remaining >= length
            else { throw DBusProtocolError.endOfStream }

        while offset - start < length {

            let positionBefore = offset
            try element(&self)

            // Defensive: a zero-width element would loop forever.
            guard offset > positionBefore
                else { throw DBusProtocolError.invalidValue("Array element consumed no bytes") }
        }

        guard offset - start == length
            else { throw DBusProtocolError.invalidValue("Array elements overran the declared length") }
    }
}
