//
//  IntrospectionNode.swift
//  DBus
//

// MARK: - Model

public extension DBusIntrospection {

    /// An object node described by an introspection document.
    struct Node: Equatable, Hashable, Sendable {

        /// The node's name, when the document gives one.
        ///
        /// The root node of a reply usually has none, because the path is already known; child
        /// nodes carry a relative name.
        public var name: String?

        /// The interfaces the object implements.
        public var interfaces: [Interface]

        /// Child nodes. Usually name-only stubs, to be introspected in turn.
        public var children: [Node]

        public init(name: String? = nil,
                    interfaces: [Interface] = [],
                    children: [Node] = []) {

            self.name = name
            self.interfaces = interfaces
            self.children = children
        }
    }

    /// An interface described by an introspection document.
    struct Interface: Equatable, Hashable, Sendable {

        public var name: DBusInterface
        public var methods: [Method]
        public var signals: [Signal]
        public var properties: [Property]

        public init(name: DBusInterface,
                    methods: [Method] = [],
                    signals: [Signal] = [],
                    properties: [Property] = []) {

            self.name = name
            self.methods = methods
            self.signals = signals
            self.properties = properties
        }
    }

    /// A method described by an introspection document.
    struct Method: Equatable, Hashable, Sendable {

        public var name: DBusMember
        public var arguments: [Argument]

        public init(name: DBusMember, arguments: [Argument] = []) {

            self.name = name
            self.arguments = arguments
        }

        /// The signature of the arguments the method accepts.
        public var inputSignature: DBusSignature {
            DBusSignature(arguments.filter { $0.direction == .in }.map { $0.type })
        }

        /// The signature of the values the method returns.
        public var outputSignature: DBusSignature {
            DBusSignature(arguments.filter { $0.direction == .out }.map { $0.type })
        }
    }

    /// A signal described by an introspection document.
    struct Signal: Equatable, Hashable, Sendable {

        public var name: DBusMember
        public var arguments: [Argument]

        public init(name: DBusMember, arguments: [Argument] = []) {

            self.name = name
            self.arguments = arguments
        }

        /// The signature of the signal's arguments.
        public var signature: DBusSignature {
            DBusSignature(arguments.map { $0.type })
        }
    }

    /// A property described by an introspection document.
    struct Property: Equatable, Hashable, Sendable {

        public var name: String
        public var type: DBusSignature.ValueType
        public var access: DBusInterfaceImplementation.Property.Access

        public init(name: String,
                    type: DBusSignature.ValueType,
                    access: DBusInterfaceImplementation.Property.Access) {

            self.name = name
            self.type = type
            self.access = access
        }
    }

    /// An argument of a method or signal.
    struct Argument: Equatable, Hashable, Sendable {

        /// Which way the argument travels.
        public enum Direction: String, Sendable {

            case `in`
            case out
        }

        public var name: String?
        public var type: DBusSignature.ValueType
        public var direction: Direction

        public init(name: String? = nil,
                    type: DBusSignature.ValueType,
                    direction: Direction = .in) {

            self.name = name
            self.type = type
            self.direction = direction
        }
    }
}

// MARK: - Parsing

public extension DBusIntrospection {

    /// Parse an introspection document.
    ///
    /// - Throws: `DBusProtocolError.invalidValue` if the document is malformed, names a type
    /// that is not a valid signature, or uses a name the specification forbids.
    static func parse(_ xml: String) throws -> Node {

        let root = try XMLReader.parse(xml)

        guard root.name == "node"
            else { throw DBusProtocolError.invalidValue("Root element is <\(root.name)>, expected <node>") }

        return try node(from: root)
    }

    private static func node(from element: XMLElement) throws -> Node {

        var node = Node(name: element.attributes["name"])

        for child in element.children {

            switch child.name {

            case "interface":
                node.interfaces.append(try interface(from: child))

            case "node":
                node.children.append(try self.node(from: child))

            case "annotation":
                continue // annotations carry no information this model represents

            default:
                throw DBusProtocolError.invalidValue("Unexpected <\(child.name)> inside <node>")
            }
        }

        return node
    }

    private static func interface(from element: XMLElement) throws -> Interface {

        guard let rawName = element.attributes["name"]
            else { throw DBusProtocolError.invalidValue("<interface> has no name") }

        guard let name = DBusInterface(rawValue: rawName)
            else { throw DBusProtocolError.invalidValue("Invalid interface name '\(rawName)'") }

        var interface = Interface(name: name)

        for child in element.children {

            switch child.name {

            case "method":
                interface.methods.append(Method(name: try member(of: child),
                                                arguments: try arguments(of: child, defaultDirection: .in)))

            case "signal":
                // A signal's arguments are always outbound and carry no direction attribute.
                interface.signals.append(Signal(name: try member(of: child),
                                                arguments: try arguments(of: child, defaultDirection: .out)))

            case "property":
                interface.properties.append(try property(from: child))

            case "annotation":
                continue

            default:
                throw DBusProtocolError.invalidValue("Unexpected <\(child.name)> inside <interface>")
            }
        }

        return interface
    }

    private static func member(of element: XMLElement) throws -> DBusMember {

        guard let rawName = element.attributes["name"]
            else { throw DBusProtocolError.invalidValue("<\(element.name)> has no name") }

        guard let member = DBusMember(rawValue: rawName)
            else { throw DBusProtocolError.invalidValue("Invalid member name '\(rawName)'") }

        return member
    }

    private static func arguments(of element: XMLElement,
                                  defaultDirection: Argument.Direction) throws -> [Argument] {

        return try element.children(named: "arg").map { child in

            guard let rawType = child.attributes["type"]
                else { throw DBusProtocolError.invalidValue("<arg> has no type") }

            guard let signature = DBusSignature(rawValue: rawType), signature.count == 1
                else { throw DBusProtocolError.invalidValue("<arg> type '\(rawType)' is not a single complete type") }

            let direction: Argument.Direction

            if let rawDirection = child.attributes["direction"] {
                guard let parsed = Argument.Direction(rawValue: rawDirection)
                    else { throw DBusProtocolError.invalidValue("Invalid argument direction '\(rawDirection)'") }
                direction = parsed
            } else {
                direction = defaultDirection
            }

            return Argument(name: child.attributes["name"], type: signature[0], direction: direction)
        }
    }

    private static func property(from element: XMLElement) throws -> Property {

        guard let name = element.attributes["name"]
            else { throw DBusProtocolError.invalidValue("<property> has no name") }

        guard let rawType = element.attributes["type"]
            else { throw DBusProtocolError.invalidValue("<property> '\(name)' has no type") }

        guard let signature = DBusSignature(rawValue: rawType), signature.count == 1
            else { throw DBusProtocolError.invalidValue("<property> type '\(rawType)' is not a single complete type") }

        guard let rawAccess = element.attributes["access"]
            else { throw DBusProtocolError.invalidValue("<property> '\(name)' has no access") }

        guard let access = DBusInterfaceImplementation.Property.Access(rawValue: rawAccess)
            else { throw DBusProtocolError.invalidValue("Invalid property access '\(rawAccess)'") }

        return Property(name: name, type: signature[0], access: access)
    }
}

// MARK: - Lookup

public extension DBusIntrospection.Node {

    /// The interface with the given name, if the object implements it.
    func interface(named name: DBusInterface) -> DBusIntrospection.Interface? {

        return interfaces.first { $0.name == name }
    }

    /// Whether the object implements the interface.
    func implements(_ name: DBusInterface) -> Bool {

        return interface(named: name) != nil
    }
}

public extension DBusIntrospection.Interface {

    /// The method with the given name, if the interface declares it.
    func method(named name: DBusMember) -> DBusIntrospection.Method? {

        return methods.first { $0.name == name }
    }

    /// The signal with the given name, if the interface declares it.
    func signal(named name: DBusMember) -> DBusIntrospection.Signal? {

        return signals.first { $0.name == name }
    }

    /// The property with the given name, if the interface declares it.
    func property(named name: String) -> DBusIntrospection.Property? {

        return properties.first { $0.name == name }
    }
}

// MARK: - Connection

public extension DBusConnection {

    /// Call `Introspect` on a remote object and parse the result.
    func introspectNode(destination: DBusBusName,
                        path: DBusObjectPath) async throws -> DBusIntrospection.Node {

        let xml = try await introspect(destination: destination, path: path)

        return try DBusIntrospection.parse(xml)
    }
}
