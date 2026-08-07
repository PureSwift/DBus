//
//  MessageCodec.swift
//  DBus
//

// MARK: - Header Field Code

/// The code identifying a header field.
///
/// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#message-protocol-header-fields
internal enum DBusHeaderFieldCode: UInt8, CaseIterable {

    /// The object to send a call to, or the object a signal is emitted from. `OBJECT_PATH`.
    case path = 1

    /// The interface to invoke a method call on, or that a signal is emitted from. `STRING`.
    case interface = 2

    /// The member, either the method name or signal name. `STRING`.
    case member = 3

    /// The name of the error that occurred, for errors. `STRING`.
    case errorName = 4

    /// The serial number of the message this message is a reply to. `UINT32`.
    case replySerial = 5

    /// The name of the connection this message is intended for. `STRING`.
    case destination = 6

    /// Unique name of the sending connection. `STRING`.
    case sender = 7

    /// The signature of the message body. `SIGNATURE`.
    case signature = 8

    /// The number of Unix file descriptors that accompany the message. `UINT32`.
    case unixFileDescriptors = 9
}

internal extension DBusHeaderFieldCode {

    /// The type the field's variant must contain.
    var valueType: DBusSignature.ValueType {

        switch self {
        case .path: return .objectPath
        case .interface, .member, .errorName, .destination, .sender: return .string
        case .replySerial, .unixFileDescriptors: return .uint32
        case .signature: return .signature
        }
    }
}

// MARK: - Constants

internal extension DBusMessage {

    /// The only protocol version this implementation speaks.
    static let protocolVersion: UInt8 = 1

    /// Size of the fixed portion of the header, before the header field array.
    ///
    /// endianness + type + flags + version + body length + serial
    static let fixedHeaderLength = 12

    /// Offset of the header field array's length prefix.
    static let headerFieldsLengthOffset = 12

    /// The number of bytes that must be read before the total message length is known.
    static let minimumHeaderLength = 16
}

// MARK: - Encoding

public extension DBusMessage {

    /// Marshal the message into its wire representation.
    ///
    /// - Parameter endianness: The byte order to encode in. Defaults to the host's, which is
    /// what the specification recommends: senders write native order and receivers convert.
    func encode(endianness: DBusEndianness = .host) throws -> [UInt8] {

        return try encodeWithDescriptors(endianness: endianness).bytes
    }

    /// Marshal the message, returning the bytes and the descriptors that must accompany them.
    ///
    /// A `UNIX_FD` argument is written as an index into `fileDescriptors`; the descriptors
    /// themselves travel out of band, as `SCM_RIGHTS` ancillary data.
    func encodeWithDescriptors(endianness: DBusEndianness = .host) throws -> (bytes: [UInt8], fileDescriptors: [Int32]) {

        // The body is marshalled first, because its length appears in the fixed header, and
        // because marshalling is what assigns the descriptor indices.
        //
        // Alignment inside the body is relative to the start of the message, but the header is
        // always padded to 8 and 8 is the largest alignment, so an origin of zero is equivalent.
        let (body, descriptors) = try DBusMarshaller.marshalWithDescriptors(arguments, endianness: endianness)

        guard body.count <= maximumMessageLength
            else { throw DBusProtocolError.messageTooLarge(UInt32(truncatingIfNeeded: body.count)) }

        var marshaller = DBusMarshaller(endianness: endianness)

        marshaller.append(endianness.rawValue)
        marshaller.append(type.rawValue)
        marshaller.append(flags.rawValue)
        marshaller.append(DBusMessage.protocolVersion)
        marshaller.appendUnaligned(UInt32(body.count))
        marshaller.appendUnaligned(serial)

        try marshaller.append(.array(headerFieldsArgument(unixFileDescriptorCount: UInt32(descriptors.count))))

        // The header is padded to an 8 byte boundary before the body begins.
        marshaller.pad(to: 8)

        var bytes = marshaller.bytes
        bytes.append(contentsOf: body)

        guard bytes.count <= maximumMessageLength
            else { throw DBusProtocolError.messageTooLarge(UInt32(truncatingIfNeeded: bytes.count)) }

        return (bytes, descriptors)
    }

    /// The header fields, as the `a(yv)` value they are marshalled as.
    ///
    /// - Parameter unixFileDescriptorCount: How many descriptors accompany the message. Taken
    /// from what marshalling actually produced rather than from the stored property, so the
    /// field can never disagree with the body.
    internal func headerFieldsArgument(unixFileDescriptorCount: UInt32? = nil) -> DBusMessageArgument.Array {

        var fields = [DBusMessageArgument]()

        func append(_ code: DBusHeaderFieldCode, _ value: DBusMessageArgument) {

            guard let structure = DBusMessageArgument.Structure([
                .byte(code.rawValue),
                .variant(DBusMessageArgument.Variant(value))
            ]) else { fatalError("Header field structure is never empty") }

            fields.append(.struct(structure))
        }

        if let path = self.path {
            append(.path, .objectPath(path))
        }

        if let interface = self.interface {
            append(.interface, .string(interface.rawValue))
        }

        if let member = self.member {
            append(.member, .string(member.rawValue))
        }

        if let errorName = self.errorName {
            append(.errorName, .string(errorName.rawValue))
        }

        if let replySerial = self.replySerial {
            append(.replySerial, .uint32(replySerial))
        }

        if let destination = self.destination {
            append(.destination, .string(destination.rawValue))
        }

        if let sender = self.sender {
            append(.sender, .string(sender.rawValue))
        }

        // The signature field is omitted when the body is empty.
        if arguments.isEmpty == false {
            append(.signature, .signature(signature))
        }

        if let count = unixFileDescriptorCount ?? self.unixFileDescriptorCount, count > 0 {
            append(.unixFileDescriptors, .uint32(count))
        }

        let elementType = DBusSignature.ValueType.struct([.byte, .variant])

        guard let array = DBusMessageArgument.Array(type: elementType, fields)
            else { fatalError("Header fields are all (yv) structs") }

        return array
    }
}

// MARK: - Decoding

public extension DBusMessage {

    /// The total length of the message beginning at the start of `bytes`, or `nil` if not
    /// enough bytes are available to determine it yet.
    ///
    /// Used by the read loop to frame the stream: read 16 bytes, learn the length, read the rest.
    static func length(from bytes: [UInt8]) throws -> Int? {

        guard bytes.count >= minimumHeaderLength
            else { return nil }

        guard let endianness = DBusEndianness(rawValue: bytes[0])
            else { throw DBusProtocolError.invalidByteOrder(bytes[0]) }

        var unmarshaller = DBusUnmarshaller(bytes: bytes, endianness: endianness, offset: 4)
        let bodyLength = Int(try unmarshaller.readIntegerUnaligned(UInt32.self))
        _ = try unmarshaller.readIntegerUnaligned(UInt32.self) // serial
        let fieldsLength = Int(try unmarshaller.readIntegerUnaligned(UInt32.self))

        guard fieldsLength <= maximumArrayLength
            else { throw DBusProtocolError.messageTooLarge(UInt32(truncatingIfNeeded: fieldsLength)) }

        // Header fields start at 16, then the header is padded to 8 before the body.
        let headerEnd = minimumHeaderLength + fieldsLength
        let paddedHeaderEnd = headerEnd.aligned(to: 8)
        let total = paddedHeaderEnd + bodyLength

        guard total <= maximumMessageLength, total >= 0
            else { throw DBusProtocolError.messageTooLarge(UInt32(truncatingIfNeeded: total)) }

        return total
    }

    /// Decode a message from its wire representation.
    ///
    /// - Parameters:
    ///   - bytes: A buffer beginning with a complete message. Trailing bytes are ignored.
    ///   - fileDescriptors: Descriptors received out of band with this message. Any `UNIX_FD`
    ///     argument indexes into these, and the decoded arguments carry the real descriptors.
    /// - Returns: The decoded message and the number of bytes it occupied.
    static func decode(_ bytes: [UInt8],
                       fileDescriptors: [Int32] = []) throws -> (message: DBusMessage, length: Int) {

        guard let total = try length(from: bytes)
            else { throw DBusProtocolError.endOfStream }

        guard bytes.count >= total
            else { throw DBusProtocolError.endOfStream }

        guard let endianness = DBusEndianness(rawValue: bytes[0])
            else { throw DBusProtocolError.invalidByteOrder(bytes[0]) }

        guard let type = DBusMessageType(rawValue: bytes[1])
            else { throw DBusProtocolError.invalidMessageType(bytes[1]) }

        let flags = Flags(rawValue: bytes[2])

        guard bytes[3] == protocolVersion
            else { throw DBusProtocolError.invalidProtocolVersion(bytes[3]) }

        var unmarshaller = DBusUnmarshaller(bytes: bytes, endianness: endianness, offset: 4)
        let bodyLength = Int(try unmarshaller.readIntegerUnaligned(UInt32.self))
        let serial = try unmarshaller.readIntegerUnaligned(UInt32.self)

        // Header fields: a(yv)
        let fieldsType = DBusSignature.ValueType.array(.struct([.byte, .variant]))
        let fieldsArgument = try unmarshaller.read(fieldsType)

        guard case let .array(fieldsArray) = fieldsArgument
            else { throw DBusProtocolError.invalidHeaderField(0) }

        var message = DBusMessage(type: type, flags: flags, serial: serial)
        var bodySignature: DBusSignature?

        for field in fieldsArray {

            guard case let .struct(structure) = field,
                structure.count == 2,
                case let .byte(rawCode) = structure[0],
                case let .variant(variant) = structure[1]
                else { throw DBusProtocolError.invalidHeaderField(0) }

            // Unknown field codes must be ignored, not rejected, so that future
            // specification additions do not break this implementation.
            guard let code = DBusHeaderFieldCode(rawValue: rawCode)
                else { continue }

            let value = variant.element

            guard value.type == code.valueType
                else { throw DBusProtocolError.typeMismatch(expected: String(code.valueType),
                                                            actual: String(value.type)) }

            switch (code, value) {

            case let (.path, .objectPath(path)):
                message.path = path

            case let (.interface, .string(string)):
                guard let interface = DBusInterface(rawValue: string)
                    else { throw DBusProtocolError.invalidValue("Invalid interface '\(string)'") }
                message.interface = interface

            case let (.member, .string(string)):
                guard let member = DBusMember(rawValue: string)
                    else { throw DBusProtocolError.invalidValue("Invalid member '\(string)'") }
                message.member = member

            case let (.errorName, .string(string)):
                guard let name = DBusError.Name(rawValue: string)
                    else { throw DBusProtocolError.invalidValue("Invalid error name '\(string)'") }
                message.errorName = name

            case let (.replySerial, .uint32(value)):
                message.replySerial = value

            case let (.destination, .string(string)):
                guard let busName = DBusBusName(rawValue: string)
                    else { throw DBusProtocolError.invalidValue("Invalid destination '\(string)'") }
                message.destination = busName

            case let (.sender, .string(string)):
                guard let busName = DBusBusName(rawValue: string)
                    else { throw DBusProtocolError.invalidValue("Invalid sender '\(string)'") }
                message.sender = busName

            case let (.signature, .signature(signature)):
                bodySignature = signature

            case let (.unixFileDescriptors, .uint32(value)):
                message.unixFileDescriptorCount = value

            default:
                throw DBusProtocolError.invalidHeaderField(rawCode)
            }
        }

        // The header is padded to 8 before the body.
        let bodyStart = unmarshaller.offset.aligned(to: 8)

        guard bodyStart + bodyLength <= bytes.count
            else { throw DBusProtocolError.endOfStream }

        if let bodySignature = bodySignature, bodySignature.isEmpty == false {

            let body = Swift.Array(bytes[bodyStart ..< bodyStart + bodyLength])
            var bodyUnmarshaller = DBusUnmarshaller(bytes: body,
                                                    endianness: endianness,
                                                    fileDescriptors: fileDescriptors)
            message.arguments = try bodyUnmarshaller.read(signature: bodySignature)

            guard bodyUnmarshaller.isAtEnd
                else { throw DBusProtocolError.invalidValue("Body has \(bodyUnmarshaller.remaining) trailing bytes") }

        } else {

            guard bodyLength == 0
                else { throw DBusProtocolError.missingHeaderField("signature") }
        }

        return (message, total)
    }
}

// MARK: - Supporting

internal extension Int {

    /// The value rounded up to the next multiple of `alignment`.
    func aligned(to alignment: Int) -> Int {

        precondition(alignment > 0)

        let remainder = self % alignment
        return remainder == 0 ? self : self + (alignment - remainder)
    }
}
