//
//  BusName.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 11/3/18.
//

/**
 Bus names
 Connections have one or more bus names associated with them. A connection has exactly one bus name that is a unique connection name. The unique connection name remains with the connection for its entire lifetime. A bus name is of type STRING, meaning that it must be valid UTF-8. However, there are also some additional restrictions that apply to bus names specifically:

 * Bus names that start with a colon (':') character are unique connection names. Other bus names are called well-known bus names.

 * Bus names are composed of 1 or more elements separated by a period ('.') character. All elements must contain at least one character.

 * Each element must only contain the ASCII characters "[A-Z][a-z][0-9]_-", with "-" discouraged in new bus names. Only elements that are part of a unique connection name may begin with a digit, elements in other bus names must not begin with a digit.

 * Bus names must contain at least one '.' (period) character (and thus at least two elements).

 * Bus names must not begin with a '.' (period) character.

 * Bus names must not exceed the maximum name length.

 Note that the hyphen ('-') character is allowed in bus names but not in interface names. It is also problematic or not allowed in various specifications and APIs that refer to D-Bus, such as Flatpak application IDs, the DBusActivatable interface in the Desktop Entry Specification, and the convention that an application's "main" interface and object path resemble its bus name. To avoid situations that require special-case handling, it is recommended that new D-Bus names consistently replace hyphens with underscores.

 Like interface names, well-known bus names should start with the reversed DNS domain name of the author of the interface (in lower-case), and it is conventional for the rest of the well-known bus name to consist of words run together, with initial capital letters. As with interface names, including a version number in well-known bus names is a good idea; it's possible to have the well-known bus name for more than one version simultaneously if backwards compatibility is required.

 As with interface names, if the author's DNS domain name contains hyphen/minus characters they should be replaced by underscores, and if it contains leading digits they should be escaped by prepending an underscore. For example, if the owner of 7-zip.org used a D-Bus name for an archiving application, it might be named `org._7_zip.Archiver`.
 */
public struct DBusBusName: RawRepresentable, Equatable, Hashable, Sendable {

    public let rawValue: String

    public init?(rawValue: String) {

        do { try DBusBusName.validate(rawValue) }
        catch { return nil }

        self.rawValue = rawValue
    }
}

public extension DBusBusName {

    /// Bus names that start with a colon (':') character are unique connection names.
    var isUnique: Bool {

        return rawValue.utf8.first == DBusBusName.uniquePrefix
    }
}

internal extension DBusBusName {

    static let length = (min: 1, max: 255)

    static let separator = ".".first!

    /// ASCII ':'
    static let uniquePrefix: UInt8 = 0x3A

    init(_ unsafe: String) {

        guard let value = DBusBusName(rawValue: unsafe)
            else { fatalError("Invalid bus name \(unsafe)") }

        self = value
    }

    static func validate(_ string: String) throws {

        guard string.utf8.count >= length.min,
            string.utf8.count <= length.max
            else { throw DBusError.invalidBusName(string) }

        // Bus names that start with a colon are unique connection names. Only in those may an
        // element begin with a digit.
        let isUnique = string.utf8.first == uniquePrefix
        let body = isUnique ? string.dropFirst() : Substring(string)

        guard body.first != separator, // must not begin with '.'
            body.last != separator, // no trailing '.'
            body.contains(separator) // at least two elements
            else { throw DBusError.invalidBusName(string) }

        let elements = body.split(separator: separator,
                                  maxSplits: .max,
                                  omittingEmptySubsequences: false)

        guard elements.count > 1
            else { throw DBusError.invalidBusName(string) }

        for element in elements {

            let bytes = element.utf8

            guard let first = bytes.first,
                isUnique || first.isASCIIDigit == false,
                bytes.allSatisfy({ $0.isBusNameElementByte })
                else { throw DBusError.invalidBusName(string) }
        }
    }
}

internal extension UInt8 {

    /// Whether the byte is one of the ASCII characters "[A-Z][a-z][0-9]_-"
    var isBusNameElementByte: Bool {

        return isObjectPathElementByte || self == 0x2D // '-'
    }
}

private extension DBusError {

    static func invalidBusName(_ string: String) -> DBusError {

        return DBusError(name: .invalidArguments, message: "Bus name was not valid: '\(string)'")
    }
}

// MARK: - CustomStringConvertible

extension DBusBusName: CustomStringConvertible {

    public var description: String {

        return rawValue
    }
}
