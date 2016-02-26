//
//  Message.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

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
    }
    
    /// Creates a new message that is an error reply to another message.
    ///
    /// Error replies are most common in response to method calls, but can be returned in reply to any message.
    /// The error name must be a valid error name according to the syntax given in the D-Bus specification. 
    /// If you don't want to make up an error name just use `DBUS_ERROR_FAILED`.
    ///
    /// - Parameter error: A tuple consisting of the message to reply to, the error name, and the error message.
    public init(error: (replyTo: DBusMessage, name: String, message: String?)) {
        
        let nameCString = convertString(error.name)
        
        defer { cleanConvertedString(nameCString) }
        
        let messageCString = convertString(error.message)
        
        defer { cleanConvertedString(messageCString) }
        
        self.internalPointer = dbus_message_new_error(error.replyTo.internalPointer, nameCString.0, messageCString.0)
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
    
    // MARK: - Methods
    
    
    
    // MARK: - Accessors
    
    /// The serial of a message or `0` if none has been specified.
    ///
    /// The message's serial number is provided by the application sending the message and
    /// is used to identify replies to this message.
    ///
    /// - Note: All messages received on a connection will have a serial provided by the remote application.
    ///
    /// For messages you're sending, `DBusConnection.send()` will assign a serial and return it to you.
    public var serial: dbus_uint32_t {
        
        return dbus_message_get_serial(internalPointer)
    }
    
    /// The reply serial of a message (the serial of the message this is a reply to).
    public var replySerial: dbus_uint32_t {
        
        get { return dbus_message_get_reply_serial(internalPointer) }
        
        set { dbus_message_set_reply_serial(internalPointer, newValue) }
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
