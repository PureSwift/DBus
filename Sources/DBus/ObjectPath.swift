//
//  ObjectPath.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/20/18.
//

public struct DBusObjectPath: RawRepresentable {
    
    internal static let length = (min:1, max: 255)
    
    @_versioned
    internal let elements: [Element]
    
    public init?(rawValue: String) {
        
        // The path must begin with an ASCII '/' (integer 47) character,
        // and must consist of elements separated by slash characters.
        guard let firstCharacter = rawValue.first,
            firstCharacter == DBusObjectPath.separator
            else { return nil }
        
        let elements = rawValue.split(separator: DBusObjectPath.separator,
                                      maxSplits: .max,
                                      omittingEmptySubsequences: true)
            .compactMap {  }
        
        
    }
    
    public var rawValue: String {
        
        return path.reduce("", { $0 + "/" + $1.rawValue })
    }
}

private extension DBusObjectPath {
    
    static let separator = "/".first!
}

extension DBusObjectPath: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}

// MARK: - Element

public extension DBusObjectPath {
    
    /// An element in the object path
    public struct Element: RawRepresentable {
        
        public let rawValue: String
        
        public init?(rawValue: String) {
            
            guard rawValue.isEmpty == false // No element may be the empty string.
                else { return nil }
        }
    }
}

extension DBusObjectPath.Element: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}
