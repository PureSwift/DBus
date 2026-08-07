//
//  Runtime.swift
//  DBus
//
//  The machinery every C entry point relies on: object boxing, the bridge
//  from this package's `async` API to the blocking calls the C ABI promises,
//  and error translation.
//
//  - Note: `DBusError`, `DBusMessage` and `DBusConnection` each name both a C
//  type here and a Swift type in the `DBus` module, so every reference to one
//  of them in this target is written module qualified. The C opaque structs
//  (`DBusConnection`, `DBusMessage`) arrive in Swift as `OpaquePointer`.
//

import Foundation
import CDBusABI
import DBus

// MARK: - Boxing

/// A reference counted Swift object addressed from C as an opaque pointer.
///
/// The C ABI is explicitly reference counted — `dbus_message_ref` and friends —
/// so the counts are kept by `Unmanaged` rather than by ARC: a pointer handed
/// to C carries a retain that only the matching `unref` releases.
internal class Box {

    /// Take an unbalanced retain and return the pointer to hand to C.
    func retainedPointer() -> OpaquePointer {

        return OpaquePointer(Unmanaged.passRetained(self).toOpaque())
    }

    /// Add one to the count, for `dbus_*_ref`.
    static func retain(_ pointer: OpaquePointer) {

        _ = Unmanaged<Box>.fromOpaque(UnsafeRawPointer(pointer)).retain()
    }

    /// Subtract one from the count, for `dbus_*_unref`.
    static func release(_ pointer: OpaquePointer) {

        Unmanaged<Box>.fromOpaque(UnsafeRawPointer(pointer)).release()
    }

    /// The object a C pointer refers to, without changing the count.
    static func unretained<T: Box>(_ pointer: OpaquePointer) -> T? {

        return Unmanaged<Box>.fromOpaque(UnsafeRawPointer(pointer)).takeUnretainedValue() as? T
    }
}

// MARK: - Blocking

/// Run an asynchronous operation to completion, blocking the calling thread.
///
/// The C ABI has no way to express `async`, and the entry points implemented
/// here are the blocking ones by definition — `..._and_block` is in the name.
/// A C caller arrives on its own thread, never on a Swift concurrency
/// cooperative thread, so parking that thread on a semaphore does not starve
/// the executor the detached task runs on.
internal func blocking<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {

    let semaphore = DispatchSemaphore(value: 0)
    let result = ResultBox<T>()

    Task.detached {

        do { result.value = .success(try await body()) }
        catch { result.value = .failure(error) }

        semaphore.signal()
    }

    semaphore.wait()

    switch result.value {
    case let .success(value): return value
    case let .failure(error): throw error
    case nil: throw DBusABIError.internalFailure
    }
}

/// Carries a result across the semaphore.
///
/// Written once by the task before `signal()` and read once after `wait()`,
/// which orders the two accesses, so no further synchronization is needed.
private final class ResultBox<T>: @unchecked Sendable {

    var value: Result<T, Error>?
}

internal enum DBusABIError: Error, CustomStringConvertible {

    case internalFailure

    var description: String { "The operation could not be completed" }
}

// MARK: - Strings

/// The Swift string a C argument refers to, or `nil` for a null pointer.
internal func string(_ pointer: UnsafePointer<CChar>?) -> String? {

    guard let pointer = pointer
        else { return nil }

    return String(cString: pointer)
}

internal extension String {

    /// A copy owned by the caller, released with `dbus_free`.
    func copiedCString() -> UnsafeMutablePointer<CChar>? {

        return strdup(self)
    }
}

// MARK: - Errors

/// Marks a `DBusError` whose strings were allocated by this library.
///
/// The reference uses one of the `dummy` bitfields for this. A bitfield is
/// awkward to address from Swift and its import is an implementation detail,
/// so the spare `padding1` pointer carries the flag instead: it is private to
/// the implementation in the reference too, and callers only ever read `name`
/// and `message`.
private nonisolated(unsafe) let ownedStringsMarker = UnsafeMutableRawPointer(bitPattern: 0x1)

internal extension DBus.DBusError.Name {

    /// The nearest error name for a failure that did not come from the bus.
    static func from(_ error: Error) -> DBus.DBusError.Name {

        if let busError = error as? DBus.DBusError {
            return busError.name
        }

        guard let protocolError = error as? DBusProtocolError
            else { return .failed }

        switch protocolError {
        case .invalidAddress:
            return .badAddress
        case .endOfStream:
            return .disconnected
        case .authenticationFailed, .authenticationRejected:
            return .accessDenied
        case .messageTooLarge:
            return .limitsExceeded
        case .invalidSignature:
            return .invalidSignature
        default:
            return .failed
        }
    }
}

/// Fill in a caller supplied `DBusError` from a thrown Swift error.
internal func setError(_ error: UnsafeMutablePointer<CDBusABI.DBusError>?, from thrown: Error) {

    guard let error = error
        else { return }

    let message: String

    if let busError = thrown as? DBus.DBusError {
        message = busError.message
    } else if let described = thrown as? CustomStringConvertible {
        message = described.description
    } else {
        message = "\(thrown)"
    }

    setError(error, name: DBus.DBusError.Name.from(thrown).rawValue, message: message)
}

/// Fill in a caller supplied `DBusError` from two strings.
internal func setError(_ error: UnsafeMutablePointer<CDBusABI.DBusError>?,
                       name: String,
                       message: String) {

    guard let error = error
        else { return }

    // Replacing an error that is already set would leak the strings it holds.
    freeError(error)

    error.pointee.name = UnsafePointer(strdup(name))
    error.pointee.message = UnsafePointer(strdup(message))
    error.pointee.padding1 = ownedStringsMarker
}

/// Release the strings a `DBusError` owns and return it to the unset state.
internal func freeError(_ error: UnsafeMutablePointer<CDBusABI.DBusError>?) {

    guard let error = error
        else { return }

    if error.pointee.padding1 == ownedStringsMarker {

        free(UnsafeMutableRawPointer(mutating: error.pointee.name))
        free(UnsafeMutableRawPointer(mutating: error.pointee.message))
    }

    error.pointee.name = nil
    error.pointee.message = nil
    error.pointee.padding1 = nil
}

// MARK: - Booleans

internal extension Bool {

    /// `dbus_bool_t` is a 32 bit integer, not a C `_Bool`.
    var cBool: dbus_bool_t { self ? 1 : 0 }
}
