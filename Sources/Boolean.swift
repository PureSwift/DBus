//
//  Boolean.swift
//  DBus
//
//  Created by Alsey Coleman Miller on 2/25/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import CDBus

extension dbus_bool_t: BooleanType {
    
    public var boolValue: Bool {
        
        return self != 0
    }
}
