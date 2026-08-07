# DBus

Pure Swift library for D-Bus. No `libdbus`, no C implementation — the wire format, the SASL
handshake and the transport are all implemented in Swift.

## Requirements

- Swift 6.0+
- Linux (or any platform with a D-Bus daemon reachable over a Unix socket)

Depends on [PureSwift/Socket](https://github.com/PureSwift/Socket) for async sockets.

> The manifest currently points at a local `../Socket` checkout, which carries three changes not
> yet upstream: `SCM_RIGHTS` ancillary data support that file-descriptor passing is built on, and
> two socket-monitor fixes — deferred poll results being applied to a reused descriptor, and a
> never-connected socket being torn down because an unconnected socket polls as `POLLHUP`.

## Usage

```swift
import DBus

let connection = try await DBusConnection.connect(to: .session)

let reply = try await connection.send(
    DBusMessage(methodCall: DBusMessage.MethodCall(
        destination: DBusBusName(rawValue: "org.freedesktop.DBus")!,
        path: DBusObjectPath(rawValue: "/org/freedesktop/DBus")!,
        interface: DBusInterface(rawValue: "org.freedesktop.DBus")!,
        method: DBusMember(rawValue: "ListNames")!
    ))
)

if case let .array(names)? = reply.arguments.first {
    for name in names.compactMap({ $0.stringValue }) {
        print(name)
    }
}

await connection.close()
```

An error reply is thrown as a `DBusError` carrying its `org.freedesktop.DBus.Error.*` name;
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

`DBusMessage` and every value type are `Sendable` structs. `DBusConnection` is an actor that owns
the socket, runs the read loop and matches replies to calls by serial. Nothing wraps a C pointer,
so there is no reference counting to get wrong.

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

Not yet implemented:

- Code generation from introspection XML

## Tests

```sh
swift test
```

Written with [Swift Testing](https://github.com/swiftlang/swift-testing). The suites that need a
live bus are marked `.enabled(if: hasSessionBus)`, so they report as skipped rather than passing
when no bus socket is present.

## License

MIT. See [LICENSE](LICENSE).
