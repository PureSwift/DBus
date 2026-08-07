//
//  Marshaller.swift
//  DBus
//

/// Encodes D-Bus values into the wire format.
///
/// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-marshaling
internal struct DBusMarshaller {

    /// The byte order values are written in.
    let endianness: DBusEndianness

    /// The encoded bytes.
    private(set) var bytes: [UInt8]

    /// Descriptors encountered while marshalling, in the order their indices were assigned.
    ///
    /// A `UNIX_FD` is marshalled as an index into the array of descriptors sent out of band
    /// with the message, not as the descriptor number itself.
    private(set) var fileDescriptors: [Int32] = []

    /// The position the alignment is measured from.
    ///
    /// Alignment in D-Bus is relative to the start of the *message*, not the start of the
    /// buffer being written. When marshalling a message body separately from its header, the
    /// body's alignment origin is the (already 8-aligned) end of the header, so an origin of
    /// zero is correct there too.
    private let origin: Int

    init(endianness: DBusEndianness = .host, bytes: [UInt8] = [], origin: Int = 0) {

        self.endianness = endianness
        self.bytes = bytes
        self.origin = origin
    }
}

// MARK: - Primitives

internal extension DBusMarshaller {

    /// The current offset, relative to the alignment origin.
    var offset: Int {

        return origin + bytes.count
    }

    /// Insert zero bytes until the offset is a multiple of `alignment`.
    mutating func pad(to alignment: Int) {

        precondition(alignment > 0)

        let remainder = offset % alignment

        guard remainder != 0 else { return }

        bytes.append(contentsOf: repeatElement(0, count: alignment - remainder))
    }

    mutating func append(_ value: UInt8) {

        bytes.append(value)
    }

    mutating func append<T: FixedWidthInteger>(_ value: T) {

        pad(to: MemoryLayout<T>.size)
        appendUnaligned(value)
    }

    /// Append an integer without first padding, for use where alignment is already guaranteed.
    mutating func appendUnaligned<T: FixedWidthInteger>(_ value: T) {

        withUnsafeBytes(of: value.byteSwapped(to: endianness)) {
            bytes.append(contentsOf: $0)
        }
    }

    mutating func append(_ value: Double) {

        append(value.bitPattern)
    }

    mutating func append(_ value: Bool) {

        append(UInt32(value ? 1 : 0))
    }

    /// Append a `STRING` or `OBJECT_PATH`: a `UInt32` byte count, the UTF-8 bytes, then a NUL.
    ///
    /// - Note: The length excludes the terminating NUL.
    mutating func appendString(_ value: String) {

        let utf8 = Swift.Array(value.utf8)
        append(UInt32(utf8.count))
        bytes.append(contentsOf: utf8)
        bytes.append(0)
    }

    /// Append a `SIGNATURE`: a single byte count, the ASCII bytes, then a NUL.
    ///
    /// - Note: A signature is at most 255 bytes, which is why a single byte suffices.
    mutating func appendSignature(_ value: String) {

        let utf8 = Swift.Array(value.utf8)
        assert(utf8.count <= 255, "Signature exceeds 255 bytes")
        bytes.append(UInt8(truncatingIfNeeded: utf8.count))
        bytes.append(contentsOf: utf8)
        bytes.append(0)
    }
}

// MARK: - Values

internal extension DBusMarshaller {

    /// Append a sequence of complete values, as in a message body.
    mutating func append<S: Sequence>(contentsOf arguments: S) throws where S.Element == DBusMessageArgument {

        for argument in arguments {
            try append(argument)
        }
    }

    mutating func append(_ argument: DBusMessageArgument) throws {

        switch argument {

        case let .byte(value):
            append(value)
        case let .boolean(value):
            append(value)
        case let .int16(value):
            append(value)
        case let .uint16(value):
            append(value)
        case let .int32(value):
            append(value)
        case let .uint32(value):
            append(value)
        case let .int64(value):
            append(value)
        case let .uint64(value):
            append(value)
        case let .double(value):
            append(value)
        case let .fileDescriptor(value):
            // Marshalled as an index into the out-of-band file descriptor array, so the
            // descriptor itself is recorded here and only its position goes on the wire.
            let index = fileDescriptors.count
            fileDescriptors.append(value.rawValue)
            append(UInt32(index))

        case let .string(value):
            appendString(value)
        case let .objectPath(value):
            appendString(value.rawValue)
        case let .signature(value):
            appendSignature(value.rawValue)

        case let .array(array):
            try appendArray(elementAlignment: array.type.alignment) { marshaller in
                for element in array {
                    try marshaller.append(element)
                }
            }

        case let .dictionary(dictionary):
            // A dictionary is an array of DICT_ENTRY, which align to 8 like a struct.
            try appendArray(elementAlignment: dictionaryEntryAlignment) { marshaller in
                for entry in dictionary {
                    marshaller.pad(to: dictionaryEntryAlignment)
                    try marshaller.append(entry.key)
                    try marshaller.append(entry.value)
                }
            }

        case let .struct(structure):
            pad(to: 8)
            for element in structure {
                try append(element)
            }

        case let .variant(variant):
            let element = variant.element
            appendSignature(String(element.type))
            try append(element)
        }
    }

    /// Append an `ARRAY`: a `UInt32` byte count, then the elements.
    ///
    /// - Note: The length counts only the element data. Padding inserted between the length
    /// and the first element to satisfy the element alignment is *not* included, and must be
    /// written even when the array is empty.
    private mutating func appendArray(elementAlignment: Int,
                                      _ body: (inout DBusMarshaller) throws -> ()) throws {

        // The length itself is a UInt32 and so aligns to 4.
        pad(to: 4)

        // Reserve space for the length, to be backfilled once the elements are written.
        let lengthIndex = bytes.count
        appendUnaligned(UInt32(0))

        // Padding to the element alignment is written even for an empty array, and is not
        // counted in the length.
        pad(to: elementAlignment)

        let start = bytes.count
        try body(&self)
        let length = bytes.count - start

        guard length <= maximumArrayLength
            else { throw DBusProtocolError.invalidValue("Array length \(length) exceeds the maximum") }

        // Backfill the length.
        withUnsafeBytes(of: UInt32(length).byteSwapped(to: endianness)) { lengthBytes in
            for (index, byte) in lengthBytes.enumerated() {
                bytes[lengthIndex + index] = byte
            }
        }
    }
}

// MARK: - Convenience

internal extension DBusMarshaller {

    /// Marshal a complete list of values and return the resulting bytes.
    static func marshal(_ arguments: [DBusMessageArgument],
                        endianness: DBusEndianness = .host,
                        origin: Int = 0) throws -> [UInt8] {

        return try marshalWithDescriptors(arguments, endianness: endianness, origin: origin).bytes
    }

    /// Marshal a complete list of values, returning the bytes and any descriptors they refer to.
    static func marshalWithDescriptors(_ arguments: [DBusMessageArgument],
                                       endianness: DBusEndianness = .host,
                                       origin: Int = 0) throws -> (bytes: [UInt8], fileDescriptors: [Int32]) {

        var marshaller = DBusMarshaller(endianness: endianness, origin: origin)
        try marshaller.append(contentsOf: arguments)
        return (marshaller.bytes, marshaller.fileDescriptors)
    }
}

// MARK: - Signature

internal extension Sequence where Element == DBusMessageArgument {

    /// The concatenated signature of the values.
    var signature: DBusSignature {

        return DBusSignature(map { $0.type })
    }
}
