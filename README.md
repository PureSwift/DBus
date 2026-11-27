# DBus

A Swift implementation of D-Bus with async connections, object export, and generated
clients for common desktop services. The wire format, SASL handshake, and transport
are implemented in Swift without depending on `libdbus`. An optional C ABI exposes
a subset of the libdbus-1 API.

## Requirements

- Swift 6.4+
- Linux or macOS 13+
- A reachable D-Bus daemon for bus connections, using Unix sockets or TCP
- The corresponding service daemon for service clients

Uses [PureSwift/Socket](https://github.com/PureSwift/Socket) for async sockets.
SwiftPM requires Socket 0.7.0 or a compatible release before 1.0.0.

## Swift Package Manager

Add `https://github.com/PureSwift/DBus.git` as a package dependency. Select the
`DBus` product for the core API and any service products your application uses:
`BlueZ`, `NetworkManager`, `UPower`, `Login1`, `ScreenSaver`, `Avahi`,
`SecretService`, `DesktopNotifications`, `StatusNotifier`, `FreedesktopPortal`,
`MPRIS`, `Polkit`, or `UDisks2`. Each service has
its own target and depends on `DBus`.

For example, a target using Bluetooth clients can declare:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "DBus", package: "DBus"),
        .product(name: "BlueZ", package: "DBus")
    ]
)
```

## Usage

```swift
import DBus

let connection = try await DBusConnection.connect(to: .session)

for name in try await connection.listNames() {
    print(name)
}

await connection.close()
```

Use `callMethod` or `send` for custom method calls. An error reply is thrown as a
`DBusError` carrying the remote error name;
framing and marshalling failures are thrown as `DBusProtocolError`.

### File descriptors

A `UNIX_FD` argument carries a real descriptor. On the wire it is marshalled as an index into
the descriptors sent out of band, so the value you pass is the descriptor itself:

```swift
try await connection.callMethod(
    destination: name,
    path: path,
    interface: interface,
    method: DBusMember(rawValue: "Accept")!,
    arguments: [.fileDescriptor(.init(rawValue: myFileDescriptor))]
)
```

The peer receives its own descriptor referring to the same open file, and **owns it**: close it
when finished. Sending requires the peer to have agreed to `NEGOTIATE_UNIX_FD`, which
`unixFileDescriptorsSupported` reports.

### Signals

A connection receives no broadcast signals until it installs a match rule. `signals(matching:)`
installs one and yields matching messages until the stream is dropped, which removes it again.

```swift
let signals = try await connection.signals(matching: .nameOwnerChanged())

for await signal in signals {
    print(signal.arguments)
}
```

### Exporting an object

```swift
actor CounterState {
    private(set) var total: UInt32 = 0

    func increment() -> UInt32 {
        total += 1
        return total
    }
}

let state = CounterState()
let counter = DBusInterfaceImplementation(
    name: DBusInterface(rawValue: "com.example.Counter")!,
    methods: [
        .init(name: DBusMember(rawValue: "Increment")!,
              outputSignature: DBusSignature(rawValue: "u")!,
              handler: { _ in [.uint32(await state.increment())] })
    ],
    properties: [
        .init(name: "Total", type: .uint32, access: .read,
              get: { .uint32(await state.total) })
    ]
)

await connection.export(DBusExportedObject([counter]),
                        at: DBusObjectPath(rawValue: "/com/example/Counter")!)

try await connection.requestName(DBusBusName(rawValue: "com.example.Counter")!)
```

`org.freedesktop.DBus.Peer`, `.Introspectable` and `.Properties` are answered automatically:
introspection XML is generated from the declared methods, properties and signals.

## Design

The core API uses `Sendable` value types for messages and arguments. `DBusConnection`
is an actor that owns the socket, runs the read loop, and matches replies to calls
by serial. Callers own their connections and close them when finished.

Values are modelled by `DBusMessageArgument`, which covers every D-Bus type including `variant`
and `dict`. Array element types are stored explicitly rather than inferred, so an empty array
still marshals with the right signature.

Names are validated on construction by hand-written parsers: `DBusObjectPath`, `DBusInterface`,
`DBusMember`, `DBusBusName` and `DBusSignature`.

## Status

Implemented:

- Message marshalling and unmarshalling, both byte orders
- Bus address parsing (`unix:path=`, `unix:abstract=`, `unix:runtime=yes`, percent escaping)
- Unix socket transport, including the Linux abstract namespace
- SASL `EXTERNAL` and `ANONYMOUS`, plus `NEGOTIATE_UNIX_FD`
- Method calls and replies, with timeouts
- Bus daemon API: name registration and queries, `AddMatch` / `RemoveMatch`
- Match rules, with spec-correct encoding and local matching
- Signal subscriptions as `AsyncStream`
- Server side: object export, method dispatch, signal emission
- `org.freedesktop.DBus.Peer`, `.Introspectable` and `.Properties`
- SASL `DBUS_COOKIE_SHA1`, with a pure-Swift SHA-1
- `tcp:` and `nonce-tcp:` transports, IPv4 and IPv6
- Unix file descriptor passing, via `SCM_RIGHTS`
- Parsing introspection XML into a typed node model
- Service client generation from checked-in Python API definitions
- Optional subset of the libdbus-1 C ABI

Not yet implemented:

- Automatic client generation from introspection XML. The existing service generator
  uses Python API definitions; it does not read introspection XML.

## Service libraries

Each service is a separate SwiftPM library product and import:

| Product | Coverage | Bus |
| --- | --- | --- |
| `BlueZ` | ObjectManager, adapter, device, GATT service/characteristic/descriptor, agent and registration clients | System |
| `NetworkManager` | Manager, device, wireless, access-point and connection-settings clients | System |
| `UPower` | Manager and device methods, battery properties and signals | System |
| `Login1` | Manager/session clients, power operations and inhibitors | System |
| `ScreenSaver` | Idle inhibition and KDE-compatible screen saver controls | Session |
| `Avahi` | Server/Server2, entry groups, service browsers and resolvers | System |
| `SecretService` | Service, collections, items, sessions and prompts | Session |
| `DesktopNotifications` | Notifications, capabilities and server information | Session |
| `StatusNotifier` | Watcher, item and DBusMenu clients | Session |
| `FreedesktopPortal` | FileChooser, OpenURI, Settings, ScreenCast, request and session clients | Session |
| `MPRIS` | Media player identity, playback, metadata and writable controls | Session |
| `Polkit` | Authority authorization checks and authentication agent registration | System |
| `UDisks2` | ObjectManager, manager, drives, blocks, filesystems, partitions, encryption, loops, swap and jobs | System |

All thirteen products are generated from checked-in interface definitions and use
caller-owned connections. BlueZ's `getManagedObjects()` returns a snapshot; consumers maintain
their own cache using `signals()` and per-object `propertyChanges()` streams.
NetworkManager scans use `requestScan(options:)` and `LastScan` property changes
instead of a built-in polling loop. Agent callbacks and exported GATT objects
remain application responsibilities.

Dots in interface names map to nested Swift types after the service namespace;
interface version suffixes are omitted from child type names:

| D-Bus interface | Swift type | Source file |
| --- | --- | --- |
| `org.bluez.Adapter1` | `BlueZ.Adapter` | `BlueZAdapter.swift` |
| `org.freedesktop.NetworkManager.Device.Wireless` | `NetworkManager.Device.Wireless` | `NetworkManagerWireless.swift` |
| `org.freedesktop.NetworkManager.Settings.Connection` | `NetworkManager.Settings.Connection` | `NetworkManagerSettingsConnection.swift` |
| `org.freedesktop.UPower.Device` | `UPower.Device` | `UPowerDevice.swift` |
| `org.freedesktop.login1.Manager` | `Login1.Manager` | `Login1.swift` |

`BlueZ` itself provides the ObjectManager client. `NetworkManager`, `UPower`, and
`ScreenSaver` provide their root clients; `Login1` is a namespace for its clients.
Generated filenames remain stable. Avahi exposes both `Avahi.Server` and
`Avahi.Server2` because the latter uses prepare/start operations for browsing.
Subscribe to a prepared browser's signals before calling `start()`.

`MPRIS` and `MPRIS.Player` require a `destination:` bus name, such as
`org.mpris.MediaPlayer2.vlc`. `StatusNotifier.Item`, `StatusNotifier.Menu` and
`BlueZ.Agent` likewise require the destination of the application exporting them.
Agent, notifier item and menu exports remain application responsibilities.

Portal methods return request paths; use `FreedesktopPortal.Request` and its
`signals()` stream to handle `Response`, and keep session objects alive until
finished. Subscribe before starting an operation (using a predictable handle token
and `connection.signals(matching:)` when needed) to avoid missing an early response.
Secret Service clients expose the wire protocol: callers choose and implement
session encryption, handle returned prompt paths, and close sessions explicitly.
Notification action/closure events and other service signals are available through
`signals()` as `DBusMessage` values. KDE-specific notification inhibition methods
may be unavailable on other notification servers.

The generated clients accept a caller-owned connection:

```swift
import DBus
import UPower

let connection = try await DBusConnection.connect(to: .system)
let power = try UPower(connection: connection)
let onBattery = try await power.onBattery
await connection.close()
```

For an object-specific client, pass its object path:

```swift
import DBus
import BlueZ

let connection = try await DBusConnection.connect(to: .system)
// Use an adapter path discovered through BlueZ.getManagedObjects().
let adapter = try BlueZ.Adapter(connection: connection, path: "/org/bluez/hci0")
let powered = try await adapter.powered
await connection.close()
```

`properties()`, `propertyChanges()` and `signals()` expose property snapshots and
async message streams. Recreate subscriptions when a service restarts. Complex
array, dictionary and structure results retain their D-Bus representation;
container arguments and replies are signature-checked. Methods with multiple
results return labeled tuples. Writable properties have async throwing setter methods, such as
`try await adapter.setPowered(true)`.
Remote errors propagate as `DBusError`, including unsupported optional methods.

For `ScreenSaver`, use a session-bus connection and keep it open for the lifetime
of an inhibition cookie. Pass that cookie to `unInhibit(cookie:)` to release it.
Only Inhibit/UnInhibit are standardized by the idle-inhibition specification;
the other screen saver methods depend on the desktop implementation.
For `Login1.Manager.inhibit`, the caller owns the returned file descriptor and must close
it to release the inhibitor. Closing only the D-Bus connection does not release it.

### Regenerating service clients

Edit the API metadata in [Scripts/service_definitions.py](Scripts/service_definitions.py)
and run:

```sh
python3 Scripts/generate-service-clients.py
```

[Scripts/generate-service-clients.py](Scripts/generate-service-clients.py) contains
the Swift generation logic. It writes all thirteen service products; do not edit the
generated Swift files manually. Upstream interface references are linked in the
API definitions and generated files.

## Optional C ABI

The `DBusABI` product implements the subset declared in
[dbus.h](Sources/CDBusABI/include/dbus/dbus.h). A small C shim handles variadic
entry points. Enable the product and its tests explicitly in SwiftPM:

```sh
SWIFTPM_DBUS_CABI=1 swift build
SWIFTPM_DBUS_CABI=1 swift test --filter DBusABITests --no-parallel
```

It exports fixed `dbus_*` symbols and should not be linked alongside the real
libdbus-1 in the same process.

For an installable Linux shared library, use CMake 3.26+ and Ninja:

```sh
swift build
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
cmake --build build --target check-exports check-abi
cmake --install build --prefix /usr/local
```

CMake reuses the Socket and swift-system checkouts resolved by SwiftPM. It builds
`libdbus-swift.so.0`, with its own library name because it implements only part
of the libdbus-1 ABI. Service products are built through SwiftPM.

## Tests

```sh
swift test --no-parallel
```

To exercise live session-bus tests on Linux, run under a temporary bus:

```sh
dbus-run-session -- swift test --no-parallel
```

Written with [Swift Testing](https://github.com/swiftlang/swift-testing). The suites that need a
live session bus skip those tests when no bus socket is present. The service tests
include a local exported service to exercise generated clients without requiring
the corresponding desktop daemons.

## License

MIT. See [LICENSE](LICENSE).
