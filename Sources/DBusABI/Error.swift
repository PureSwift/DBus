//
//  Error.swift
//  DBus
//
//  `dbus_error_*` — the C ABI's out-parameter error type.
//

import Foundation
import CDBusABI
import DBus

/// `void dbus_error_init(DBusError *error)`
@_cdecl("dbus_error_init")
public func abi_dbus_error_init(_ error: UnsafeMutablePointer<CDBusABI.DBusError>?) {

    guard let error = error
        else { return }

    error.pointee.name = nil
    error.pointee.message = nil
    error.pointee.padding1 = nil
}

/// `void dbus_error_free(DBusError *error)`
///
/// Returns the error to the unset state, so it may be reused, as in the
/// reference.
@_cdecl("dbus_error_free")
public func abi_dbus_error_free(_ error: UnsafeMutablePointer<CDBusABI.DBusError>?) {

    freeError(error)
}

/// `dbus_bool_t dbus_error_is_set(const DBusError *error)`
@_cdecl("dbus_error_is_set")
public func abi_dbus_error_is_set(_ error: UnsafePointer<CDBusABI.DBusError>?) -> dbus_bool_t {

    guard let error = error
        else { return false.cBool }

    return (error.pointee.name != nil).cBool
}

/// `dbus_bool_t dbus_error_has_name(const DBusError *error, const char *name)`
@_cdecl("dbus_error_has_name")
public func abi_dbus_error_has_name(_ error: UnsafePointer<CDBusABI.DBusError>?,
                                _ name: UnsafePointer<CChar>?) -> dbus_bool_t {

    guard let error = error,
          let actual = error.pointee.name,
          let expected = name
        else { return false.cBool }

    return (strcmp(actual, expected) == 0).cBool
}

/// `void dbus_set_error_const(DBusError *error, const char *name, const char *message)`
@_cdecl("dbus_set_error_const")
public func abi_dbus_set_error_const(_ error: UnsafeMutablePointer<CDBusABI.DBusError>?,
                                 _ name: UnsafePointer<CChar>?,
                                 _ message: UnsafePointer<CChar>?) {

    setError(error,
             name: string(name) ?? DBus.DBusError.Name.failed.rawValue,
             message: string(message) ?? "")
}

/// The Swift half of the variadic `dbus_set_error`, which lives in C.
@_cdecl("_dbus_abi_set_error")
public func abi_set_error_bridge(_ error: UnsafeMutablePointer<CDBusABI.DBusError>?,
                                _ name: UnsafePointer<CChar>?,
                                _ message: UnsafePointer<CChar>?) {

    abi_dbus_set_error_const(error, name, message)
}

/// `void dbus_move_error(DBusError *src, DBusError *dest)`
///
/// Hands ownership to `dest` and clears `src`. A null `dest` discards the
/// error, which is how the reference lets a caller ignore one.
@_cdecl("dbus_move_error")
public func abi_dbus_move_error(_ source: UnsafeMutablePointer<CDBusABI.DBusError>?,
                            _ destination: UnsafeMutablePointer<CDBusABI.DBusError>?) {

    guard let source = source
        else { return }

    guard let destination = destination else {
        freeError(source)
        return
    }

    freeError(destination)

    destination.pointee.name = source.pointee.name
    destination.pointee.message = source.pointee.message
    destination.pointee.padding1 = source.pointee.padding1

    // Cleared without freeing: the strings belong to `destination` now.
    source.pointee.name = nil
    source.pointee.message = nil
    source.pointee.padding1 = nil
}
