//
//  DispatchStatus.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/27/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

/// Indicates the status of incoming data on a `DBusConnection`.
///
/// This determines whether `DBusConnection.dispatch()` needs to be called.
public enum DBusDispatchStatus: UInt32 {
    
    /// There is more data to potentially convert to messages.
    case DataRemains
    
    /// All currently available data has been processed.
    case Complete
    
    /// More memory is needed to continue.
    case NeedMemory
}