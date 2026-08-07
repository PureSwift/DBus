//
//  DBusTCPAddress.swift
//  DBus
//

import Socket
import SystemPackage

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Bionic)
import Bionic
#endif

/// A resolved TCP endpoint to connect to.
///
/// - Note: An enum because `IPv4SocketAddress` and `IPv6SocketAddress` are distinct types with
/// distinct protocol identifiers, so the socket must be created differently for each.
public enum DBusTCPEndpoint: Equatable, Hashable, Sendable {

    case ipv4(IPv4SocketAddress)
    case ipv6(IPv6SocketAddress)
}

public extension DBusTCPEndpoint {

    /// The port the endpoint refers to.
    var port: UInt16 {

        switch self {
        case let .ipv4(address): return address.port
        case let .ipv6(address): return address.port
        }
    }
}

extension DBusTCPEndpoint: CustomStringConvertible {

    public var description: String {

        switch self {
        case let .ipv4(address): return "\(address.address.rawValue):\(address.port)"
        case let .ipv6(address): return "[\(address.address.rawValue)]:\(address.port)"
        }
    }
}

// MARK: - Resolution

public extension DBusTCPEndpoint {

    /// The address family a `tcp:` address may request.
    enum Family: String, Sendable {

        case ipv4
        case ipv6
    }

    /// Resolve a host and port into every endpoint that can be tried, in the order the
    /// resolver returned them.
    ///
    /// - Parameter family: Restricts the lookup when the address specified one; otherwise both
    /// families are returned.
    static func resolve(host: String,
                        port: UInt16,
                        family: Family? = nil) throws -> [DBusTCPEndpoint] {

        var hints = addrinfo()
        // Glibc, Musl and Bionic declare the socket types as an enumeration; Darwin as Int32.
        #if canImport(Darwin)
        hints.ai_socktype = SOCK_STREAM
        #else
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #endif
        hints.ai_protocol = Int32(IPPROTO_TCP)

        switch family {
        case .ipv4: hints.ai_family = AF_INET
        case .ipv6: hints.ai_family = AF_INET6
        case nil: hints.ai_family = AF_UNSPEC
        }

        var result: UnsafeMutablePointer<addrinfo>?

        let status = host.withCString { hostPointer in
            String(port).withCString { portPointer in
                getaddrinfo(hostPointer, portPointer, &hints, &result)
            }
        }

        guard status == 0, let first = result else {

            let reason = status == 0 ? "no addresses" : String(cString: gai_strerror(status))
            throw DBusProtocolError.invalidAddress("Could not resolve \(host):\(port): \(reason)")
        }

        defer { freeaddrinfo(first) }

        var endpoints = [DBusTCPEndpoint]()

        var entry: UnsafeMutablePointer<addrinfo>? = first

        while let current = entry {

            defer { entry = current.pointee.ai_next }

            guard let socketAddress = current.pointee.ai_addr
                else { continue }

            switch current.pointee.ai_family {

            case AF_INET:
                let value = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                endpoints.append(.ipv4(IPv4SocketAddress(address: IPv4Address(value.sin_addr),
                                                         port: UInt16(bigEndian: value.sin_port))))

            case AF_INET6:
                let value = socketAddress.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                endpoints.append(.ipv6(IPv6SocketAddress(address: IPv6Address(value.sin6_addr),
                                                         port: UInt16(bigEndian: value.sin6_port))))

            default:
                continue // a family this transport does not speak
            }
        }

        guard endpoints.isEmpty == false
            else { throw DBusProtocolError.invalidAddress("No usable address for \(host):\(port)") }

        return endpoints
    }
}

// MARK: - Address

public extension DBusAddress {

    /// The TCP endpoints this address refers to.
    ///
    /// Recognises the `tcp:` and `nonce-tcp:` transports, both of which take `host`, `port` and
    /// an optional `family`.
    ///
    /// - Throws: `DBusProtocolError.invalidAddress` if the transport is not TCP, or the host or
    /// port is missing or malformed.
    func tcpEndpoints() throws -> [DBusTCPEndpoint] {

        guard transport == "tcp" || transport == "nonce-tcp"
            else { throw DBusProtocolError.invalidAddress("Not a TCP transport: '\(transport)'") }

        guard let host = self["host"], host.isEmpty == false
            else { throw DBusProtocolError.invalidAddress("No host in TCP address") }

        guard let portString = self["port"], let port = UInt16(portString)
            else { throw DBusProtocolError.invalidAddress("No valid port in TCP address") }

        let family: DBusTCPEndpoint.Family?

        if let familyString = self["family"] {
            guard let parsed = DBusTCPEndpoint.Family(rawValue: familyString)
                else { throw DBusProtocolError.invalidAddress("Unknown address family '\(familyString)'") }
            family = parsed
        } else {
            family = nil
        }

        return try DBusTCPEndpoint.resolve(host: host, port: port, family: family)
    }

    /// The nonce a `nonce-tcp:` address requires, read from the file it names.
    ///
    /// The client sends these bytes immediately after connecting and before the SASL handshake
    /// begins, proving it can read a file only the server's user can read.
    ///
    /// - Returns: `nil` for a plain `tcp:` address, which needs no nonce.
    func nonce() throws -> [UInt8]? {

        guard transport == "nonce-tcp"
            else { return nil }

        guard let path = self["noncefile"]
            else { throw DBusProtocolError.invalidAddress("nonce-tcp address has no noncefile") }

        guard let descriptor = try? FileDescriptor.open(FilePath(path), .readOnly)
            else { throw DBusProtocolError.invalidAddress("Could not read the nonce file at \(path)") }

        defer { try? descriptor.close() }

        // The nonce is a fixed 16 bytes, but read a little more so a wrong-sized file is
        // detected rather than silently truncated.
        var buffer = [UInt8](repeating: 0, count: 32)

        guard let count = try? buffer.withUnsafeMutableBytes({ try descriptor.read(into: $0) })
            else { throw DBusProtocolError.invalidAddress("Could not read the nonce file at \(path)") }

        guard count == DBusAddress.nonceLength
            else { throw DBusProtocolError.invalidAddress("Nonce file is \(count) bytes, expected \(DBusAddress.nonceLength)") }

        return Array(buffer[0 ..< count])
    }

    /// The length of a nonce-tcp nonce, in bytes.
    static var nonceLength: Int { 16 }
}

// MARK: - Endpoint

/// Somewhere a connection can be established.
internal enum DBusTransportEndpoint {

    case unix(DBusUnixSocketAddress)

    /// A TCP endpoint, with the nonce to send first if the transport requires one.
    case tcp(DBusTCPEndpoint, nonce: [UInt8]?)
}

internal extension DBusAddress {

    /// Every endpoint this address can be reached at, in preference order.
    func endpoints() throws -> [DBusTransportEndpoint] {

        switch transport {

        case "unix":
            return [.unix(try unixSocketAddress())]

        case "tcp", "nonce-tcp":
            let nonce = try self.nonce()
            return try tcpEndpoints().map { .tcp($0, nonce: nonce) }

        default:
            throw DBusProtocolError.invalidAddress("Unsupported transport '\(transport)'")
        }
    }
}
