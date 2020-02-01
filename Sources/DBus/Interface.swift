//
//  Interface.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/24/18.
//

import Foundation
import CDBus

/**
 DBus Interface Name (e.g "`com.example.MusicPlayer1.readValue`")
 
 The various names in D-Bus messages have some restrictions.
 
 There is a maximum name length of 255 which applies to bus names, interfaces, and members.
 
 Interfaces have names with type STRING, meaning that they must be valid UTF-8. However, there are also some additional restrictions that apply to interface names specifically:
 
 Interface names are composed of 1 or more elements separated by a period ('.') character. All elements must contain at least one character.
 
 Each element must only contain the ASCII characters "[A-Z][a-z][0-9]_" and must not begin with a digit.
 
 Interface names must contain at least one '.' (period) character (and thus at least two elements).
 
 Interface names must not begin with a '.' (period) character.
 
 Interface names must not exceed the maximum name length.
 
 Interface names should start with the reversed DNS domain name of the author of the interface (in lower-case), like interface names in Java. It is conventional for the rest of the interface name to consist of words run together, with initial capital letters on all words ("CamelCase"). Several levels of hierarchy can be used. It is also a good idea to include the major version of the interface in the name, and increment it if incompatible changes are made; this way, a single object can implement several versions of an interface in parallel, if necessary.
 
 For instance, if the owner of example.com is developing a D-Bus API for a music player, they might define interfaces called com.example.MusicPlayer1, com.example.MusicPlayer1.Track and com.example.MusicPlayer1.Seekable.
 
 If the author's DNS domain name contains hyphen/minus characters ('-'), which are not allowed in D-Bus interface names, they should be replaced by underscores. If the DNS domain name contains a digit immediately following a period ('.'), which is also not allowed in interface names), the interface name should add an underscore before that digit. For example, if the owner of 7-zip.org defined an interface for out-of-process plugins, it might be named org._7_zip.Plugin.
 
 D-Bus does not distinguish between the concepts that would be called classes and interfaces in Java: either can be identified on D-Bus by an interface name.
 */
public struct DBusInterface {
    
    @usableFromInline
    internal private(set) var elements: [Element]
    
    /// Cached string.
    /// This will be the original string the object path was created from.
    ///
    /// - Note: Any subsequent mutation will set this value to nil, and `rawValue` and `description` getters
    /// will have to rebuild the string for every invocation. Mutating leads to an unoptimized code path,
    /// but for values created from either a string or an array of elements, this value is cached.
    @usableFromInline
    internal private(set) var string: String?
    
    /// Initialize with an array of elements.
    public init?(_ elements: [Element]) {
        
        // Must have at least one period, so at least 2 elements
        guard elements.count > 1
            else { return nil }
        
        self.elements = elements
        self.string = String(elements)
    }
}

internal extension DBusInterface {
    
    static let length = (min: 3, max: 255)
    
    static let separator = ".".first!
    
    static func parse(_ string: String) -> [Element]? {
        
        guard string.count >= length.min,
            string.count <= length.max,
            string.first != separator,
            string.last != separator,
            string.contains(separator)
            else { return nil }
        
        let pathStrings = string.split(separator: separator,
                                       maxSplits: .max,
                                       omittingEmptySubsequences: false)
        
        var elements = [Element]()
        elements.reserveCapacity(pathStrings.count) // pre-allocate buffer
        
        for substring in pathStrings {
            
            guard let element = Element(substring: substring)
                else { return nil }
            
            elements.append(element)
        }
        
        // Must have at least one period, so at least 2 elements
        guard elements.count > 1
            else { return nil }
        
        return elements
    }
    
    static func validate(_ string: String) throws {
        
        let error = DBusError.Reference()
        guard Bool(dbus_validate_interface(string, &error.internalValue))
            else { throw DBusError(error)! }
    }
}

internal extension String {
    
    init(_ interface: [DBusInterface.Element]) {
        
        assert(interface.count > 1, "Must have at least 2 elements")
        
        let separator = String(DBusInterface.separator)
        self = interface.enumerated().reduce("", {
            $0 + $1.element.rawValue + (($1.offset + 1 < interface.count) ? separator : "")
        })
    }
}

extension DBusInterface: RawRepresentable {
    
    public init?(rawValue: String) {
        
        guard let elements = DBusInterface.parse(rawValue)
            else { return nil }
        
        self.elements = elements
        self.string = rawValue
    }
    
    public var rawValue: String {
        
        return string ?? String(elements)
    }
}

extension DBusInterface: Equatable {
    
    public static func == (lhs: DBusInterface, rhs: DBusInterface) -> Bool {
        
        // fast path
        if let lhsString = lhs.string,
            let rhsString = rhs.string {
            
            return lhsString == rhsString
        }
        
        // slower comparison
        return lhs.elements == rhs.elements
    }
}

extension DBusInterface: Hashable {
    
    public var hashValue: Int {
        
        return rawValue.hashValue
    }
}

extension DBusInterface: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}

// MARK: Collection

extension DBusInterface: MutableCollection {
    
    public typealias Index = Int
    
    public subscript (index: Index) -> Element {
        
        get { return elements[index] }
        
        mutating set {
            string = nil
            elements[index] = newValue
        }
    }
    
    public var count: Int {
        
        return elements.count
    }
    
    /// The start `Index`.
    public var startIndex: Index {
        return 0
    }
    
    /// The end `Index`.
    ///
    /// This is the "one-past-the-end" position, and will always be equal to the `count`.
    public var endIndex: Index {
        return count
    }
    
    public func index(before i: Index) -> Index {
        return i - 1
    }
    
    public func index(after i: Index) -> Index {
        return i + 1
    }
    
    public func makeIterator() -> IndexingIterator<DBusInterface> {
        return IndexingIterator(_elements: self)
    }
    
    public mutating func append(_ element: Element) {
        string = nil
        elements.append(element)
    }
}

extension DBusInterface: RandomAccessCollection { }

// MARK: - Element

public extension DBusInterface {
    
    /// An element in the object path
    struct Element {
        
        /// Don't copy buffer of individual elements, because these elements will always be created
        /// from a bigger string, which we should just internally reference.
        internal let substring: Substring
        
        /// Designated initializer.
        internal init?(substring: Substring) {
            
            // validate string
            guard substring.isEmpty == false, // No element may be an empty string.
                substring.contains(DBusInterface.separator) == false, // Multiple '.' characters cannot occur in sequence.
                substring.rangeOfCharacter(from: Element.invalidCharacters) == nil // check for invalid characters
                else { return nil }
            
            // store validated string
            self.substring = substring
        }
    }
}

extension DBusInterface.Element: RawRepresentable {
    
    public init?(rawValue: String) {
        
        // This API will rarely be used
        let substring = Substring(rawValue)
        self.init(substring: substring)
    }
    
    public var rawValue: String {
        
        return String(substring)
    }
}

private extension DBusInterface.Element {
    
    /// only ASCII characters "[A-Z][a-z][0-9]_"
    static let invalidCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLKMNOPQRSTUVWXYZ0123456789_").inverted
}

extension DBusInterface.Element: Equatable {
    
    public static func == (lhs: DBusInterface.Element, rhs: DBusInterface.Element) -> Bool {
        
        return lhs.substring == rhs.substring
    }
}

extension DBusInterface.Element: CustomStringConvertible {
    
    public var description: String {
        
        return rawValue
    }
}

extension DBusInterface.Element: Hashable {
    
    public var hashValue: Int {
        
        return substring.hashValue
    }
}
