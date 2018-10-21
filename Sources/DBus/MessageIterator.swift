//
//  MessageIterator.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 10/12/18.
//

import CDBus

public extension DBusMessageIter {
    
    /// Initializes a DBusMessageIter for appending arguments to the end of a message.
    init(message: DBusMessage) {
        
        self.init()
        dbus_message_iter_init_append(message.internalPointer, &self)
    }
        
    mutating func appendContainer(type: DBusType, signature: String? = nil, container: (inout DBusMessageIter) throws -> ()) throws {
        
        var subIterator = DBusMessageIter()
        
        guard Bool(dbus_message_iter_open_container(&self, Int32(type.integerValue), signature, &subIterator))
            else { throw DBusError(name: .failed, message: "") }
        
        defer { dbus_message_iter_close_container(&self, &subIterator) }
        
        try container(&subIterator)
    }
}
