//
//  Connection.swift
//  DBus
//
//  `dbus_connection_*` — opening, closing and the blocking send.
//

import Foundation
import CDBusABI
import DBus

// MARK: - Storage

/// The object a `DBusConnection *` points at.
internal final class ConnectionBox: Box {

    let connection: DBusConnection

    /// Cached so `dbus_bus_get_unique_name` can return a borrowed pointer.
    private var uniqueName: UnsafeMutablePointer<CChar>?

    /// Whether this connection came from the shared `dbus_bus_get` cache.
    let isShared: Bool

    init(_ connection: DBusConnection, isShared: Bool) {

        self.connection = connection
        self.isShared = isShared
    }

    deinit {

        free(uniqueName)

        // The read loop holds the socket open until the actor is told to stop.
        let connection = self.connection
        Task { await connection.close() }
    }

    /// A borrowed C string for the unique name, valid while the connection is.
    func borrowedUniqueName(_ value: String?) -> UnsafePointer<CChar>? {

        guard let value = value
            else { return nil }

        if let existing = uniqueName, strcmp(existing, value) == 0 {
            return UnsafePointer(existing)
        }

        free(uniqueName)
        uniqueName = strdup(value)

        return UnsafePointer(uniqueName)
    }
}

internal func connection(_ pointer: OpaquePointer?) -> ConnectionBox? {

    guard let pointer = pointer
        else { return nil }

    return Box.unretained(pointer)
}

/// The shared connections `dbus_bus_get` hands out, one per bus type.
///
/// The reference caches these and returns the same object to every caller, so
/// a program that calls `dbus_bus_get(DBUS_BUS_SESSION, ...)` twice gets one
/// connection with two references, not two connections.
private final class SharedConnections: @unchecked Sendable {

    static let shared = SharedConnections()

    private let lock = NSLock()
    private var connections: [Int32: ConnectionBox] = [:]

    func connection(for busType: Int32, _ make: () throws -> ConnectionBox) rethrows -> ConnectionBox {

        lock.lock()
        defer { lock.unlock() }

        if let existing = connections[busType] {
            return existing
        }

        let box = try make()
        connections[busType] = box
        return box
    }
}

// MARK: - Opening

private func busType(_ raw: Int32) -> DBus.DBusBusType? {

    switch raw {
    case Int32(CDBusABI.DBUS_BUS_SESSION.rawValue): return .session
    case Int32(CDBusABI.DBUS_BUS_SYSTEM.rawValue): return .system
    // The reference falls back to the session bus when DBUS_STARTER_ADDRESS
    // is unset, which is the case for anything not activated by the bus.
    case Int32(CDBusABI.DBUS_BUS_STARTER.rawValue): return .session
    default: return nil
    }
}

/// `DBusConnection *dbus_bus_get(DBusBusType type, DBusError *error)`
///
/// Returns a shared connection, already registered with the bus. The caller
/// owns a reference to it and releases it with `dbus_connection_unref`.
@_cdecl("dbus_bus_get")
public func abi_dbus_bus_get(_ type: Int32,
                         _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> OpaquePointer? {

    guard let busType = busType(type) else {
        setError(error, name: DBus.DBusError.Name.failed.rawValue, message: "Unknown bus type")
        return nil
    }

    do {
        let box = try SharedConnections.shared.connection(for: type) {

            // `connect` performs the Hello handshake, so the connection this
            // returns is already registered with the bus.
            let connection = try blocking { try await DBusConnection.connect(to: busType) }
            return ConnectionBox(connection, isShared: true)
        }

        // The cache holds one reference; the caller gets its own.
        return box.retainedPointer()
    }
    catch let thrown {
        setError(error, from: thrown)
        return nil
    }
}

/// `DBusConnection *dbus_bus_get_private(DBusBusType type, DBusError *error)`
@_cdecl("dbus_bus_get_private")
public func abi_dbus_bus_get_private(_ type: Int32,
                                 _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> OpaquePointer? {

    guard let busType = busType(type) else {
        setError(error, name: DBus.DBusError.Name.failed.rawValue, message: "Unknown bus type")
        return nil
    }

    do {
        let connection = try blocking { try await DBusConnection.connect(to: busType) }
        return ConnectionBox(connection, isShared: false).retainedPointer()
    }
    catch let thrown {
        setError(error, from: thrown)
        return nil
    }
}

/// `DBusConnection *dbus_connection_open(const char *address, DBusError *error)`
///
/// The connection is authenticated but not registered; call
/// `dbus_bus_register` before using it with a message bus.
@_cdecl("dbus_connection_open")
public func abi_dbus_connection_open(_ address: UnsafePointer<CChar>?,
                                 _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> OpaquePointer? {

    return abi_dbus_connection_open_private(address, error)
}

/// `DBusConnection *dbus_connection_open_private(const char *address, DBusError *error)`
@_cdecl("dbus_connection_open_private")
public func abi_dbus_connection_open_private(_ address: UnsafePointer<CChar>?,
                                         _ error: UnsafeMutablePointer<CDBusABI.DBusError>?) -> OpaquePointer? {

    guard let addressString = string(address) else {
        setError(error, name: DBus.DBusError.Name.badAddress.rawValue, message: "No address")
        return nil
    }

    do {
        let connection = try blocking { try await DBusConnection.connect(to: addressString) }
        return ConnectionBox(connection, isShared: false).retainedPointer()
    }
    catch let thrown {
        setError(error, from: thrown)
        return nil
    }
}

// MARK: - Reference counting

/// `DBusConnection *dbus_connection_ref(DBusConnection *connection)`
@_cdecl("dbus_connection_ref")
public func abi_dbus_connection_ref(_ connection: OpaquePointer?) -> OpaquePointer? {

    guard let connection = connection
        else { return nil }

    Box.retain(connection)
    return connection
}

/// `void dbus_connection_unref(DBusConnection *connection)`
@_cdecl("dbus_connection_unref")
public func abi_dbus_connection_unref(_ connection: OpaquePointer?) {

    guard let connection = connection
        else { return }

    Box.release(connection)
}

/// `void dbus_connection_close(DBusConnection *connection)`
@_cdecl("dbus_connection_close")
public func abi_dbus_connection_close(_ pointer: OpaquePointer?) {

    guard let box = connection(pointer)
        else { return }

    let connection = box.connection
    _ = try? blocking { await connection.close() }
}

// MARK: - State

/// `dbus_bool_t dbus_connection_get_is_connected(DBusConnection *connection)`
@_cdecl("dbus_connection_get_is_connected")
public func abi_dbus_connection_get_is_connected(_ pointer: OpaquePointer?) -> dbus_bool_t {

    guard let box = connection(pointer)
        else { return false.cBool }

    let connection = box.connection
    let isConnected = (try? blocking { await connection.isConnected }) ?? false

    return isConnected.cBool
}

/// `dbus_bool_t dbus_connection_get_is_authenticated(DBusConnection *connection)`
///
/// A connection this implementation hands back has already completed the SASL
/// handshake, so this reports the same thing as `get_is_connected`.
@_cdecl("dbus_connection_get_is_authenticated")
public func abi_dbus_connection_get_is_authenticated(_ pointer: OpaquePointer?) -> dbus_bool_t {

    return abi_dbus_connection_get_is_connected(pointer)
}

/// `char *dbus_connection_get_server_id(DBusConnection *connection)`
///
/// The caller releases the result with `dbus_free`.
@_cdecl("dbus_connection_get_server_id")
public func abi_dbus_connection_get_server_id(_ pointer: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {

    guard let box = connection(pointer)
        else { return nil }

    let connection = box.connection
    let guid = try? blocking { await connection.serverGUID }

    return (guid ?? nil)?.copiedCString()
}

// MARK: - Sending

/// `dbus_bool_t dbus_connection_send(DBusConnection *, DBusMessage *, dbus_uint32_t *serial)`
///
/// Sends without waiting for a reply.
@_cdecl("dbus_connection_send")
public func abi_dbus_connection_send(_ pointer: OpaquePointer?,
                                 _ message: OpaquePointer?,
                                 _ serial: UnsafeMutablePointer<dbus_uint32_t>?) -> dbus_bool_t {

    guard let box = connection(pointer), let messageBox = DBusABI.message(message)
        else { return false.cBool }

    let connection = box.connection
    let value = messageBox.message

    do {
        let assigned = try blocking { try await connection.send(oneWay: value) }
        messageBox.message.serial = assigned
        serial?.pointee = assigned
        return true.cBool
    }
    catch {
        return false.cBool
    }
}

/// `DBusMessage *dbus_connection_send_with_reply_and_block(DBusConnection *, DBusMessage *, int, DBusError *)`
///
/// The caller owns the returned message and releases it with
/// `dbus_message_unref`.
@_cdecl("dbus_connection_send_with_reply_and_block")
public func abi_dbus_connection_send_with_reply_and_block(
    _ pointer: OpaquePointer?,
    _ message: OpaquePointer?,
    _ timeoutMilliseconds: Int32,
    _ error: UnsafeMutablePointer<CDBusABI.DBusError>?
) -> OpaquePointer? {

    guard let box = connection(pointer), let messageBox = DBusABI.message(message) else {
        setError(error, name: DBus.DBusError.Name.invalidArguments.rawValue, message: "No message")
        return nil
    }

    let connection = box.connection
    let value = messageBox.message

    let timeout: Duration?

    switch timeoutMilliseconds {
    case Int32(DBUS_TIMEOUT_USE_DEFAULT):
        timeout = DBusConnection.defaultTimeout
    case Int32(DBUS_TIMEOUT_INFINITE):
        timeout = nil
    case ..<0:
        timeout = DBusConnection.defaultTimeout
    default:
        timeout = .milliseconds(Int(timeoutMilliseconds))
    }

    do {
        let reply = try blocking { try await connection.send(value, timeout: timeout) }
        return MessageBox(reply).retainedPointer()
    }
    catch let thrown {
        setError(error, from: thrown)
        return nil
    }
}

/// `void dbus_connection_flush(DBusConnection *connection)`
///
/// A no-op: every send here completes before it returns, so there is never
/// anything queued to flush.
@_cdecl("dbus_connection_flush")
public func abi_dbus_connection_flush(_ connection: OpaquePointer?) {

    // Deliberately empty.
}
