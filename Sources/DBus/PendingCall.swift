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
    public var notification: ((DBusPendingCall) -> ())?
    
    // MARK: - Internal Properties
    
    internal let internalPointer: OpaquePointer
    
    // MARK: - Private Properties
    
    private var replyMessageCache: DBusMessage?
    
    // MARK: - Initialization
    
    deinit {
        
        dbus_pending_call_unref(internalPointer)
    }
    
    internal init(_ internalPointer: OpaquePointer) {
        
        assert(internalPointer != nil, "Cannot initialize DBusPendingCall from a nil pointer")
        
        self.internalPointer = internalPointer
        
        /// Set notification function
        
        // will be freed later
        let pointer = UnsafeMutablePointer<DBusPendingCall>.alloc(1)
        
        pointer.memory = self
        
        dbus_pending_call_set_notify(internalPointer, DBusPendingCallPrivateNotifyFunction, UnsafeMutablePointer<Void>(pointer), DBusPendingCallPrivateFreeFunction)
    }
    
    // MARK: - Methods
    
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
        
        let messageInternalPointer = dbus_pending_call_steal_reply(internalPointer)
        
        // no response yet
        guard messageInternalPointer != nil else { return nil }
        
        let message = DBusMessage(messageInternalPointer)
        
        self.replyMessageCache = message
        
        return message
    }
    
    /// Checks whether the pending call has received a reply yet, or not.
    public var completed: Bool {
        
        return dbus_pending_call_get_completed(internalPointer).boolValue
    }
}

// MARK: - Private 

private func DBusPendingCallPrivateNotifyFunction(pendingCall: OpaquePointer, _ userData: UnsafeMutablePointer<Void>) -> Void {
    
    let pointer = UnsafeMutablePointer<DBusPendingCall>(userData)
    
    let pendingCall = pointer.memory
    
    pendingCall.notification?(pendingCall)
}

private func DBusPendingCallPrivateFreeFunction(memory: UnsafeMutablePointer<Void>) -> Void {
    
    let pointer = UnsafeMutablePointer<DBusPendingCall>(memory)
    
    pointer.dealloc(1)
    
    pointer.destroy()
}
