//
//  TCPTests.swift
//  DBusTests
//

import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Bionic)
import Bionic
#endif
import Socket
import Testing
@testable import DBus

// MARK: - Address parsing

@Suite struct TCPAddressTests {

    @Test func parsesTCPAddress() throws {

        let address = try DBusAddress.parse("tcp:host=127.0.0.1,port=1234,family=ipv4")[0]

        #expect(address.transport == "tcp")
        #expect(address["host"] == "127.0.0.1")
        #expect(address["port"] == "1234")
        #expect(address["family"] == "ipv4")
        #expect(try address.nonce() == nil, "A plain tcp address needs no nonce")
    }

    /// A numeric address needs no name service, so this resolves offline.
    @Test func resolvesLoopbackIPv4() throws {

        let endpoints = try DBusTCPEndpoint.resolve(host: "127.0.0.1", port: 1234, family: .ipv4)

        #expect(endpoints.count >= 1)

        guard case let .ipv4(address) = endpoints[0]
            else { Issue.record("Expected IPv4, got \(endpoints[0])"); return }

        #expect(address.port == 1234, "The port must be in host order")
        #expect(address.address.rawValue == "127.0.0.1")
        #expect(endpoints[0].description == "127.0.0.1:1234")
    }

    @Test func resolvesLoopbackIPv6() throws {

        let endpoints = try DBusTCPEndpoint.resolve(host: "::1", port: 5678, family: .ipv6)

        guard case let .ipv6(address) = endpoints[0]
            else { Issue.record("Expected IPv6, got \(endpoints[0])"); return }

        #expect(address.port == 5678)
        #expect(endpoints[0].description == "[::1]:5678")
    }

    @Test func familyRestrictsResolution() throws {

        // Asking for the wrong family for a numeric address yields nothing.
        #expect(throws: (any Error).self) {
            try DBusTCPEndpoint.resolve(host: "127.0.0.1", port: 1, family: .ipv6)
        }
    }

    @Test func rejectsUnresolvableHost() {

        #expect(throws: (any Error).self) {
            try DBusTCPEndpoint.resolve(host: "this.host.does.not.exist.invalid", port: 1)
        }
    }

    @Test(arguments: [
        "tcp:port=1234",                       // no host
        "tcp:host=127.0.0.1",                  // no port
        "tcp:host=127.0.0.1,port=notanumber",
        "tcp:host=127.0.0.1,port=99999",       // out of UInt16 range
        "tcp:host=127.0.0.1,port=1,family=ipx" // unknown family
    ])
    func rejectsMalformedTCPAddress(string: String) throws {

        let address = try DBusAddress.parse(string)[0]

        #expect(throws: (any Error).self) { try address.tcpEndpoints() }
    }

    @Test func unixAddressIsNotTCP() throws {

        let address = try DBusAddress.parse("unix:path=/run/bus")[0]

        #expect(throws: (any Error).self) { try address.tcpEndpoints() }
    }

    @Test func nonceTCPRequiresNonceFile() throws {

        let address = try DBusAddress.parse("nonce-tcp:host=127.0.0.1,port=1")[0]

        #expect(throws: (any Error).self) { try address.nonce() }
    }

    @Test func nonceMustBeSixteenBytes() throws {

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbus-nonce-\(UInt32.random(in: 0 ... .max))")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let goodPath = directory.appendingPathComponent("good").path
        let shortPath = directory.appendingPathComponent("short").path

        let nonce = [UInt8](repeating: 0xAB, count: 16)
        try Data(nonce).write(to: URL(fileURLWithPath: goodPath))
        try Data([0x01, 0x02]).write(to: URL(fileURLWithPath: shortPath))

        let good = try DBusAddress.parse("nonce-tcp:host=127.0.0.1,port=1,noncefile=\(goodPath)")[0]
        #expect(try good.nonce() == nonce)

        let short = try DBusAddress.parse("nonce-tcp:host=127.0.0.1,port=1,noncefile=\(shortPath)")[0]
        #expect(throws: (any Error).self) { try short.nonce() }

        let missing = try DBusAddress.parse("nonce-tcp:host=127.0.0.1,port=1,noncefile=/nope")[0]
        #expect(throws: (any Error).self) { try missing.nonce() }
    }
}

// MARK: - Live

/// A `dbus-daemon` listening on TCP, started for the duration of a test.
///
/// Configured for `ANONYMOUS` because `EXTERNAL` cannot work over TCP: there are no peer
/// credentials to read, so this also exercises the mechanism fallback for real. (`dbus-send`
/// cannot talk to this bus at all, because libdbus disables ANONYMOUS on the client side.)
///
/// The policy needs `eavesdrop="true"` on its allow rules; without it the daemon refuses even
/// `Hello`, and every call times out.
///
/// - Note: Spawned with `posix_spawn` rather than Foundation's `Process`. `Process` offers only
/// blocking ways to observe the child — `waitUntilExit()` and reading a pipe — and blocking a
/// Swift concurrency cooperative thread from an async test deadlocks the run. Reading the
/// daemon's `--print-address` output is impossible for the same reason: its stdout is block
/// buffered when it is a pipe, so the address never arrives. The port is therefore chosen here
/// and readiness established by connecting.
private final class TCPDaemon {

    let address: String
    private let processID: pid_t
    private let directory: URL

    /// Where `dbus-daemon` lives, or `nil` if it is not installed.
    ///
    /// Homebrew installs outside `/usr/bin`, and to a different prefix on Apple Silicon than on
    /// Intel, so the location is searched rather than assumed.
    private static let executablePath: String? = [
        "/usr/bin/dbus-daemon",
        "/opt/homebrew/bin/dbus-daemon",
        "/usr/local/bin/dbus-daemon"
    ].first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Start a daemon, retrying on a different port if the chosen one is taken.
    static func start() async -> TCPDaemon? {

        guard executablePath != nil
            else { return nil }

        for _ in 0 ..< 3 {

            guard let daemon = TCPDaemon(port: UInt16.random(in: 30000 ... 60000))
                else { continue }

            if await daemon.waitUntilReady() {
                return daemon
            }

            daemon.stop()
        }

        return nil
    }

    private init?(port: UInt16) {

        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbus-tcp-\(UInt32.random(in: 0 ... .max))")

        address = "tcp:host=127.0.0.1,port=\(port),family=ipv4"

        let configuration = """
            <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
             "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
            <busconfig>
              <type>session</type>
              <listen>tcp:host=127.0.0.1,port=\(port),family=ipv4</listen>
              <auth>ANONYMOUS</auth>
              <allow_anonymous/>
              <policy context="default">
                <allow send_destination="*" eavesdrop="true"/>
                <allow eavesdrop="true"/>
                <allow own="*"/>
              </policy>
            </busconfig>
            """

        let configurationURL = directory.appendingPathComponent("bus.conf")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try configuration.write(to: configurationURL, atomically: true, encoding: .utf8)
        }
        catch { return nil }

        guard let executable = TCPDaemon.executablePath,
              let pid = TCPDaemon.spawn([
                  executable,
                  "--config-file=\(configurationURL.path)",
                  "--nofork"
              ]) else {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }

        processID = pid
    }

    /// Launch a process with stdout and stderr discarded, returning its process ID.
    private static func spawn(_ arguments: [String]) -> pid_t? {

        // Darwin typedefs the file actions as an opaque pointer, the other platforms as a struct.
        #if canImport(Darwin)
        var fileActions: posix_spawn_file_actions_t?
        #else
        var fileActions = posix_spawn_file_actions_t()
        #endif

        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)

        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        argv.append(nil)
        defer { argv.forEach { free($0) } }

        // Built from `ProcessInfo` rather than the `environ` global, which Darwin does not
        // export to a linked image.
        var envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment
            .map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer { envp.forEach { free($0) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, arguments[0], &fileActions, nil, argv, envp)

        return status == 0 ? pid : nil
    }

    /// Poll until the daemon accepts a TCP connection, or give up.
    ///
    /// - Note: A plain socket connect rather than a full `DBusConnection`, so the probe does
    /// not consume a bus connection or run the SASL handshake. Completing and then dropping a
    /// real session made the daemon shut down the connection that followed.
    private func waitUntilReady() async -> Bool {

        guard case let .ipv4(endpoint)? = try? DBusAddress.parse(address).first?.tcpEndpoints().first
            else { return false }

        for _ in 0 ..< 30 {

            if let socket = try? await Socket(IPv4Protocol.tcp) {

                if (try? await socket.connect(to: endpoint)) != nil {
                    await socket.close()
                    return true
                }

                await socket.close()
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        return false
    }

    func stop() {

        // SIGKILL rather than SIGTERM so the reap below cannot block on a slow shutdown.
        kill(processID, SIGKILL)

        var status: Int32 = 0
        waitpid(processID, &status, 0)

        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite(.serialized) struct TCPConnectionTests {

    /// Run `body` against a freshly started TCP daemon, or skip if one cannot be started.
    ///
    /// The daemon is always stopped, including when the body throws, so no process outlives
    /// the test.
    private func withTCPDaemon(_ body: (String) async throws -> Void) async throws {

        await SocketGate.shared.lock()

        guard let daemon = await TCPDaemon.start() else {
            await SocketGate.shared.unlock()
            return
        }

        do {
            try await body(daemon.address)
            daemon.stop()
            await SocketGate.shared.unlock()
        }
        catch {
            daemon.stop()
            await SocketGate.shared.unlock()
            throw error
        }
    }

    @Test func connectsOverTCP() async throws {

        try await withTCPDaemon { address in

            #expect(address.hasPrefix("tcp:"), "Expected a TCP address, got \(address)")

            let connection = try await DBusConnection.connect(to: address)

            let uniqueName = await connection.uniqueName
            #expect(uniqueName?.isUnique == true, "Hello did not complete over TCP")
            #expect(await connection.serverGUID != nil)

            await connection.close()
        }
    }

    /// EXTERNAL cannot succeed over TCP, so the client must fall back to ANONYMOUS by itself.
    @Test func fallsBackToAnonymousOverTCP() async throws {

        try await withTCPDaemon { address in

            let connection = try await DBusConnection.connect(
                to: address,
                mechanisms: [.external, .cookieSHA1, .anonymous]
            )

            #expect(await connection.isConnected)

            await connection.close()
        }
    }

    /// Method calls and replies must work the same over TCP as over a Unix socket, which also
    /// checks the marshalling is transport independent.
    @Test func callsMethodsOverTCP() async throws {

        try await withTCPDaemon { address in

            let connection = try await DBusConnection.connect(to: address)

            let names = try await connection.listNames()
            #expect(names.contains("org.freedesktop.DBus"))

            let ownName = try #require(await connection.uniqueName)
            #expect(names.contains(ownName.rawValue))

            let busID = try await connection.getBusID()
            #expect(busID.isEmpty == false)

            await connection.close()
        }
    }

    /// The daemon's address names a specific resolved endpoint, so this also checks that
    /// `endpoints()` produces something connectable.
    @Test func resolvesDaemonAddressToEndpoint() async throws {

        try await withTCPDaemon { address in

            let parsed = try DBusAddress.parse(address)[0]
            let endpoints = try parsed.tcpEndpoints()

            #expect(endpoints.isEmpty == false)
            #expect(endpoints.allSatisfy { $0.port != 0 })
        }
    }

    /// Nothing is listening on a closed port, so connecting must fail rather than hang.
    @Test func failsOnRefusedConnection() async throws {

        await SocketGate.shared.lock()

        await #expect(throws: (any Error).self) {
            try await DBusConnection.connect(to: "tcp:host=127.0.0.1,port=1,family=ipv4")
        }

        await SocketGate.shared.unlock()
    }
}
