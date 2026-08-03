//
//  DBusAddress.swift
//  DBus
//

/// A D-Bus server address.
///
/// An address string is one or more alternatives separated by `;`, each of the form
/// `transport:key=value,key=value`. Values are percent-encoded: any byte may be written as
/// `%` followed by two hexadecimal digits, and the characters that are *not* optionally
/// escaped are `[-0-9A-Za-z_/.\\*]`.
///
/// Reference: https://dbus.freedesktop.org/doc/dbus-specification.html#addresses
public struct DBusAddress: Equatable, Hashable, Sendable {

    /// The transport name, e.g. `unix`.
    public let transport: String

    /// The transport-specific key/value parameters, in the order they appeared.
    public let properties: [(key: String, value: String)]

    internal init(transport: String, properties: [(key: String, value: String)]) {

        self.transport = transport
        self.properties = properties
    }

    public static func == (lhs: DBusAddress, rhs: DBusAddress) -> Bool {

        return lhs.transport == rhs.transport
            && lhs.properties.count == rhs.properties.count
            && zip(lhs.properties, rhs.properties).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }

    public func hash(into hasher: inout Hasher) {

        hasher.combine(transport)
        for property in properties {
            hasher.combine(property.key)
            hasher.combine(property.value)
        }
    }
}

public extension DBusAddress {

    /// The value of the given parameter, if present.
    subscript (key: String) -> String? {

        return properties.first(where: { $0.key == key })?.value
    }
}

// MARK: - Parsing

public extension DBusAddress {

    /// Parse an address string, which may list several alternatives separated by `;`.
    ///
    /// - Returns: Every alternative, in preference order. Empty alternatives are skipped,
    /// since a trailing `;` is permitted.
    static func parse(_ string: String) throws -> [DBusAddress] {

        var addresses = [DBusAddress]()

        for alternative in string.split(separator: ";", omittingEmptySubsequences: true) {

            addresses.append(try parseSingle(String(alternative), original: string))
        }

        guard addresses.isEmpty == false
            else { throw DBusProtocolError.invalidAddress(string) }

        return addresses
    }

    private static func parseSingle(_ string: String, original: String) throws -> DBusAddress {

        guard let colonIndex = string.firstIndex(of: ":")
            else { throw DBusProtocolError.invalidAddress(original) }

        let transport = String(string[string.startIndex ..< colonIndex])

        guard transport.isEmpty == false
            else { throw DBusProtocolError.invalidAddress(original) }

        let parameterString = string[string.index(after: colonIndex)...]

        var properties = [(key: String, value: String)]()

        for parameter in parameterString.split(separator: ",", omittingEmptySubsequences: true) {

            guard let equalsIndex = parameter.firstIndex(of: "=")
                else { throw DBusProtocolError.invalidAddress(original) }

            let key = String(parameter[parameter.startIndex ..< equalsIndex])
            let rawValue = parameter[parameter.index(after: equalsIndex)...]

            guard key.isEmpty == false,
                let value = unescape(String(rawValue))
                else { throw DBusProtocolError.invalidAddress(original) }

            properties.append((key: key, value: value))
        }

        return DBusAddress(transport: transport, properties: properties)
    }

    /// Decode percent-escaped bytes, e.g. `%2F` becomes `/`.
    internal static func unescape(_ string: String) -> String? {

        guard string.contains("%")
            else { return string }

        var bytes = [UInt8]()
        var iterator = string.utf8.makeIterator()

        while let byte = iterator.next() {

            guard byte == 0x25 // '%'
                else { bytes.append(byte); continue }

            guard let high = iterator.next().flatMap(hexDigit),
                let low = iterator.next().flatMap(hexDigit)
                else { return nil }

            bytes.append(high << 4 | low)
        }

        return String(validating: bytes, as: UTF8.self)
    }

    private static func hexDigit(_ byte: UInt8) -> UInt8? {

        switch byte {
        case 0x30 ... 0x39: return byte - 0x30 // 0-9
        case 0x41 ... 0x46: return byte - 0x41 + 10 // A-F
        case 0x61 ... 0x66: return byte - 0x61 + 10 // a-f
        default: return nil
        }
    }
}

// MARK: - Well Known Buses

public extension DBusAddress {

    /// The address of the well known bus of the given type, from the environment.
    ///
    /// - Throws: `DBusProtocolError.invalidAddress` if the relevant environment variable is
    /// unset and no default applies.
    static func addresses(for busType: DBusBusType) throws -> [DBusAddress] {

        switch busType {

        case .session:
            guard let string = ProcessEnvironment.value(for: "DBUS_SESSION_BUS_ADDRESS")
                else { throw DBusProtocolError.invalidAddress("DBUS_SESSION_BUS_ADDRESS is not set") }
            return try parse(string)

        case .system:
            // Unlike the session bus, the system bus has a well known default location.
            let string = ProcessEnvironment.value(for: "DBUS_SYSTEM_BUS_ADDRESS")
                ?? "unix:path=/var/run/dbus/system_bus_socket"
            return try parse(string)

        case .starter:
            guard let string = ProcessEnvironment.value(for: "DBUS_STARTER_ADDRESS")
                else { throw DBusProtocolError.invalidAddress("DBUS_STARTER_ADDRESS is not set") }
            return try parse(string)
        }
    }
}

// MARK: - Socket Address

public extension DBusAddress {

    /// The Unix socket this address refers to.
    ///
    /// Recognises `unix:path=`, `unix:abstract=`, `unix:tmpdir=` and `unix:runtime=yes`.
    ///
    /// - Throws: `DBusProtocolError.invalidAddress` if the transport is not `unix`, or if no
    /// recognised parameter is present.
    func unixSocketAddress() throws -> DBusUnixSocketAddress {

        guard transport == "unix"
            else { throw DBusProtocolError.invalidAddress("Unsupported transport '\(transport)'") }

        if let path = self["path"] {
            return .path(path)
        }

        if let abstract = self["abstract"] {
            return .abstract(abstract)
        }

        if self["runtime"] == "yes" {

            guard let runtimeDirectory = ProcessEnvironment.value(for: "XDG_RUNTIME_DIR")
                else { throw DBusProtocolError.invalidAddress("XDG_RUNTIME_DIR is not set") }

            return .path(runtimeDirectory + "/bus")
        }

        throw DBusProtocolError.invalidAddress("No socket path in unix address")
    }
}

// MARK: - Description

extension DBusAddress: CustomStringConvertible {

    public var description: String {

        let parameters = properties.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return "\(transport):\(parameters)"
    }
}
