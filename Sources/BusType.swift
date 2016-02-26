//
//  BusType.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/26/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//


/// Well-known bus types.
public enum DBusBusType: CInt {
    
    /// The login session bus.
    case Session
    
    /// The systemwide bus.
    case System
    
    /// The bus that started us, if any.
    case Starter
}