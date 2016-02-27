//
//  HandlerResult.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/27/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

/// Results that a message handler can return.
public enum DBusHandlerResult: UInt32 {
    
    /// Message has had its effect - no need to run more handlers.
    case Handled
    
    /// Message has not had any effect - see if other handlers want it.
    case NotYetHandled
    
    /// Please try again later with more memory.
    case NeedMemory
}