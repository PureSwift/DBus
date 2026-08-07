//
//  Member.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 11/3/18.
//

/**
 DBus Member Name

 Member (i.e. method or signal) names:
 * Must only contain the ASCII characters "[A-Z][a-z][0-9]_" and may not begin with a digit.
 * Must not contain the '.' (period) character.
 * Must not exceed the maximum name length.
 * Must be at least 1 byte in length.

 It is conventional for member names on D-Bus to consist of capitalized words with no punctuation ("camel-case"). Method names should usually be verbs, such as "`GetItems`", and signal names should usually be a description of an event, such as "`ItemsChanged`".
 */
public struct DBusMember: RawRepresentable, Equatable, Hashable, Sendable {

    public let rawValue: String

    public init?(rawValue: String) {

        do { try DBusMember.validate(rawValue) }
        catch { return nil }

        self.rawValue = rawValue
    }
}

internal extension DBusMember {

    static let length = (min: 1, max: 255)

    init(_ unsafe: String) {

        guard let value = DBusMember(rawValue: unsafe)
            else { fatalError("Invalid member \(unsafe)") }

        self = value
    }

    static func validate(_ string: String) throws {

        let bytes = string.utf8

        guard bytes.count >= length.min,
            bytes.count <= length.max
            else { throw DBusError.invalidMember(string) }

        // May not begin with a digit. The allowed character set excludes '.' by construction.
        guard let first = bytes.first,
            first.isASCIIDigit == false,
            bytes.allSatisfy({ $0.isObjectPathElementByte })
            else { throw DBusError.invalidMember(string) }
    }
}

private extension DBusError {

    static func invalidMember(_ string: String) -> DBusError {

        return DBusError(name: .invalidArguments, message: "Member name was not valid: '\(string)'")
    }
}

// MARK: - CustomStringConvertible

extension DBusMember: CustomStringConvertible {

    public var description: String {

        return rawValue
    }
}
