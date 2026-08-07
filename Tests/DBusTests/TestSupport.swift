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

/// Serializes every test that opens a socket.
///
/// `.serialized` only orders tests *within* one suite, and Swift Testing runs separate suites
/// concurrently. `Socket` routes all descriptors through a process-wide manager keyed by file
/// descriptor number, so suites opening and closing sockets at the same time can collide as
/// numbers are reused. This gate makes the socket-using tests take turns regardless of suite.
///
/// - Note: Exposed as `lock`/`unlock` rather than a closure-taking method so that no
/// non-`Sendable` closure or result has to cross the actor boundary.
actor SocketGate {

    static let shared = SocketGate()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {

        while isLocked {
            await withCheckedContinuation { waiters.append($0) }
        }

        isLocked = true
    }

    func unlock() {

        isLocked = false

        if waiters.isEmpty == false {
            waiters.removeFirst().resume()
        }
    }
}

/// Open a connection to the session bus, run `body`, and always close afterwards.
///
/// Swift Testing has no asynchronous teardown hook, and `defer { Task { ... } }` would not
/// finish before the next test began, so connection lifetime is scoped by this helper instead.
@discardableResult
func withConnection<T>(_ body: (DBusConnection) async throws -> T) async throws -> T {

    guard let address = sessionBusAddress
        else { throw NoSessionBus() }

    await SocketGate.shared.lock()

    let connection: DBusConnection

    do { connection = try await DBusConnection.connect(to: address) }
    catch {
        await SocketGate.shared.unlock()
        throw error
    }

    do {
        let result = try await body(connection)
        await connection.close()
        await SocketGate.shared.unlock()
        return result
    }
    catch {
        await connection.close()
        await SocketGate.shared.unlock()
        throw error
    }
}

/// Open two connections, run `body`, and always close both.
@discardableResult
func withConnections<T>(_ body: (DBusConnection, DBusConnection) async throws -> T) async throws -> T {

    guard let address = sessionBusAddress
        else { throw NoSessionBus() }

    await SocketGate.shared.lock()

    let first: DBusConnection
    let second: DBusConnection

    do {
        first = try await DBusConnection.connect(to: address)
    }
    catch {
        await SocketGate.shared.unlock()
        throw error
    }

    do {
        second = try await DBusConnection.connect(to: address)
    }
    catch {
        await first.close()
        await SocketGate.shared.unlock()
        throw error
    }

    do {
        let result = try await body(first, second)
        await first.close()
        await second.close()
        await SocketGate.shared.unlock()
        return result
    }
    catch {
        await first.close()
        await second.close()
        await SocketGate.shared.unlock()
        throw error
    }
}
