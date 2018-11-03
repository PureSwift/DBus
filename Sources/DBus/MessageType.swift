//
//  MessageType.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

/// The DBus Message type.
public enum DBusMessageType: CInt {
    
    /// Message type of a method call message.
    ///
    /// Method call messages ask to invoke a method on an object.
    case methodCall = 1
    
    /// Message type of a method return message.
    ///
    /// Method return messages return the results of invoking a method.
    case methodReturn
    
    /// Message type of an error reply message.
    ///
    /// Error messages return an exception caused by invoking a method.
    case error
    
    /// Message type of a signal message.
    ///
    /// Signal messages are notifications that a given signal has been emitted (that an event has occurred).
    /// You could also think of these as "event" messages.
    case signal
}
