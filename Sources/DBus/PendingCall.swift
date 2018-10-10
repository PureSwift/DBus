//
//  PendingCall.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/27/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

/// Pending reply to a method call message.
public final class DBusPendingCall {
    
    // MARK: - Properties
    
    /// Notification closure to be called when the reply is received or the pending call times out
    public var notification: (() -> ())?
    
    // MARK: - Internal Properties
    
    internal let internalPointer: OpaquePointer
    
    // MARK: - Private Properties
    
    private var replyMessageCache: DBusMessage?
    
    // MARK: - Initialization
    
    deinit {
        
        dbus_pending_call_unref(internalPointer)
    }
    
    internal init(_ internalPointer: OpaquePointer) {
        
        self.internalPointer = internalPointer
        
        setNotification()
    }
    
    // MARK: - Methods
    
    private func setNotification() {
        
        let objectPointer = Unmanaged<DBusPendingCall>.passRetained(self).toOpaque()
        
        dbus_pending_call_set_notify(internalPointer, { (internalPointer, objectPointer) in
            
            let object = Unmanaged<DBusPendingCall>.fromOpaque(objectPointer!).takeUnretainedValue()
            
            object.notification?()
            
        }, objectPointer, { (objectPointer) in
            
            // free object
            Unmanaged<DBusPendingCall>.fromOpaque(objectPointer!).release()
        })
    }
    
    /// Cancels the pending call, such that any reply or error received will just be ignored.
    public func cancel() {
        
        dbus_pending_call_cancel(internalPointer)
    }
    
    /// Block until the pending call is completed.
    public func block() {
        
        dbus_pending_call_block(internalPointer)
    }
    
    // MARK: - Dynamic Properties
    
    /// Gets the reply, or returns `nil` if none has been received yet.
    public var replyMessage: DBusMessage? {
        
        // return cached message
        guard replyMessageCache == nil else { return replyMessageCache }
        
        // attempt to get reply message
        
        guard let messageInternalPointer = dbus_pending_call_steal_reply(internalPointer)
            else { return nil }
        
        let message = DBusMessage(messageInternalPointer)
        
        self.replyMessageCache = message
        
        return message
    }
    
    /// Checks whether the pending call has received a reply yet, or not.
    public var completed: Bool {
        
        return Bool(dbus_pending_call_get_completed(internalPointer))
    }
}
