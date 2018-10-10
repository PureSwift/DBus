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
    case methodCall = 1
    
    /// Message type of a method return message.
    case methodReturn
    
    /// Message type of an error reply message. 
    case error
    
    /// Message type of a signal message.
    case signal
}
