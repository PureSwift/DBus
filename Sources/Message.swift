//
//  Message.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// Message to be sent or received over a `DBusConnection`.
///
/// A `DBusMessage` is the most basic unit of communication over a `DBusConnection`.
/// A `DBusConnection` represents a stream of messages received from a remote application,
/// and a stream of messages sent to a remote application.
///
/// A message has header fields such as the sender, destination, method or signal name, and so forth.
///
public final class DBusMessage {
    
    // MARK: - Internal Properties
    
    internal let internalPointer: COpaquePointer
    
    // MARK: - Initialization
    
    deinit {
        
        dbus_message_unref(internalPointer)
    }
    
    internal init(_ internalPointer: COpaquePointer) {
        
        assert(internalPointer != nil, "Cannot create a DBus message from a nil pointer")
        
        self.internalPointer = internalPointer
    }
    
    /// Constructs a new message of the given message type.
    public init(type: DBusMessageType) {
        
        self.internalPointer = dbus_message_new(type.rawValue)
        
        assert(self.internalPointer != nil, "Out of memory! Cound not create DBus message")
    }
    
    /// Creates a new message that is an error reply to another message.
    ///
    /// Error replies are most common in response to method calls, but can be returned in reply to any message.
    /// The error name must be a valid error name according to the syntax given in the D-Bus specification. 
    /// If you don't want to make up an error name just use `DBUS_ERROR_FAILED`.
    ///
    /// - Parameter error: A tuple consisting of the message to reply to, the error name, and the error message.
    public init(error: (replyTo: DBusMessage, name: String, message: String?)) {
        
        assert(error.replyTo.internalPointer != nil, "Invalid replyTo message. Internal pointer is nil")
        
        let nameCString = convertString(error.name)
        
        defer { cleanConvertedString(nameCString) }
        
        let messageCString = convertString(error.message)
        
        defer { cleanConvertedString(messageCString) }
        
        self.internalPointer = dbus_message_new_error(error.replyTo.internalPointer, nameCString.0, messageCString.0)
        
        assert(self.internalPointer != nil, "Out of memory! Cound not create DBus message")
    }
    
    /// Constructs a new message to invoke a method on a remote object.
    ///
    /// - Note: Destination, path, interface, and method name can't contain any invalid characters (see the D-Bus specification).
    public init(methodCall: (destination: String?, path: String, interface: String?, method: String)) {
        
        let destination = convertString(methodCall.destination)
        
        defer { cleanConvertedString(destination) }
        
        let path = convertString(methodCall.path)
        
        defer { cleanConvertedString(path) }
        
        let interface = convertString(methodCall.interface)
        
        defer { cleanConvertedString(interface) }
        
        let method = convertString(methodCall.method)
        
        defer { cleanConvertedString(method) }
        
        // Returns NULL if memory can't be allocated for the message.
        self.internalPointer = dbus_message_new_method_call(destination.0, path.0, interface.0, method.0)
        
        assert(self.internalPointer != nil, "Out of memory! Cound not create DBus message")
    }
    
    /// Constructs a message that is a reply to a method call.
    public init(methodReturn methodCall: DBusMessage) {
        
        assert(methodCall.internalPointer != nil, "Invalid method call message. Internal pointer is nil")
        
        self.internalPointer = dbus_message_new_method_return(methodCall.internalPointer)
        
        assert(self.internalPointer != nil, "Out of memory! Cound not create DBus message")
    }
    
    /// Constructs a new message representing a signal emission.
    ///
    /// A signal is identified by its originating object path, interface, and the name of the signal.
    ///
    /// - Note: Path, interface, and signal name must all be valid (the D-Bus specification defines the syntax of these fields).
    public init(signal: (path: String, interface: String, name: String)) {
        
        let path = convertString(signal.path)
        
        defer { cleanConvertedString(path) }
        
        let interface = convertString(signal.interface)
        
        defer { cleanConvertedString(interface) }
        
        let name = convertString(signal.name)
        
        defer { cleanConvertedString(name) }
        
        self.internalPointer = dbus_message_new_signal(path.0, interface.0, name.0)
        
        assert(self.internalPointer != nil, "Out of memory! Cound not create DBus message")
    }
    
    // MARK: - Methods
    
    
    
    // MARK: - Properties
    
    /// The message type.
    public var type: DBusMessageType {
        
        let rawValue = dbus_message_get_type(internalPointer)
        
        guard let type = DBusMessageType(rawValue: rawValue)
            else { fatalError("Invalid DBus Message type: \(rawValue)") }
        
        return type
    }
    
    public var arguments: [DBusMessageArgument] {
        
        get {
            
            var iterator = DBusMessageIter()
            
            guard dbus_message_iter_init(internalPointer, &iterator)
                else { return [] }
            
            //while let currentType = dbus_message_iter_get_arg_type(&iterator) where current_type != DBUS_TYPE_INVALID { }
            
            fatalError("Not implemented")
        }
        
        set { append(newValue) }
    }
    
    /// Checks whether a message contains Unix file descriptors.
    public var containsFileDescriptors: Bool {
        
        return dbus_message_contains_unix_fds(internalPointer).boolValue
    }
    
    /// The serial of a message or `0` if none has been specified.
    ///
    /// The message's serial number is provided by the application sending the message and
    /// is used to identify replies to this message.
    ///
    /// - Note: All messages received on a connection will have a serial provided by the remote application.
    ///
    /// For messages you're sending, `DBusConnection.send()` will assign a serial and return it to you.
    public var serial: dbus_uint32_t {
        
        get { return dbus_message_get_serial(internalPointer) }
        
        set { dbus_message_set_serial(internalPointer, newValue) }
    }
    
    /// The reply serial of a message (the serial of the message this is a reply to).
    public var replySerial: dbus_uint32_t {
        
        get { return dbus_message_get_reply_serial(internalPointer) }
        
        set { guard dbus_message_set_reply_serial(internalPointer, newValue) else { fatalError("Out of memory!") } }
    }
    
    /// Flag indicating that the caller of the method is prepared to wait for interactive authorization to take place 
    /// (for instance via Polkit) before the actual method is processed.
    ///
    /// The flag is `false` by default;
    /// that is, by default the other end is expected to make any authorization decisions non-interactively and promptly.
    public var allowInteractiveAuthorization: Bool {
        
        get { return dbus_message_get_allow_interactive_authorization(internalPointer).boolValue }
        
        set { dbus_message_set_allow_interactive_authorization(internalPointer, dbus_bool_t(newValue)) }
    }
    
    /// Sets a flag indicating that an owner for the destination name will be automatically started before the message is delivered.
    ///
    /// When this flag is set, the message is held until a name owner finishes starting up, 
    /// or fails to start up. In case of failure, the reply will be an error.
    ///
    /// The flag is set to `true` by default, i.e. auto starting is the default.
    public var autoStart: Bool {
        
        get { return dbus_message_get_auto_start(internalPointer).boolValue }
        
        set { dbus_message_set_auto_start(internalPointer, dbus_bool_t(newValue)) }
    }
    
    /// Flag indicating that the message does not want a reply; 
    /// if this flag is set, the other end of the connection may (but is not required to) 
    /// optimize by not sending method return or error replies.
    ///
    /// The flag is `false` by default, that is by default the other end is required to reply.
    ///
    /// - Note: If this flag is set, there is no way to know whether the message successfully arrived at the remote end. 
    /// Normally you know a message was received when you receive the reply to it.
    public var noReply: Bool {
        
        get { return dbus_message_get_no_reply(internalPointer).boolValue }
        
        set { dbus_message_set_no_reply(internalPointer, dbus_bool_t(newValue)) }
    }
    
    /// The destination is the name of another connection on the bus 
    /// and may be either the unique name assigned by the bus to each connection, or a well-known name specified in advance.
    ///
    /// The destination name must contain only valid characters as defined in the D-Bus specification.
    public var destination: String? {
        
        get { return valueForFunction(dbus_message_get_destination) }
        
        set { setValueForFunction(dbus_message_set_destination, newValue) }
    }
    
    /// The name of the error (for `Error` message type).
    ///
    /// The name is fully-qualified (namespaced). 
    /// The error name must contain only valid characters as defined in the D-Bus specification.
    public var errorName: String? {
        
        get { return valueForFunction(dbus_message_get_error_name) }
        
        set { setValueForFunction(dbus_message_set_error_name, newValue) }
    }
    
    /// The interface this message is being sent to (for method call type) 
    /// or the interface a signal is being emitted from (for signal call type).
    ///
    /// The interface name must contain only valid characters as defined in the D-Bus specification.
    public var interface: String? {
        
        get { return valueForFunction(dbus_message_get_interface) }
        
        set { setValueForFunction(dbus_message_set_interface, newValue) }
    }
    
    /// The object path this message is being sent to (for method call type)
    /// or the one a signal is being emitted from (for signal call type).
    ///
    /// The path must contain only valid characters as defined in the D-Bus specification.
    public var path: String? {
        
        get { return valueForFunction(dbus_message_get_path) }
        
        set { setValueForFunction(dbus_message_set_path, newValue) }
    }
    
    /// The interface member being invoked (for method call type) or emitted (for signal type).
    ///
    /// The member name must contain only valid characters as defined in the D-Bus specification.
    public var member: String? {
        
        get { return valueForFunction(dbus_message_get_member) }
        
        set { setValueForFunction(dbus_message_set_member, newValue) }
    }
    
    /// The message sender.
    ///
    /// The sender must be a valid bus name as defined in the D-Bus specification.
    ///
    /// - Note: Usually you don't want to call this. 
    /// The message bus daemon will call it to set the origin of each message. 
    /// If you aren't implementing a message bus daemon you shouldn't need to set the sender.
    public var sender: String? {
        
        get { return valueForFunction(dbus_message_get_sender) }
        
        set { setValueForFunction(dbus_message_set_sender, newValue) }
    }
    
    // MARK: - Private Methods
    
    private func valueForFunction(function: COpaquePointer -> UnsafePointer<Int8>) -> String? {
        
        return String.fromCString(function(internalPointer))
    }
    
    private func setValueForFunction(function: (COpaquePointer, UnsafePointer<Int8>) -> dbus_bool_t, _ newValue: String?) {
        
        let newString = convertString(newValue)
        
        defer { cleanConvertedString(newString) }
        
        guard function(internalPointer, newString.0)
            else { fatalError("Out of memory! Could not set \"\(newValue ?? "<Nil String>")\" for function \(function)") }
    }
    
    private func append(arguments: [DBusMessageArgument]) {
        
        var iterator = DBusMessageIter()
        
        dbus_message_iter_init_append(internalPointer, &iterator)
        
        for argument in arguments {
            
            switch argument {
                
            case var .Byte(value):
                
                guard dbus_message_iter_append_basic(&iterator, DBusType.Byte.integerValue, &value)
                    else { fatalError("Out of memory! could not append \(argument)") }
                
            case let .Boolean(boolean):
                
                var value = dbus_bool_t(boolean)
                
                guard dbus_message_iter_append_basic(&iterator, DBusType.Boolean.integerValue, &value)
                    else { fatalError("Out of memory! could not append \(argument)") }
                
            case var .Int16(value):
                
                guard dbus_message_iter_append_basic(&iterator, DBusType.Int16.integerValue, &value)
                    else { fatalError("Out of memory! could not append \(argument)") }
                
            case var .UInt16(value):
                
                guard dbus_message_iter_append_basic(&iterator, DBusType.UInt16.integerValue, &value)
                    else { fatalError("Out of memory! could not append \(argument)") }
                
            case var .Int32(value):
                
                guard dbus_message_iter_append_basic(&iterator, DBusType.Int32.integerValue, &value)
                    else { fatalError("Out of memory! could not append \(argument)") }
                
            case var .UInt32(value):
                
                guard dbus_message_iter_append_basic(&iterator, DBusType.UInt32.integerValue, &value)
                    else { fatalError("Out of memory! could not append \(argument)") }
                
            case var .Int64(value):
                
                guard dbus_message_iter_append_basic(&iterator, DBusType.Int64.integerValue, &value)
                    else { fatalError("Out of memory! could not append \(argument)") }
                
            case var .UInt64(value):
                
                guard dbus_message_iter_append_basic(&iterator, DBusType.UInt64.integerValue, &value)
                    else { fatalError("Out of memory! could not append \(argument)") }
                
            case var .Double(value):
                
                guard dbus_message_iter_append_basic(&iterator, DBusType.Double.integerValue, &value)
                    else { fatalError("Out of memory! could not append \(argument)") }
                
            case let .String(value):
                
                var string = convertString(value)
                
                defer { cleanConvertedString(string) }
                
                guard dbus_message_iter_append_basic(&iterator, DBusType.String.integerValue, &string.0)
                    else { fatalError("Out of memory! could not append \(argument)") }
                
            default: fatalError("Not implemented appending: \(argument)")
            }
        }
    }
}

// MARK: - Copying

public extension DBusMessage {
    
    public var copy: DBusMessage {
        
        let copyPointer = dbus_message_copy(internalPointer)
        
        let copyMessage = DBusMessage(copyPointer)
        
        return copyMessage
    }
}

// MARK: - Private

private let DBUS_TYPE_INVALID: CInt = {
    
    let bytes = DBUS_TYPE_INVALID_AS_STRING.utf8.map { $0 as UInt8 }
    
    return CInt(bytes[0] + bytes[1])
}()

