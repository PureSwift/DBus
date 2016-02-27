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
    
    // MARK: - Properties
    
    public let shared: Bool
    
    // MARK: - Internal Properties
    
    internal let internalPointer: COpaquePointer
    
    // MARK: - Initialization
    
    deinit {
        
        // Connections created with dbus_connection_open_private() or dbus_bus_get_private() are not kept track of 
        /// or referenced by libdbus. The creator of these connections is responsible for calling dbus_connection_close() 
        /// prior to releasing the last reference, if the connection is not already disconnected.
        if shared == false {
            
            self.close()
        }
        
        dbus_connection_unref(internalPointer)
    }
    
    /// Gets a connection to a remote address.
    ///
    /// - Parameter address: The address to connect to.
    /// - Parameter shared: Whether the connection will be shared by subsequent callers,
    /// or a new dedicated connection should be created.
    public init(address: String, shared: Bool = true) throws {
        
        self.shared = shared
        
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
    
    /// Connects to a bus daemon and registers the client with it.
    ///
    /// - Parameter busType: Bus type.
    /// - Parameter shared: Whether the connection will be shared by subsequent callers,
    /// or a new dedicated connection should be created.
    public init(busType: DBusBusType, shared: Bool = true) throws {
        
        self.shared = shared
        
        let error = DBusErrorInternal()
        
        let internalBusType = CDBus.DBusBusType(rawValue: busType.rawValue)
        
        if shared {
            
            self.internalPointer = dbus_bus_get(internalBusType, error.internalPointer)
            
        } else {
            
            self.internalPointer = dbus_bus_get_private(internalBusType, error.internalPointer)
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
    
    /// Processes any incoming data.
    ///
    /// If there's incoming raw data that has not yet been parsed, it is parsed,
    /// which may or may not result in adding messages to the incoming queue.
    public func dispatch() -> DBusDispatchStatus {
        
        let rawValue = dbus_connection_dispatch(internalPointer).rawValue
        
        return DBusDispatchStatus(rawValue: rawValue)!
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

