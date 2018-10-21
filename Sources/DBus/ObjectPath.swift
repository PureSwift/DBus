//
//  ObjectPath.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/20/18.
//

/// DBus Object Path
public struct DBusObjectPath {
    
    @_versioned
    internal let reference: Reference
    
    /// Reference type with value semantics
    internal init(reference: Reference) {
        
        self.reference = reference
    }
}

// MARK: - Constants

internal extension DBusObjectPath {
    
    static let separator = "/".first!
}

// MARK: - RawRepresentable

extension DBusObjectPath: RawRepresentable {
    
    public init?(rawValue: String) {
        
        guard let reference = Reference(string: rawValue)
            else { return nil }
        
        self.init(reference: reference)
    }
    
    public var rawValue: String {
        
        get { return reference.string }
    }
}

// MARK: - CustomStringConvertible

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

private extension DBusObjectPath.Element {
    
    static let length = (min: 1, max: 255)
}

extension DBusObjectPath.Element: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}

// MARK: - Reference Backed Value Type

internal extension DBusObjectPath {
    
    /// Internal cache
    final class Reference {
        
        /// initialize with the elements
        internal init(elements: [Element]) {
            
            self.elements = elements
        }
        
        /// Initialize with a string.
        internal convenience init?(string: String) {
            
            // The path must begin with an ASCII '/' (integer 47) character,
            // and must consist of elements separated by slash characters.
            guard let firstCharacter = string.first,
                firstCharacter == DBusObjectPath.separator
                else { return nil }
            
            let pathStrings = string.split(separator: DBusObjectPath.separator,
                                           maxSplits: .max,
                                           omittingEmptySubsequences: true)
            
            var elements = [Element]()
            elements.reserveCapacity(pathStrings.count) // pre-allocate buffer
            
            for elementString in pathStrings {
                
                guard let element = Element(rawValue: String(elementString))
                    else { return nil }
                
                elements.append(element)
            }
            
            self.init(elements: elements)
            self.stringCache = string // store parsed string
        }
        
        /// Parsed elements. Always initialized to this value.
        internal let elements: [Element]
        
        /// Cached String value.
        private var stringCache: String?
        
        /// lazily initialized string value
        internal var string: String {
            
            guard let cache = stringCache else {
                
                // lazily initialize
                let separator = String(DBusObjectPath.separator)
                let stringValue = elements.isEmpty ? separator :
                    elements.reduce("", { $0 + separator + $1.rawValue })
                
                // cache value
                stringCache = stringValue
                
                return stringValue
            }
            
            return cache
        }
    }
}
