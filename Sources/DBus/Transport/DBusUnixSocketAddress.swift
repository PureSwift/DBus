//
//  DBusUnixSocketAddress.swift
//  DBus
//

import Socket
import SystemPackage

/// The `AF_UNIX` / `SOCK_STREAM` protocol a D-Bus connection uses.
///
/// - Note: `Socket` ships `UnixProtocol`, but its only case maps to `SOCK_RAW`. D-Bus runs
/// over a stream socket.
public enum DBusUnixProtocol: Int32, Sendable, SocketProtocol {

    case stream = 0

    public static var family: SocketAddressFamily { .unix }

    public var type: SocketType { .stream }
}

/// A Unix domain socket address, in either the filesystem or the Linux abstract namespace.
///
/// - Note: `Socket.UnixSocketAddress` stores a `FilePath` and writes `sun_path` with
/// `withPlatformString`, so it cannot express an abstract address: those begin with a NUL byte
/// and their length is carried by the `socklen_t`, not by NUL termination. The session bus is
/// commonly reached through an abstract socket, so this type handles both forms.
///
/// Reference: unix(7), "abstract sockets".
public struct DBusUnixSocketAddress: SocketAddress, Equatable, Hashable, Sendable {

    public typealias ProtocolID = DBusUnixProtocol

    /// Where the socket lives.
    public enum Namespace: Equatable, Hashable, Sendable {

        /// A path in the filesystem, NUL terminated in `sun_path`.
        case filesystem

        /// A name in the Linux abstract namespace, preceded by a NUL byte in `sun_path`
        /// and delimited by the address length rather than by NUL termination.
        case abstract
    }

    /// The namespace the socket lives in.
    public let namespace: Namespace

    /// The path or abstract name, without the leading NUL of the abstract form.
    public let name: String

    internal init(namespace: Namespace, name: String) {

        self.namespace = namespace
        self.name = name
    }

    /// A socket at the given filesystem path.
    public static func path(_ path: String) -> DBusUnixSocketAddress {

        return DBusUnixSocketAddress(namespace: .filesystem, name: path)
    }

    /// A socket with the given name in the Linux abstract namespace.
    public static func abstract(_ name: String) -> DBusUnixSocketAddress {

        return DBusUnixSocketAddress(namespace: .abstract, name: name)
    }
}

// MARK: - Capacity

internal extension DBusUnixSocketAddress {

    /// The size of `sockaddr_un.sun_path`, which is 108 bytes on Linux.
    static var pathCapacity: Int {

        return MemoryLayout.size(ofValue: CInterop.UnixSocketAddress().sun_path)
    }

    /// The offset of `sun_path` within `sockaddr_un`, i.e. the size of `sun_family`.
    static var pathOffset: Int {

        return MemoryLayout<CInterop.UnixSocketAddress>.size - pathCapacity
    }

    /// The bytes written into `sun_path`, and the resulting address length.
    ///
    /// - Filesystem: the path bytes plus a terminating NUL.
    /// - Abstract: a leading NUL, then the name bytes, with no terminator.
    func pathBytes() throws -> (bytes: [UInt8], length: CInterop.SocketLength) {

        let nameBytes = Swift.Array(name.utf8)

        switch namespace {

        case .filesystem:
            guard nameBytes.count + 1 <= DBusUnixSocketAddress.pathCapacity
                else { throw DBusProtocolError.invalidAddress("Socket path is too long: '\(name)'") }

            let bytes = nameBytes + [0]
            return (bytes, CInterop.SocketLength(DBusUnixSocketAddress.pathOffset + bytes.count))

        case .abstract:
            guard nameBytes.count + 1 <= DBusUnixSocketAddress.pathCapacity
                else { throw DBusProtocolError.invalidAddress("Abstract socket name is too long: '\(name)'") }

            // The length, not a NUL, delimits an abstract name, so no terminator is appended.
            let bytes = [0] + nameBytes
            return (bytes, CInterop.SocketLength(DBusUnixSocketAddress.pathOffset + bytes.count))
        }
    }
}

// MARK: - SocketAddress

public extension DBusUnixSocketAddress {

    func withUnsafePointer<Result, Error>(
        _ body: (UnsafePointer<CInterop.SocketAddress>, CInterop.SocketLength) throws(Error) -> Result
    ) rethrows -> Result where Error: Swift.Error {

        // `pathBytes()` only fails for an over-long name, which `init` callers should have
        // rejected; trap rather than widen this protocol requirement to throwing.
        guard let (bytes, length) = try? pathBytes()
            else { fatalError("Socket name exceeds sun_path capacity: '\(name)'") }

        var socketAddress = CInterop.UnixSocketAddress()
        socketAddress.sun_family = numericCast(Self.family.rawValue)

        withUnsafeMutableBytes(of: &socketAddress.sun_path) { pathBuffer in
            for (index, byte) in bytes.enumerated() {
                pathBuffer[index] = byte
            }
        }

        return try Swift.withUnsafeBytes(of: &socketAddress) { buffer throws(Error) -> Result in
            try body(buffer.baseAddress!.assumingMemoryBound(to: CInterop.SocketAddress.self), length)
        }
    }

    static func withUnsafePointer(
        _ pointer: UnsafeMutablePointer<CInterop.SocketAddress>
    ) -> Self {

        return pointer.withMemoryRebound(to: CInterop.UnixSocketAddress.self, capacity: 1) {
            Self.init($0.pointee)
        }
    }

    static func withUnsafePointer(
        _ body: (UnsafeMutablePointer<CInterop.SocketAddress>, CInterop.SocketLength) throws -> ()
    ) rethrows -> Self {

        var socketAddress = CInterop.UnixSocketAddress()

        try withUnsafeMutableBytes(of: &socketAddress) { buffer in
            try body(buffer.baseAddress!.assumingMemoryBound(to: CInterop.SocketAddress.self),
                     CInterop.SocketLength(MemoryLayout<CInterop.UnixSocketAddress>.size))
        }

        return Self.init(socketAddress)
    }

    internal init(_ cValue: CInterop.UnixSocketAddress) {

        var value = cValue

        let (namespace, name): (Namespace, String) = withUnsafeBytes(of: &value.sun_path) { pathBuffer in

            let bytes = pathBuffer.bindMemory(to: UInt8.self)

            guard let first = bytes.first
                else { return (.filesystem, "") }

            if first == 0 {
                // Abstract. Without the true address length the name cannot be delimited
                // exactly, so take everything up to the first trailing NUL run.
                let remainder = bytes.dropFirst().prefix(while: { $0 != 0 })
                return (.abstract, String(decoding: remainder, as: UTF8.self))
            } else {
                let path = bytes.prefix(while: { $0 != 0 })
                return (.filesystem, String(decoding: path, as: UTF8.self))
            }
        }

        self.init(namespace: namespace, name: name)
    }
}

// MARK: - Description

extension DBusUnixSocketAddress: CustomStringConvertible {

    public var description: String {

        switch namespace {
        case .filesystem: return "unix:path=\(name)"
        case .abstract: return "unix:abstract=\(name)"
        }
    }
}
