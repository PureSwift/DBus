//
//  Connection.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// DBus Connection
public final class Connection {
    
    // MARK: - Internal Properties
    
    internal let internalPointer: COpaquePointer
    
    // MARK: - Initialization
    
    public init(address: String) throws {
        
        let errorPointer = DBusError.InternalPointer()
        
        self.internalPointer = dbus_connection_open(address, errorPointer)
        
        guard self.internalPointer != nil
            else { throw DBusError(internalPointer: errorPointer) }
    }
    
    // MARK: - Methods
    
    
}