//
//  Member.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 11/3/18.
//

import CDBus

/**
 DBus Member Name
 
 Member (i.e. method or signal) names:
 * Must only contain the ASCII characters "[A-Z][a-z][0-9]_" and may not begin with a digit.
 * Must not contain the '.' (period) character.
 * Must not exceed the maximum name length.
 * Must be at least 1 byte in length.
 
 It is conventional for member names on D-Bus to consist of capitalized words with no punctuation ("camel-case"). Method names should usually be verbs, such as "`GetItems`", and signal names should usually be a description of an event, such as "`ItemsChanged`".
 */
public struct DBusMember: RawRepresentable, Equatable, Hashable {
    
    public let rawValue: String
    
    public init?(rawValue: String) {
        
        do { try DBusMember.validate(rawValue) }
        catch { return nil }
        
        self.rawValue = rawValue
    }
}

internal extension DBusMember {
    
    static func validate(_ string: String) throws {
        
        let error = DBusError.Reference()
        guard Bool(dbus_validate_member(string, &error.internalValue))
            else { throw DBusError(error)! }
    }
}

// MARK: - CustomStringConvertible

extension DBusMember: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}
