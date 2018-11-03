//
//  MessageArgument.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/26/16.
//  Copyright © 2016 Pure All rights reserved.
//

import CDBus

/// DBus Message argument value.
public enum DBusMessageArgument: Equatable {
    
    case byte(UInt8)
    case boolean(Bool)
    case int16(Int16)
    case uint16(UInt16)
    case int32(Int32)
    case uint32(UInt32)
    case int64(Int64)
    case uint64(UInt64)
    case double(Double)
    case fileDescriptor(CInt)
    
    case string(String)
    case objectPath(DBusObjectPath)
    case signature(DBusSignature)
    
    case array(Array)
    //case variant
    
    //case `struct`
    //case dictionaryEntry
}

public extension DBusMessageArgument {
    
    public struct Array: Equatable {
        
        /// Array elements.
        internal let elements: [Element]
        
        /// Signature of the array (all elements must have the same signature).
        public let signature: DBusSignature
        
        /// Initialize with an array of homogenous array elements.
        public init?(_ elements: [Element], signature: DBusSignature? = nil) {
            
            let expectedSignature: DBusSignature
            
            if let signature = signature {
                
                expectedSignature = signature
                
            } else {
                
                // dynamically infer signature
                guard let element = elements.first
                    else { return nil } // can't infer from empty array
                
                expectedSignature = DBusSignature(element.values)
            }
            
            // validate homogenous array
            if elements.isEmpty == false {
                
                for element in elements {
                    
                    let elementSignature = DBusSignature(element.values)
                    
                    guard elementSignature == expectedSignature
                        else { return nil } // all elements must have the same signature
                }
            }
            
            self.elements = elements
            self.signature = expectedSignature
        }
        
        /// Initialize with an empty array.
        public init(_ signature: DBusSignature) {
            
            self.elements = []
            self.signature = signature
        }
    }
}


// MARK: RandomAccessCollection

extension DBusMessageArgument.Array: RandomAccessCollection {
    
    public typealias Index = Int
    
    public subscript (index: Index) -> Element {
        return elements[index]
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
    
    public func makeIterator() -> IndexingIterator<DBusMessageArgument.Array> {
        return IndexingIterator(_elements: self)
    }
}

public extension DBusMessageArgument.Array {
    
    public struct Element: Equatable {
        
        internal let values: [DBusMessageArgument]
        
        public init?(_ values: [DBusMessageArgument]) {
            
            // Array must have an element type
            guard values.isEmpty == false
                else { return nil }
            
            self.values = values
        }
    }
}

// MARK: RandomAccessCollection

extension DBusMessageArgument.Array.Element: RandomAccessCollection {
    
    public typealias Element = DBusMessageArgument
    
    public typealias Index = Int
    
    public subscript (index: Index) -> Element {
        return values[index]
    }
    
    public var count: Int {
        return values.count
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
    
    public func makeIterator() -> IndexingIterator<DBusMessageArgument.Array.Element> {
        return IndexingIterator(_elements: self)
    }
}

public extension DBusMessageArgument {
    
    /// DBus Signature
    public var signature: DBusSignature {
        
        return DBusSignature(singatureElements)
    }
    
    internal var singatureElements: [DBusSignature.Element] {
        
        switch self {
        case .byte: return [.byte]
        case .boolean: return [.boolean]
        case .int16: return [.int16]
        case .uint16: return [.uint16]
        case .int32: return [.int32]
        case .uint32: return [.uint32]
        case .int64: return [.int64]
        case .uint64: return [.uint64]
        case .double: return [.double]
        case .fileDescriptor: return [.fileDescriptor]
        case .string: return [.string]
        case .objectPath: return [.objectPath]
        case .signature: return [.signature]
        case let .array(array): return array.signature.elements
        }
    }
}

public extension DBusSignature {
    
    public init(_ arguments: [DBusMessageArgument]) {
        
        self.init(arguments.reduce([], { $0 + $1.singatureElements }))
    }
}
