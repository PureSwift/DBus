/// A service endpoint on a caller-owned connection. Closing the connection ends subscriptions.
public struct DBusServiceProxy: Sendable {
    public let connection: DBusConnection
    public let destination: DBusBusName
    public let path: DBusObjectPath
    public let interface: DBusInterface

    public init(connection: DBusConnection, destination: String, path: String, interface: String) throws {
        guard let destination = DBusBusName(rawValue: destination),
              let path = DBusObjectPath(rawValue: path),
              let interface = DBusInterface(rawValue: interface) else {
            throw DBusProtocolError.invalidValue("Invalid service endpoint")
        }
        self.connection = connection
        self.destination = destination
        self.path = path
        self.interface = interface
    }

    public func call(_ method: String, arguments: [DBusMessageArgument] = []) async throws -> [DBusMessageArgument] {
        guard let member = DBusMember(rawValue: method) else {
            throw DBusProtocolError.invalidValue("Invalid method name: \(method)")
        }
        return try await connection.callMethod(destination: destination, path: path,
                                                interface: interface, method: member, arguments: arguments)
    }

    public func property(_ name: String) async throws -> DBusMessageArgument {
        try await connection.getProperty(destination: destination, path: path, interface: interface, name: name)
    }

    public func properties() async throws -> [String: DBusMessageArgument] {
        try await connection.getAllProperties(destination: destination, path: path, interface: interface)
    }

    /// Subscribes to this owner's signals. Recreate the subscription if the service restarts.
    public func signals() async throws -> AsyncStream<DBusMessage> {
        let owner = try await connection.getNameOwner(destination)
        return try await connection.signals(interface: interface, path: path, sender: owner)
    }

    public func propertyChanges() async throws -> AsyncStream<DBusMessage> {
        let owner = try await connection.getNameOwner(destination)
        return try await connection.signals(matching: .propertiesChanged(interface: interface, path: path, sender: owner))
    }

    /// Validate the complete reply signature before a wrapper decodes its payload.
    public static func validate(_ reply: [DBusMessageArgument], signature: String) throws {
        let actual = DBusSignature(reply.map(\.type)).rawValue
        guard actual == signature else {
            throw DBusProtocolError.invalidValue("Expected reply \(signature), received \(actual)")
        }
    }
}

/// Common property and signal access shared by generated service clients.
public protocol DBusServiceClient: Sendable {
    var proxy: DBusServiceProxy { get }
}

public extension DBusServiceClient {
    func properties() async throws -> [String: DBusMessageArgument] {
        try await proxy.properties()
    }

    func signals() async throws -> AsyncStream<DBusMessage> {
        try await proxy.signals()
    }

    func propertyChanges() async throws -> AsyncStream<DBusMessage> {
        try await proxy.propertyChanges()
    }
}
