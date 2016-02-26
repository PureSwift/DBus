//
//  Connection.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// Type representing a connection to a remote application and associated incoming/outgoing message queues.
public final class Connection {
    
    // MARK: - Internal Properties
    
    internal let internalPointer: COpaquePointer
    
    // MARK: - Initialization
    
    deinit {
        
        dbus_connection_unref(internalPointer)
    }
    
    /// Gets a connection to a remote address.
    ///
    /// - Parameter shared: Whether the connection will be shared subsequent callers, 
    /// or a new dedicated connection should be created.
    public init(address: String, shared: Bool = true) throws {
        
        let errorPointer = DBusError.InternalPointer()
        
        if shared {
            
            self.internalPointer = dbus_connection_open(address, errorPointer)
            
        } else {
            
            self.internalPointer = dbus_connection_open_private(address, errorPointer)
        }
        
        // check for error
        guard self.internalPointer != nil
            else { throw DBusError(internalPointer: errorPointer) }
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
    
    // MARK: - Accessors
    
    public var connected: Bool {
        
        return dbus_connection_get_is_connected(internalPointer).boolValue
    }
    
    public var authenticated: Bool {
        
        return dbus_connection_get_is_authenticated(internalPointer).boolValue
    }
    
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

