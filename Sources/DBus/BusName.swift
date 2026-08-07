//
//  BusName.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 11/3/18.
//

import Foundation
import CDBus

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
 
 If a well-known bus name implies the presence of a "main" interface, that "main" interface is often given the same name as the well-known bus name, and situated at the corresponding object path. For instance, if the owner of example.com is developing a D-Bus API for a music player, they might define that any application that takes the well-known name `com.example.MusicPlayer1` should have an object at the object path `/com/example/MusicPlayer1` which implements the interface `com.example.MusicPlayer1`.
 */
public struct DBusBusName: RawRepresentable, Equatable, Hashable {
    
    public let rawValue: String
    
    public init?(rawValue: String) {
        
        do { try DBusBusName.validate(rawValue) }
        catch { return nil }
        
        self.rawValue = rawValue
    }
}

internal extension DBusBusName {
    
    init(_ unsafe: String) {
        
        precondition(DBusBusName(rawValue: unsafe) != nil, "Invalid bus name \(unsafe)")
        
        self.rawValue = unsafe
    }
}

internal extension DBusBusName {
    
    static func validate(_ string: String) throws {
        
        let error = DBusError()
        guard Bool(dbus_validate_bus_name(string, &error.internalValue))
            else { throw error }
    }
}

// MARK: - CustomStringConvertible

extension DBusBusName: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}
