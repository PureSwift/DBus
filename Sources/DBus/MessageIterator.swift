//
//  MessageIterator.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/12/18.
//

import CDBus

// MARK: - Iterating

extension DBusMessageIter {
    
    init(iterating message: DBusMessage) {
        
        self.init()
        dbus_message_iter_init(message.internalPointer, &self)
    }
    
    mutating func next() -> DBusMessageArgument? {
        
        // make sure there is a valid element
        guard let argumentType = DBusType(Int(dbus_message_iter_get_arg_type(&self)))
            else { return nil }
        
        let value: DBusMessageArgument
        
        switch argumentType {
            
        case .byte:
            value = .byte(readBasic().byt)
        case .boolean:
            value = .boolean(Bool(readBasic().bool_val))
        case .int16:
            value = .int16(readBasic().i16)
        case .int32:
            value = .int32(readBasic().i32)
        case .int64:
            value = .int64(Int64(readBasic().i64))
        case .uint16:
            value = .uint16(readBasic().u16)
        case .uint32:
            value = .uint32(readBasic().u32)
        case .uint64:
            value = .uint64(UInt64(readBasic().u64))
            
        case .string:
            value = .string(readString())
        case .objectPath:
            value = .objectPath(DBusObjectPath(readString()))
        case .signature:
            value = .signature(DBusSignature(readString()))
            
        case .array:
            
            guard let signature = try? self.signature(),
                let arrayType = signature.first,
                case let .array(valueType) = arrayType
                else { fatalError("Invalid array signature \((try? self.signature())?.description ?? "")") }
            
            value = recurse {
                
                var elements = [DBusMessageArgument]()
                
                while let element = $0.next() {
                    elements.append(element)
                }
                
                guard let array = DBusMessageArgument.Array(type: valueType, elements)
                    else { fatalError("Invalid elements") }
                
                return .array(array)
            }
            
        default:
            fatalError()
        }
        
        // move iterator to next element in the sequence
        dbus_message_iter_next(&self)
        
        // return value
        return value
    }
    
    /// Read a basic value into the provided pointer.
    @inline(__always)
    private mutating func readBasic() -> DBusBasicValue {
        
        var basicValue = DBusBasicValue()
        withUnsafeMutablePointer(to: &basicValue) {
            dbus_message_iter_get_basic(&self, UnsafeMutableRawPointer($0))
        }
        return basicValue
    }
    
    private mutating func readString() -> String {
        
        guard let cString = readBasic().str
            else { fatalError("Nil string pointer") }
        
        return String(cString: cString)
    }
    
    /// Recurses into a container value when reading values from a message.
    private mutating func recurse <Result> (_ recurseBlock: (inout DBusMessageIter) throws -> Result) rethrows -> Result {
        
        /**
         Recurses into a container value when reading values from a message, initializing a sub-iterator to use for traversing the child values of the container.
         
         Note that this recurses into a value, not a type, so you can only recurse if the value exists. The main implication of this is that if you have for example an empty array of array of int32, you can recurse into the outermost array, but it will have no values, so you won't be able to recurse further. There's no array of int32 to recurse into.
         */
        
        var subiterator = DBusMessageIter()
        dbus_message_iter_recurse(&self, &subiterator)
        
        return try recurseBlock(&subiterator)
    }
    
    private mutating func signature() throws -> DBusSignature {
        
        guard let cString = dbus_message_iter_get_signature(&self)
            else { throw DBusError(name: .noMemory, message: "Could not get signature") }
        
        let string = String(cString: cString)
        
        dbus_free(UnsafeMutableRawPointer(cString))
        
        return DBusSignature(string)
    }
}

// MARK: - Appending

internal extension DBusMessageIter {
    
    /// A message iterator for which `dbus_message_iter_abandon_container_if_open()` is the only valid operation.
    static var closed: DBusMessageIter {
        
        var iter = DBusMessageIter()
        dbus_message_iter_init_closed(&iter)
        return iter
    }
    
    /**
     Abandons creation of a contained-typed value and frees resources created by dbus_message_iter_open_container().
     
     Once this returns, the message is hosed and you have to start over building the whole message.
     
     Unlike dbus_message_iter_abandon_container(), it is valid to call this function on an iterator that was initialized with DBUS_MESSAGE_ITER_INIT_CLOSED, or an iterator that was already closed or abandoned. However, it is not valid to call this function on uninitialized memory. This is intended to be used in error cleanup code paths, similar to this pattern:
     */
    @inline(__always)
    mutating func abandonContainerIfOpen(_ subcontainer: inout DBusMessageIter) {
        
        dbus_message_iter_abandon_container_if_open(&self, &subcontainer)
    }
}

internal extension DBusMessageIter {
    
    /// Initializes a DBusMessageIter for appending arguments to the end of a message.
    init(appending message: DBusMessage) {
        
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
            var basicValue = DBusBasicValue(fd: value.rawValue)
            try append(&basicValue, .fileDescriptor)
            
        case let .string(value):
            try append(value)
        case let .objectPath(value):
            try append(value.rawValue, .objectPath)
        case let .signature(value):
            try append(value.rawValue, .signature)
            
        case let .array(array):
            try appendContainer(type: .array, signature: DBusSignature([array.type])) {
                for element in array {
                    try $0.append(argument: element)
                }
            }
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
    
    /**
     Appends a container-typed value to the message.
    */
    private mutating func appendContainer(type: DBusType, signature: DBusSignature? = nil, container: (inout DBusMessageIter) throws -> ()) throws {
        
        var subIterator = DBusMessageIter()
        
        /**
         On success, you are required to append the contents of the container using the returned sub-iterator, and then call dbus_message_iter_close_container(). Container types are for example struct, variant, and array. For variants, the contained_signature should be the type of the single value inside the variant. For structs and dict entries, contained_signature should be NULL; it will be set to whatever types you write into the struct. For arrays, contained_signature should be the type of the array elements.
        */
        
        guard Bool(dbus_message_iter_open_container(&self, Int32(type.integerValue), signature?.rawValue, &subIterator))
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
