//
//  Bus.swift
//  DBus
//
//  `dbus_bus_*` — the operations the message bus itself provides.
//

import Foundation
import CDBusABI
import DBus

/// `dbus_bool_t dbus_bus_register(DBusConnection *connection, DBusError *error)`
///
/// Reports whether the connection is registered with the bus. Connecting
/// performs the `Hello` handshake here, so a connection that exists at all is
/// already registered and this always succeeds for one — but callers written
/// against the reference call it, so it is provided rather than omitted.
@_cdecl("dbus_bus_register")
public func abi_dbus_bus_register(_ pointer: OpaquePointer?,
                              _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> dbus_bool_t {

    guard let box = connection(pointer) else {
        setError(error, name: DBus.DBusError.Name.invalidArguments.rawValue, message: "No connection")
        return false.cBool
    }

    let connection = box.connection

    do {
        guard try blocking({ await connection.uniqueName }) != nil else {
            setError(error,
                     name: DBus.DBusError.Name.failed.rawValue,
                     message: "The connection has no unique name")
            return false.cBool
        }

        return true.cBool
    }
    catch let thrown {
        setError(error, from: thrown)
        return false.cBool
    }
}

/// `const char *dbus_bus_get_unique_name(DBusConnection *connection)`
///
/// Borrowed, valid while the connection is.
@_cdecl("dbus_bus_get_unique_name")
public func abi_dbus_bus_get_unique_name(_ pointer: OpaquePointer?) -> UnsafePointer<CChar>? {

    guard let box = connection(pointer)
        else { return nil }

    let connection = box.connection
    let name = try? blocking { await connection.uniqueName }

    return box.borrowedUniqueName((name ?? nil)?.rawValue)
}

/// `char *dbus_bus_get_id(DBusConnection *connection, DBusError *error)`
///
/// The caller releases the result with `dbus_free`.
@_cdecl("dbus_bus_get_id")
public func abi_dbus_bus_get_id(_ pointer: OpaquePointer?,
                            _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> UnsafeMutablePointer<CChar>? {

    guard let box = connection(pointer) else {
        setError(error, name: DBus.DBusError.Name.invalidArguments.rawValue, message: "No connection")
        return nil
    }

    let connection = box.connection

    do {
        return try blocking { try await connection.getBusID() }.copiedCString()
    }
    catch let thrown {
        setError(error, from: thrown)
        return nil
    }
}

/// `int dbus_bus_request_name(DBusConnection *, const char *, unsigned int, DBusError *)`
///
/// Returns one of the `DBUS_REQUEST_NAME_REPLY_*` values, or -1 on failure.
@_cdecl("dbus_bus_request_name")
public func abi_dbus_bus_request_name(_ pointer: OpaquePointer?,
                                  _ name: UnsafePointer<CChar>?,
                                  _ flags: UInt32,
                                  _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> Int32 {

    guard let box = connection(pointer),
          let nameString = string(name),
          let busName = DBusBusName(rawValue: nameString) else {

        setError(error,
                 name: DBus.DBusError.Name.invalidArguments.rawValue,
                 message: "Invalid bus name")
        return -1
    }

    let connection = box.connection
    let requestFlags = DBusConnection.RequestNameFlags(rawValue: flags)

    do {
        let result = try blocking { try await connection.requestName(busName, flags: requestFlags) }
        return Int32(result.rawValue)
    }
    catch let thrown {
        setError(error, from: thrown)
        return -1
    }
}

/// `int dbus_bus_release_name(DBusConnection *, const char *, DBusError *)`
@_cdecl("dbus_bus_release_name")
public func abi_dbus_bus_release_name(_ pointer: OpaquePointer?,
                                  _ name: UnsafePointer<CChar>?,
                                  _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> Int32 {

    guard let box = connection(pointer),
          let nameString = string(name),
          let busName = DBusBusName(rawValue: nameString) else {

        setError(error,
                 name: DBus.DBusError.Name.invalidArguments.rawValue,
                 message: "Invalid bus name")
        return -1
    }

    let connection = box.connection

    do {
        let result = try blocking { try await connection.releaseName(busName) }
        return Int32(result.rawValue)
    }
    catch let thrown {
        setError(error, from: thrown)
        return -1
    }
}

/// `dbus_bool_t dbus_bus_name_has_owner(DBusConnection *, const char *, DBusError *)`
@_cdecl("dbus_bus_name_has_owner")
public func abi_dbus_bus_name_has_owner(_ pointer: OpaquePointer?,
                                    _ name: UnsafePointer<CChar>?,
                                    _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> dbus_bool_t {

    guard let box = connection(pointer),
          let nameString = string(name),
          let busName = DBusBusName(rawValue: nameString) else {

        setError(error,
                 name: DBus.DBusError.Name.invalidArguments.rawValue,
                 message: "Invalid bus name")
        return false.cBool
    }

    let connection = box.connection

    do {
        return try blocking { try await connection.nameHasOwner(busName) }.cBool
    }
    catch let thrown {
        setError(error, from: thrown)
        return false.cBool
    }
}

/// `dbus_bool_t dbus_bus_start_service_by_name(DBusConnection *, const char *, dbus_uint32_t, dbus_uint32_t *, DBusError *)`
@_cdecl("dbus_bus_start_service_by_name")
public func abi_dbus_bus_start_service_by_name(_ pointer: OpaquePointer?,
                                           _ name: UnsafePointer<CChar>?,
                                           _ flags: dbus_uint32_t,
                                           _ result: UnsafeMutablePointer<dbus_uint32_t>?,
                                           _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> dbus_bool_t {

    guard let box = connection(pointer),
          let nameString = string(name),
          let busName = DBusBusName(rawValue: nameString) else {

        setError(error,
                 name: DBus.DBusError.Name.invalidArguments.rawValue,
                 message: "Invalid bus name")
        return false.cBool
    }

    let connection = box.connection

    do {
        let value = try blocking { try await connection.startServiceByName(busName, flags: flags) }
        result?.pointee = value
        return true.cBool
    }
    catch let thrown {
        setError(error, from: thrown)
        return false.cBool
    }
}

/// `unsigned long dbus_bus_get_unix_user(DBusConnection *, const char *, DBusError *)`
@_cdecl("dbus_bus_get_unix_user")
public func abi_dbus_bus_get_unix_user(_ pointer: OpaquePointer?,
                                   _ name: UnsafePointer<CChar>?,
                                   _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> UInt {

    guard let box = connection(pointer),
          let nameString = string(name),
          let busName = DBusBusName(rawValue: nameString) else {

        setError(error,
                 name: DBus.DBusError.Name.invalidArguments.rawValue,
                 message: "Invalid bus name")
        return UInt.max
    }

    let connection = box.connection

    do {
        return UInt(try blocking { try await connection.getConnectionUnixUser(busName) })
    }
    catch let thrown {
        setError(error, from: thrown)
        return UInt.max
    }
}

// MARK: - Match rules

/// Call `AddMatch` or `RemoveMatch` on the bus.
private func match(_ pointer: OpaquePointer?,
                   _ rule: UnsafePointer<CChar>?,
                   _ error: UnsafeMutablePointer<CDBusABI.DBusError>?,
                   method: String) {

    guard let box = connection(pointer), let ruleString = string(rule) else {
        setError(error, name: DBus.DBusError.Name.invalidArguments.rawValue, message: "No match rule")
        return
    }

    let connection = box.connection

    let call = DBus.DBusMessage.MethodCall(
        destination: DBusBusName(rawValue: "org.freedesktop.DBus")!,
        path: DBusObjectPath(rawValue: "/org/freedesktop/DBus")!,
        interface: DBusInterface(rawValue: "org.freedesktop.DBus")!,
        method: DBusMember(rawValue: method)!
    )

    let request = DBus.DBusMessage(methodCall: call, arguments: [.string(ruleString)])

    do {
        _ = try blocking { try await connection.send(request) }
    }
    catch let thrown {
        setError(error, from: thrown)
    }
}

/// `void dbus_bus_add_match(DBusConnection *connection, const char *rule, DBusError *error)`
///
/// The rule is installed on the bus. Delivered signals are readable through
/// this package's Swift API; the C ABI has no message queue to pop them from,
/// because it does not expose the dispatch loop.
@_cdecl("dbus_bus_add_match")
public func abi_dbus_bus_add_match(_ connection: OpaquePointer?,
                               _ rule: UnsafePointer<CChar>?,
                               _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) {

    match(connection, rule, error, method: "AddMatch")
}

/// `void dbus_bus_remove_match(DBusConnection *connection, const char *rule, DBusError *error)`
@_cdecl("dbus_bus_remove_match")
public func abi_dbus_bus_remove_match(_ connection: OpaquePointer?,
                                  _ rule: UnsafePointer<CChar>?,
                                  _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) {

    match(connection, rule, error, method: "RemoveMatch")
}
