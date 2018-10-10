//
//  BusType.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/26/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

/// Well-known D-Bus bus types.
public enum DBusBusType: UInt32 {
    
    /// The login session bus.
    case session
    
    /// The systemwide bus.
    case system
    
    /// The bus that started us, if any.
    case starter
}
