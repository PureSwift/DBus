//
//  TestSupport.swift
//  DBusTests
//

import Testing
@testable import DBus

/// The session bus address, if one is configured for this process.
let sessionBusAddress: String? = ProcessEnvironment.value(for: "DBUS_SESSION_BUS_ADDRESS")

/// Whether the live tests can run.
///
/// Used with `.enabled(if:)` so the suite reports the bus tests as skipped, rather than
/// silently passing, on a machine or container without a bus.
let hasSessionBus: Bool = sessionBusAddress != nil

/// Raised when a helper is used without a bus available.
struct NoSessionBus: Error, CustomStringConvertible {

    var description: String { "DBUS_SESSION_BUS_ADDRESS is not set" }
}

/// Open a connection to the session bus, run `body`, and always close afterwards.
///
/// Swift Testing has no asynchronous teardown hook, and `defer { Task { ... } }` would not
/// finish before the next test began, so connection lifetime is scoped by this helper instead.
@discardableResult
func withConnection<T>(_ body: (DBusConnection) async throws -> T) async throws -> T {

    guard let address = sessionBusAddress
        else { throw NoSessionBus() }

    let connection = try await DBusConnection.connect(to: address)

    do {
        let result = try await body(connection)
        await connection.close()
        return result
    }
    catch {
        await connection.close()
        throw error
    }
}

/// Open two connections, run `body`, and always close both.
@discardableResult
func withConnections<T>(_ body: (DBusConnection, DBusConnection) async throws -> T) async throws -> T {

    guard let address = sessionBusAddress
        else { throw NoSessionBus() }

    let first = try await DBusConnection.connect(to: address)

    let second: DBusConnection

    do {
        second = try await DBusConnection.connect(to: address)
    }
    catch {
        await first.close()
        throw error
    }

    do {
        let result = try await body(first, second)
        await first.close()
        await second.close()
        return result
    }
    catch {
        await first.close()
        await second.close()
        throw error
    }
}
