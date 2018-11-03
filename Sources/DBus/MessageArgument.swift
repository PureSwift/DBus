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

public extension DBusSignature {
    
    public init(_ argument: DBusMessageArgument) {
        
        switch argument {
        case .byte: self = [.byte]
        case .boolean: self = [.boolean]
        case .int16: self = [.int16]
        case .uint16: self = [.uint16]
        case .int32: self = [.int32]
        case .uint32: self = [.uint32]
        case .int64: self = [.int64]
        case .uint64: self = [.uint64]
        case .double: self = [.double]
        case .fileDescriptor: self = [.fileDescriptor]
        case .string: self = [.string]
        case .objectPath: self = [.objectPath]
        case .signature: self = [.signature]
        case let .array(array): self = array.signature
        }
    }
    
    public init(_ arguments: [DBusMessageArgument]) {
        
        let elements = arguments.reduce([], { $0 + DBusSignature($1).elements })
        self.init(elements)
    }
}
