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
    case fileDescriptor(FileDescriptor)
    
    case string(String)
    case objectPath(DBusObjectPath)
    case signature(DBusSignature)
    
    case array(Array)
    case `struct`(Structure)
    //case variant
    //case dictionaryEntry
}

public extension DBusMessageArgument {
    
    /// Argument value type. 
    var type: DBusSignature.ValueType {
        
        switch self {
        case .byte: return .byte
        case .boolean: return .boolean
        case .int16: return .int16
        case .int32: return .int32
        case .int64: return .int64
        case .uint16: return .uint16
        case .uint32: return .uint32
        case .uint64: return .uint64
        case .double: return .double
        case .fileDescriptor: return .fileDescriptor
        case .string: return .string
        case .objectPath: return .objectPath
        case .signature: return .signature
        case let .array(array): return .array(array.type)
        case let .struct(structure): return .struct(structure.type)
        }
    }
}

// MARK: - Supporting Types

public extension DBusMessageArgument {
    
    /// File Descriptor
    struct FileDescriptor: RawRepresentable, Equatable, Hashable {
        
        public var rawValue: CInt
        
        public init(rawValue: CInt) {
            
            self.rawValue = rawValue
        }
    }
}

public extension DBusMessageArgument {
    
    /// Structure
    struct Structure: Equatable {
        
        /// Structure elements.
        internal let elements: [DBusMessageArgument]
        
        /// Initializes a structure argument with the specified arguments.
        public init?(_ elements: [DBusMessageArgument]) {
            
            guard elements.isEmpty == false
                else { return nil }
            
            self.elements = elements
        }
    }
}

public extension DBusMessageArgument.Structure {
    
    var type: DBusSignature.StructureType {
        
        let types = elements.map { $0.type }
        
        guard let structureType = DBusSignature.StructureType(types)
            else { fatalError("Invalid structure") }
        
        return structureType
    }
}

// MARK: RandomAccessCollection

extension DBusMessageArgument.Structure: RandomAccessCollection {
    
    public typealias Element = DBusMessageArgument
    
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
    
    public func makeIterator() -> IndexingIterator<DBusMessageArgument.Structure> {
        return IndexingIterator(_elements: self)
    }
}

public extension DBusMessageArgument {
    
    struct Array: Equatable {
        
        /// Array elements.
        internal let elements: [DBusMessageArgument]
        
        /// Type of the elements.
        public let type: DBusSignature.ValueType
        
        /// Initialize with an empty array.
        public init(type: DBusSignature.ValueType) {
            
            self.elements = []
            self.type = type
        }
        
        /// Initialize with an array of homogenous array elements and tries to infer the element value type.
        public init?(_ elements: [Element]) {
            
            // dynamically infer signature
            guard let element = elements.first
                else { return nil } // can't infer from empty array
            
            self.init(type: element.type, elements)
        }
        
        /// Initialize with an array of homogenous array elements.
        public init?(type: DBusSignature.ValueType, _ elements: [Element]) {
            
            // validate homogenous array
            if elements.isEmpty == false {
                
                for element in elements {
                    
                    guard element.type == type
                        else { return nil } // all elements must have the same type
                }
            }
            
            self.elements = elements
            self.type = type
        }
    }
}

// MARK: RandomAccessCollection

extension DBusMessageArgument.Array: RandomAccessCollection {
    
    public typealias Element = DBusMessageArgument
    
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

// MARK: - DBusMessageArgumentValue

internal protocol DBusMessageArgumentValue {
    
    //init?(argument: DBusMessageArgument)
    
    func toArgument() -> DBusMessageArgument
}

extension UInt8: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .byte(self)
    }
}

extension Bool: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .boolean(self)
    }
}

extension Int16: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .int16(self)
    }
}

extension Int32: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .int32(self)
    }
}

extension Int64: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .int64(self)
    }
}

extension UInt16: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .uint16(self)
    }
}

extension UInt32: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .uint32(self)
    }
}

extension UInt64: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .uint64(self)
    }
}

extension Double: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .double(self)
    }
}

extension DBusMessageArgument.FileDescriptor: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .fileDescriptor(self)
    }
}

extension String: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .string(self)
    }
}

extension DBusObjectPath: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .objectPath(self)
    }
}

extension DBusSignature: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .signature(self)
    }
}

extension DBusMessageArgument.Array: DBusMessageArgumentValue {
    
    func toArgument() -> DBusMessageArgument {
        return .array(self)
    }
}
