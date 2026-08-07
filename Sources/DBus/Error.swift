//
//  Error.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

/// DBus type representing an exception.
///
/// This is a *bus-level* error: it carries an `org.freedesktop.DBus.Error.*` name and a
/// human-readable message, and corresponds to an error reply on the wire. Framing and
/// marshalling failures are reported as ``DBusProtocolError`` instead.
public struct DBusError: Error, Equatable, Hashable, Sendable {

    /// Error name field
    public let name: DBusError.Name

    /// Error message field
    public let message: String

    public init(name: DBusError.Name, message: String) {

        self.name = name
        self.message = message
    }
}

// MARK: - CustomStringConvertible

extension DBusError: CustomStringConvertible {

    public var description: String {

        return "\(name): \(message)"
    }
}

// MARK: Error Name

public extension DBusError {

    /// A D-Bus error name.
    ///
    /// Error names follow the same syntax rules as interface names.
    struct Name: Equatable, Hashable, Sendable {

        public let rawValue: String

        public init?(rawValue: String) {

            do { try DBusInterface.validate(rawValue) }
            catch { return nil }

            self.rawValue = rawValue
        }
    }
}

internal extension DBusError.Name {

    /// Initialize with a string known at compile time to be valid.
    init(_ unsafe: String) {

        guard let value = DBusError.Name(rawValue: unsafe)
            else { fatalError("Invalid error name \(unsafe)") }

        self = value
    }
}

public extension DBusError.Name {

    init(_ interface: DBusInterface) {

        // should be valid
        self.rawValue = interface.rawValue
    }
}

public extension DBusInterface {

    init(_ error: DBusError.Name) {

        self.init(rawValue: error.rawValue)!
    }
}

public extension DBusError.Name {

    /// A generic error; "something went wrong" - see the error message for more.
    ///
    /// `org.freedesktop.DBus.Error.Failed`
    static let failed = DBusError.Name("org.freedesktop.DBus.Error.Failed")

    /// No Memory
    ///
    /// `org.freedesktop.DBus.Error.NoMemory`
    static let noMemory = DBusError.Name("org.freedesktop.DBus.Error.NoMemory")

    /// Existing file and the operation you're using does not silently overwrite.
    ///
    /// `org.freedesktop.DBus.Error.FileExists`
    static let fileExists = DBusError.Name("org.freedesktop.DBus.Error.FileExists")

    /// Missing file.
    ///
    /// `org.freedesktop.DBus.Error.FileNotFound`
    static let fileNotFound = DBusError.Name("org.freedesktop.DBus.Error.FileNotFound")

    /// Invalid arguments
    ///
    /// `org.freedesktop.DBus.Error.InvalidArgs`
    static let invalidArguments = DBusError.Name("org.freedesktop.DBus.Error.InvalidArgs")

    /// Invalid signature
    ///
    /// `org.freedesktop.DBus.Error.InvalidSignature`
    static let invalidSignature = DBusError.Name("org.freedesktop.DBus.Error.InvalidSignature")

    /// The bus doesn't know how to launch a service to supply the bus name you wanted.
    ///
    /// `org.freedesktop.DBus.Error.ServiceUnknown`
    static let serviceUnknown = DBusError.Name("org.freedesktop.DBus.Error.ServiceUnknown")

    /// The bus name you referenced doesn't exist (i.e. no application owns it).
    ///
    /// `org.freedesktop.DBus.Error.NameHasNoOwner`
    static let nameHasNoOwner = DBusError.Name("org.freedesktop.DBus.Error.NameHasNoOwner")

    /// Method not found on the object.
    ///
    /// `org.freedesktop.DBus.Error.UnknownMethod`
    static let unknownMethod = DBusError.Name("org.freedesktop.DBus.Error.UnknownMethod")

    /// Object does not exist at the given path.
    ///
    /// `org.freedesktop.DBus.Error.UnknownObject`
    static let unknownObject = DBusError.Name("org.freedesktop.DBus.Error.UnknownObject")

    /// Interface not implemented by the object.
    ///
    /// `org.freedesktop.DBus.Error.UnknownInterface`
    static let unknownInterface = DBusError.Name("org.freedesktop.DBus.Error.UnknownInterface")

    /// Property does not exist on the interface.
    ///
    /// `org.freedesktop.DBus.Error.UnknownProperty`
    static let unknownProperty = DBusError.Name("org.freedesktop.DBus.Error.UnknownProperty")

    /// Property is read-only.
    ///
    /// `org.freedesktop.DBus.Error.PropertyReadOnly`
    static let propertyReadOnly = DBusError.Name("org.freedesktop.DBus.Error.PropertyReadOnly")

    /// Permission denied.
    ///
    /// `org.freedesktop.DBus.Error.AccessDenied`
    static let accessDenied = DBusError.Name("org.freedesktop.DBus.Error.AccessDenied")

    /// The operation is not supported.
    ///
    /// `org.freedesktop.DBus.Error.NotSupported`
    static let notSupported = DBusError.Name("org.freedesktop.DBus.Error.NotSupported")

    /// The call timed out.
    ///
    /// `org.freedesktop.DBus.Error.NoReply`
    static let noReply = DBusError.Name("org.freedesktop.DBus.Error.NoReply")

    /// The connection is disconnected and you're trying to use it.
    ///
    /// `org.freedesktop.DBus.Error.Disconnected`
    static let disconnected = DBusError.Name("org.freedesktop.DBus.Error.Disconnected")

    /// The address given was not valid.
    ///
    /// `org.freedesktop.DBus.Error.BadAddress`
    static let badAddress = DBusError.Name("org.freedesktop.DBus.Error.BadAddress")

    /// A limit was exceeded.
    ///
    /// `org.freedesktop.DBus.Error.LimitsExceeded`
    static let limitsExceeded = DBusError.Name("org.freedesktop.DBus.Error.LimitsExceeded")
}

extension DBusError.Name: CustomStringConvertible {

    public var description: String {

        return rawValue
    }
}

extension DBusError.Name: RawRepresentable { }

// MARK: - Protocol Error

/// An error in the D-Bus wire protocol: framing, marshalling, transport or authentication.
///
/// Distinct from ``DBusError``, which models an error *reply* sent by a peer.
public enum DBusProtocolError: Error, Equatable, Hashable, Sendable {

    /// The stream ended before a complete message could be read.
    case endOfStream

    /// The endianness byte was neither `l` nor `B`.
    case invalidByteOrder(UInt8)

    /// The protocol version was not `1`.
    case invalidProtocolVersion(UInt8)

    /// The message type code was not recognised.
    case invalidMessageType(UInt8)

    /// A header field could not be decoded.
    case invalidHeaderField(UInt8)

    /// A required header field was absent for this message type.
    case missingHeaderField(String)

    /// The declared length exceeds the maximum message size.
    case messageTooLarge(UInt32)

    /// A type code in the wire data was not a valid signature.
    case invalidSignature(String)

    /// A marshalled value did not match its declared type.
    case typeMismatch(expected: String, actual: String)

    /// A string field was not valid UTF-8, or was not NUL-terminated.
    case invalidString

    /// A padding byte was non-zero, which the specification forbids.
    case invalidPadding

    /// The value could not be represented, e.g. an array whose elements are not homogeneous.
    case invalidValue(String)

    /// The bus address string could not be parsed.
    case invalidAddress(String)

    /// No supported authentication mechanism was offered by the peer.
    case authenticationFailed(String)

    /// The peer rejected the connection during the SASL handshake.
    case authenticationRejected(String)
}

extension DBusProtocolError: CustomStringConvertible {

    public var description: String {

        switch self {
        case .endOfStream:
            return "The stream ended before a complete message could be read"
        case let .invalidByteOrder(byte):
            return "Invalid byte order marker: \(byte)"
        case let .invalidProtocolVersion(version):
            return "Unsupported protocol version: \(version)"
        case let .invalidMessageType(type):
            return "Invalid message type: \(type)"
        case let .invalidHeaderField(code):
            return "Invalid header field code: \(code)"
        case let .missingHeaderField(name):
            return "Missing required header field: \(name)"
        case let .messageTooLarge(length):
            return "Message length \(length) exceeds the maximum message size"
        case let .invalidSignature(string):
            return "Invalid signature: '\(string)'"
        case let .typeMismatch(expected, actual):
            return "Type mismatch: expected \(expected), found \(actual)"
        case .invalidString:
            return "Invalid string value"
        case .invalidPadding:
            return "Non-zero padding byte"
        case let .invalidValue(reason):
            return "Invalid value: \(reason)"
        case let .invalidAddress(string):
            return "Invalid bus address: '\(string)'"
        case let .authenticationFailed(reason):
            return "Authentication failed: \(reason)"
        case let .authenticationRejected(reason):
            return "Authentication rejected: \(reason)"
        }
    }
}
