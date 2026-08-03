//
//  BusAPI.swift
//  DBus
//

/// Well known names, paths and interfaces of the message bus itself.
public enum DBusWellKnown {

    /// The bus daemon's well known name, `org.freedesktop.DBus`.
    public static let busName = DBusBusName("org.freedesktop.DBus")

    /// The bus daemon's object path, `/org/freedesktop/DBus`.
    public static let busPath = DBusObjectPath("/org/freedesktop/DBus")

    /// The bus daemon's interface, `org.freedesktop.DBus`.
    public static let busInterface = DBusInterface(rawValue: "org.freedesktop.DBus")!

    /// `org.freedesktop.DBus.Peer`
    public static let peerInterface = DBusInterface(rawValue: "org.freedesktop.DBus.Peer")!

    /// `org.freedesktop.DBus.Introspectable`
    public static let introspectableInterface = DBusInterface(rawValue: "org.freedesktop.DBus.Introspectable")!

    /// `org.freedesktop.DBus.Properties`
    public static let propertiesInterface = DBusInterface(rawValue: "org.freedesktop.DBus.Properties")!
}

// MARK: - Calling

public extension DBusConnection {

    /// Invoke a method and return the reply's arguments.
    ///
    /// - Throws: The `DBusError` carried by an error reply.
    @discardableResult
    func callMethod(destination: DBusBusName?,
                    path: DBusObjectPath,
                    interface: DBusInterface?,
                    method: DBusMember,
                    arguments: [DBusMessageArgument] = [],
                    timeout: Duration? = DBusConnection.defaultTimeout) async throws -> [DBusMessageArgument] {

        let call = DBusMessage.MethodCall(destination: destination,
                                          path: path,
                                          interface: interface,
                                          method: method)

        let reply = try await send(DBusMessage(methodCall: call, arguments: arguments), timeout: timeout)

        return reply.arguments
    }

    /// Invoke a method on the bus daemon itself.
    @discardableResult
    internal func callBus(_ method: String,
                          arguments: [DBusMessageArgument] = []) async throws -> [DBusMessageArgument] {

        return try await callMethod(destination: DBusWellKnown.busName,
                                    path: DBusWellKnown.busPath,
                                    interface: DBusWellKnown.busInterface,
                                    method: DBusMember(method),
                                    arguments: arguments)
    }
}

// MARK: - Name Registration

public extension DBusConnection {

    /// Flags controlling how a name is requested.
    struct RequestNameFlags: OptionSet, Equatable, Hashable, Sendable {

        public var rawValue: UInt32

        public init(rawValue: UInt32) {

            self.rawValue = rawValue
        }

        /// If another connection already owns the name and has set `allowReplacement`,
        /// take ownership from it.
        public static let allowReplacement = RequestNameFlags(rawValue: 0x01)

        /// Allow another connection that sets `allowReplacement` to take the name from us.
        public static let replaceExisting = RequestNameFlags(rawValue: 0x02)

        /// Do not place the request in the queue if the name is already owned; fail instead.
        public static let doNotQueue = RequestNameFlags(rawValue: 0x04)
    }

    /// The outcome of requesting a name.
    enum RequestNameResult: UInt32, Sendable {

        /// The caller is now the primary owner of the name.
        case primaryOwner = 1

        /// The name is already owned and the caller has been placed in the queue.
        case inQueue = 2

        /// The name is already owned and `doNotQueue` was set.
        case exists = 3

        /// The caller already owns the name.
        case alreadyOwner = 4
    }

    /// The outcome of releasing a name.
    enum ReleaseNameResult: UInt32, Sendable {

        /// The name was released.
        case released = 1

        /// No such name exists on the bus.
        case nonExistent = 2

        /// The name exists but the caller was neither its owner nor in its queue.
        case notOwner = 3
    }

    /// Ask the bus to assign the given well known name to this connection.
    @discardableResult
    func requestName(_ name: DBusBusName,
                     flags: RequestNameFlags = [.doNotQueue]) async throws -> RequestNameResult {

        let reply = try await callBus("RequestName",
                                      arguments: [.string(name.rawValue), .uint32(flags.rawValue)])

        guard case let .uint32(rawValue)? = reply.first,
            let result = RequestNameResult(rawValue: rawValue)
            else { throw DBusProtocolError.invalidValue("Unexpected RequestName reply \(reply)") }

        return result
    }

    /// Give up a well known name.
    @discardableResult
    func releaseName(_ name: DBusBusName) async throws -> ReleaseNameResult {

        let reply = try await callBus("ReleaseName", arguments: [.string(name.rawValue)])

        guard case let .uint32(rawValue)? = reply.first,
            let result = ReleaseNameResult(rawValue: rawValue)
            else { throw DBusProtocolError.invalidValue("Unexpected ReleaseName reply \(reply)") }

        return result
    }
}

// MARK: - Name Queries

public extension DBusConnection {

    /// Every name currently visible on the bus, unique and well known alike.
    func listNames() async throws -> [String] {

        return try stringArray(from: await callBus("ListNames"), method: "ListNames")
    }

    /// Names that can be activated on demand, whether or not they are currently owned.
    func listActivatableNames() async throws -> [String] {

        return try stringArray(from: await callBus("ListActivatableNames"),
                               method: "ListActivatableNames")
    }

    /// Whether the given name currently has an owner.
    func nameHasOwner(_ name: DBusBusName) async throws -> Bool {

        let reply = try await callBus("NameHasOwner", arguments: [.string(name.rawValue)])

        guard case let .boolean(value)? = reply.first
            else { throw DBusProtocolError.invalidValue("Unexpected NameHasOwner reply \(reply)") }

        return value
    }

    /// The unique name of the connection that owns the given name.
    ///
    /// - Throws: `org.freedesktop.DBus.Error.NameHasNoOwner` if the name is unowned.
    func getNameOwner(_ name: DBusBusName) async throws -> DBusBusName {

        let reply = try await callBus("GetNameOwner", arguments: [.string(name.rawValue)])

        guard case let .string(value)? = reply.first,
            let busName = DBusBusName(rawValue: value)
            else { throw DBusProtocolError.invalidValue("Unexpected GetNameOwner reply \(reply)") }

        return busName
    }

    /// The well known names owned by the given connection.
    func listQueuedOwners(_ name: DBusBusName) async throws -> [String] {

        return try stringArray(from: await callBus("ListQueuedOwners",
                                                   arguments: [.string(name.rawValue)]),
                               method: "ListQueuedOwners")
    }

    /// The Unix user ID of the connection owning the given name.
    func getConnectionUnixUser(_ name: DBusBusName) async throws -> UInt32 {

        let reply = try await callBus("GetConnectionUnixUser", arguments: [.string(name.rawValue)])

        guard case let .uint32(value)? = reply.first
            else { throw DBusProtocolError.invalidValue("Unexpected GetConnectionUnixUser reply \(reply)") }

        return value
    }

    /// The process ID of the connection owning the given name.
    func getConnectionUnixProcessID(_ name: DBusBusName) async throws -> UInt32 {

        let reply = try await callBus("GetConnectionUnixProcessID", arguments: [.string(name.rawValue)])

        guard case let .uint32(value)? = reply.first
            else { throw DBusProtocolError.invalidValue("Unexpected GetConnectionUnixProcessID reply \(reply)") }

        return value
    }

    /// The unique ID of the bus.
    func getBusID() async throws -> String {

        let reply = try await callBus("GetId")

        guard case let .string(value)? = reply.first
            else { throw DBusProtocolError.invalidValue("Unexpected GetId reply \(reply)") }

        return value
    }

    /// Start a service by name, if the bus is configured to activate it.
    @discardableResult
    func startServiceByName(_ name: DBusBusName, flags: UInt32 = 0) async throws -> UInt32 {

        let reply = try await callBus("StartServiceByName",
                                      arguments: [.string(name.rawValue), .uint32(flags)])

        guard case let .uint32(value)? = reply.first
            else { throw DBusProtocolError.invalidValue("Unexpected StartServiceByName reply \(reply)") }

        return value
    }

    private func stringArray(from reply: [DBusMessageArgument],
                             method: String) throws -> [String] {

        guard case let .array(array)? = reply.first
            else { throw DBusProtocolError.invalidValue("Unexpected \(method) reply \(reply)") }

        return try array.map {
            guard case let .string(value) = $0
                else { throw DBusProtocolError.invalidValue("\(method) returned a non-string element") }
            return value
        }
    }
}

// MARK: - Standard Interfaces

public extension DBusConnection {

    /// Call `org.freedesktop.DBus.Peer.Ping` on a remote object.
    func ping(destination: DBusBusName,
              path: DBusObjectPath = DBusObjectPath()) async throws {

        try await callMethod(destination: destination,
                             path: path,
                             interface: DBusWellKnown.peerInterface,
                             method: DBusMember("Ping"))
    }

    /// Call `org.freedesktop.DBus.Introspectable.Introspect` and return the XML.
    func introspect(destination: DBusBusName,
                    path: DBusObjectPath) async throws -> String {

        let reply = try await callMethod(destination: destination,
                                         path: path,
                                         interface: DBusWellKnown.introspectableInterface,
                                         method: DBusMember("Introspect"))

        guard case let .string(xml)? = reply.first
            else { throw DBusProtocolError.invalidValue("Introspect did not return a string") }

        return xml
    }

    /// Call `org.freedesktop.DBus.Properties.Get`, returning the value inside the variant.
    func getProperty(destination: DBusBusName,
                     path: DBusObjectPath,
                     interface: DBusInterface,
                     name: String) async throws -> DBusMessageArgument {

        let reply = try await callMethod(destination: destination,
                                         path: path,
                                         interface: DBusWellKnown.propertiesInterface,
                                         method: DBusMember("Get"),
                                         arguments: [.string(interface.rawValue), .string(name)])

        guard let value = reply.first?.variantValue
            else { throw DBusProtocolError.invalidValue("Get did not return a variant") }

        return value
    }

    /// Call `org.freedesktop.DBus.Properties.Set`.
    func setProperty(destination: DBusBusName,
                     path: DBusObjectPath,
                     interface: DBusInterface,
                     name: String,
                     value: DBusMessageArgument) async throws {

        try await callMethod(destination: destination,
                             path: path,
                             interface: DBusWellKnown.propertiesInterface,
                             method: DBusMember("Set"),
                             arguments: [
                                .string(interface.rawValue),
                                .string(name),
                                .variant(DBusMessageArgument.Variant(value))
                             ])
    }

    /// Call `org.freedesktop.DBus.Properties.GetAll`, unwrapping each variant.
    func getAllProperties(destination: DBusBusName,
                          path: DBusObjectPath,
                          interface: DBusInterface) async throws -> [String: DBusMessageArgument] {

        let reply = try await callMethod(destination: destination,
                                         path: path,
                                         interface: DBusWellKnown.propertiesInterface,
                                         method: DBusMember("GetAll"),
                                         arguments: [.string(interface.rawValue)])

        guard case let .dictionary(dictionary)? = reply.first
            else { throw DBusProtocolError.invalidValue("GetAll did not return a dictionary") }

        var properties = [String: DBusMessageArgument]()

        for entry in dictionary {

            guard case let .string(key) = entry.key,
                let value = entry.value.variantValue
                else { throw DBusProtocolError.invalidValue("GetAll returned an unexpected entry") }

            properties[key] = value
        }

        return properties
    }
}
