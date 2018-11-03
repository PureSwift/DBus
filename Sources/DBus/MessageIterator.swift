//
//  MessageIterator.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/12/18.
//

import CDBus

internal extension DBusMessageIter {
    
    /// Initializes a DBusMessageIter for appending arguments to the end of a message.
    init(message: DBusMessage) {
        
        self.init()
        dbus_message_iter_init_append(message.internalPointer, &self)
    }
    
    mutating func append(argument: DBusMessageArgument) throws {
        
        switch argument {
            
        case let .byte(value):
            var basicValue = DBusBasicValue(byt: value)
            try append(&basicValue, .byte)
        case let .boolean(value):
            var basicValue = DBusBasicValue(bool_val: dbus_bool_t(value))
            try append(&basicValue, .boolean)
        case let .int16(value):
            var basicValue = DBusBasicValue(i16: value)
            try append(&basicValue, .int16)
        case let .uint16(value):
            var basicValue = DBusBasicValue(u16: value)
            try append(&basicValue, .uint16)
        case let .int32(value):
            var basicValue = DBusBasicValue(i32: value)
            try append(&basicValue, .int32)
        case let .uint32(value):
            var basicValue = DBusBasicValue(u32: value)
            try append(&basicValue, .uint32)
        case let .int64(value):
            var basicValue = DBusBasicValue(i64: dbus_int64_t(value))
            try append(&basicValue, .int64)
        case let .uint64(value):
            var basicValue = DBusBasicValue(u64: dbus_uint64_t(value))
            try append(&basicValue, .uint64)
        case let .double(value):
            var basicValue = DBusBasicValue(dbl: value)
            try append(&basicValue, .double)
        case let .fileDescriptor(value):
            var basicValue = DBusBasicValue(fd: value)
            try append(&basicValue, .fileDescriptor)
            
        case let .string(value):
            try append(value)
        case let .objectPath(value):
            try append(value.rawValue, .objectPath)
        case let .signature(value):
            try append(value.rawValue, .signature)
            
        case let .array(value):
            //appendContainer(type: .array, container: <#T##(inout DBusMessageIter) throws -> ()#>)
            fatalError()
        case let .variant:
            fatalError()
            
        }
    }
    
    private mutating func append(_ basicValue: inout DBusBasicValue, _ type: DBusType) throws {
        
        guard withUnsafePointer(to: &basicValue, {
            Bool(dbus_message_iter_append_basic(&self, Int32(type.integerValue), UnsafeRawPointer($0)))
        }) else { throw DBusError.messageAppendOutOfMemory }
    }
    
    private mutating func append(_ string: String, _ type: DBusType = .string) throws {
        
        try string.withCString {
            let cString = UnsafeMutablePointer<Int8>(mutating: $0)
            var basicValue = DBusBasicValue(str: cString)
            try append(&basicValue, type)
        }
    }
    
    mutating func appendContainer(type: DBusType, signature: String? = nil, container: (inout DBusMessageIter) throws -> ()) throws {
        
        var subIterator = DBusMessageIter()
        
        guard Bool(dbus_message_iter_open_container(&self, Int32(type.integerValue), signature, &subIterator))
            else { throw DBusError.messageAppendOutOfMemory }
        
        defer { dbus_message_iter_close_container(&self, &subIterator) }
        
        try container(&subIterator)
    }
}

private extension DBusError {
    
    // Argument could not be appended due to lack of memory.
    static var messageAppendOutOfMemory: DBusError {
        
        // If this fails due to lack of memory, the message is hosed and you have to start over building the whole message.
        // FALSE if not enough memory
        return DBusError(name: .noMemory, message: "Argument could not be appended to message due to lack of memory.")
    }
}
