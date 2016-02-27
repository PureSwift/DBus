//
//  Connection.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// Type representing a connection to a remote application and associated incoming/outgoing message queues.
public final class DBusConnection {
    
    // MARK: - Internal Properties
    
    internal let internalPointer: COpaquePointer
    
    // MARK: - Initialization
    
    deinit {
        
        dbus_connection_unref(internalPointer)
    }
    
    /// Gets a connection to a remote address.
    ///
    /// - Parameter address: The address to connect to.
    /// - Parameter shared: Whether the connection will be shared by subsequent callers,
    /// or a new dedicated connection should be created.
    public init(address: String, shared: Bool = true) throws {
        
        let error = DBusErrorInternal()
        
        if shared {
            
            self.internalPointer = dbus_connection_open(address, error.internalPointer)
            
        } else {
            
            self.internalPointer = dbus_connection_open_private(address, error.internalPointer)
        }
        
        // check for error
        guard self.internalPointer != nil
            else { throw error.toError()! }
    }
    
    // MARK: - Methods
    
    /// Closes a private connection, so no further data can be sent or received.
    ///
    //// This disconnects the transport (such as a socket) underlying the connection.
    public func close() {
        
        dbus_connection_close(internalPointer)
    }
    
    /// Tests whether a certain type can be send via the connection.
    public func canSend(type: DBusType) -> Bool {
        
        return dbus_connection_can_send_type(internalPointer, type.integerValue).boolValue
    }
    
    /// Adds a message to the outgoing message queue. 
    ///
    /// Does not block to write the message to the network; that happens asynchronously. 
    /// To force the message to be written, call `flush()`.
    ///
    /// - Parameter message: The message to write.
    ///
    /// - Parameter serial: Return location for message serial, or `nil` if you don't care.
    public func send(message: DBusMessage, serial: dbus_uint32_t? = nil) {
        
        let serialPointer: UnsafeMutablePointer<dbus_uint32_t>
        
        if let serial = serial {
            
            serialPointer = UnsafeMutablePointer<dbus_uint32_t>.alloc(1)
            
            serialPointer.memory = serial
            
            defer { serialPointer.dealloc(1) }
            
        } else {
            
            // nil pointer
            serialPointer = UnsafeMutablePointer<dbus_uint32_t>()
        }
        
        guard dbus_connection_send(internalPointer, message.internalPointer, serialPointer)
            else { fatalError("Out of memory! Could not add message to queue. (\(message))") }
    }
    
    /// Queues a message to send, as with `DBusConnection.send()`, 
    /// but also returns reply to the message.
    public func sendWithReply(message: DBusMessage, timeout: Int = Int(DBUS_TIMEOUT_USE_DEFAULT)) -> DBusPendingCall? {
        
        let pendingCallDoublePointer = UnsafeMutablePointer<COpaquePointer>.alloc(1)
        
        // free double pointer
        defer { pendingCallDoublePointer.dealloc(1) }
        
        guard dbus_connection_send_with_reply(internalPointer, message.internalPointer, pendingCallDoublePointer, CInt(timeout))
            else { fatalError("Out of memory! Could not add message to queue. (\(message))") }
        
        // if the connection is disconnected or you try to send Unix file descriptors on a connection that does not support them,
        // the DBusPendingCall will be set to NULL
        guard pendingCallDoublePointer != nil else { return nil }
        
        let pendingCallInternalPointer = pendingCallDoublePointer.memory
        
        return DBusPendingCall(pendingCallInternalPointer)
    }
    
    /// Blocks until the outgoing message queue is empty.
    public func flush() {
        
        dbus_connection_flush(internalPointer)
    }
    
    // MARK: - Properties
    
    /// Whether the connection is currently open.
    public var connected: Bool {
        
        return dbus_connection_get_is_connected(internalPointer).boolValue
    }
    
    /// Whether the connection was authenticated.
    public var authenticated: Bool {
        
        return dbus_connection_get_is_authenticated(internalPointer).boolValue
    }
    
    /// Whether the connection is not authenticated as a specific user.
    public var anonymous: Bool {
        
        return dbus_connection_get_is_anonymous(internalPointer).boolValue
    }
    
    /// Gets the ID of the server address we are authenticated to, if this connection is on the client side, 
    /// or `nil` if the connection is on the server side.
    public var serverIdentifier: String? {
        
        let cString = dbus_connection_get_server_id(internalPointer)
        
        guard cString != nil else { return nil }
        
        let stringValue = String.fromCString(cString)!
        
        return stringValue
    }
    
    
}

