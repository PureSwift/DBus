//
//  IntrospectionParsingTests.swift
//  DBusTests
//

import Testing
@testable import DBus

@Suite struct XMLReaderTests {

    @Test func parsesElementsAndAttributes() throws {

        let element = try XMLReader.parse("""
            <node name="thing">
              <interface name="com.example.A">
                <method name="Do"/>
              </interface>
            </node>
            """)

        #expect(element.name == "node")
        #expect(element.attributes["name"] == "thing")
        #expect(element.children.count == 1)
        #expect(element.children[0].name == "interface")
        #expect(element.children[0].children(named: "method").count == 1)
    }

    @Test func skipsDeclarationDoctypeAndComments() throws {

        let element = try XMLReader.parse("""
            <?xml version="1.0"?>
            <!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
             "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
            <!-- a comment with <angle> brackets -->
            <node>
              <!-- another -->
              <node name="child"/>
            </node>
            """)

        #expect(element.name == "node")
        #expect(element.children.count == 1)
        #expect(element.children[0].attributes["name"] == "child")
    }

    /// A doctype may carry an internal subset in brackets containing '>'.
    @Test func skipsDoctypeInternalSubset() throws {

        let element = try XMLReader.parse("""
            <!DOCTYPE node [ <!ELEMENT node (interface*)> ]>
            <node name="x"/>
            """)

        #expect(element.attributes["name"] == "x")
    }

    @Test func decodesEntities() throws {

        let element = try XMLReader.parse(
            #"<node name="a&lt;b&gt;c&amp;d&quot;e&apos;f&#65;&#x42;"/>"#
        )

        #expect(element.attributes["name"] == "a<b>c&d\"e'fAB")
    }

    @Test func acceptsSingleQuotedAttributes() throws {

        let element = try XMLReader.parse("<node name='thing'/>")

        #expect(element.attributes["name"] == "thing")
    }

    @Test(arguments: [
        "",                              // no root
        "<node>",                        // unterminated
        "<node></other>",                // mismatched close
        "<node name=thing/>",            // unquoted attribute
        "<node name/>",                  // attribute without a value
        "<node/><node/>",                // two roots
        #"<node name="a&bogus;"/>"#,     // unknown entity
        #"<node name="unterminated/>"#,  // unterminated attribute value
        "<node name=\"a\" name=\"b\"/>"  // duplicate attribute
    ])
    func rejectsMalformedDocument(xml: String) {

        #expect(throws: (any Error).self, "\(xml) should be rejected") {
            try XMLReader.parse(xml)
        }
    }
}

// MARK: - Introspection model

@Suite struct IntrospectionParsingTests {

    private let testInterface = DBusInterface(rawValue: "com.example.TestObject")!

    @Test func parsesInterfacesMethodsSignalsAndProperties() throws {

        let node = try DBusIntrospection.parse("""
            <!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
             "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
            <node>
              <interface name="com.example.TestObject">
                <method name="Echo">
                  <arg name="input" type="s" direction="in"/>
                  <arg name="output" type="s" direction="out"/>
                </method>
                <method name="Reset"/>
                <signal name="Bounced">
                  <arg name="text" type="s"/>
                </signal>
                <property name="Greeting" type="s" access="readwrite"/>
                <property name="Counter" type="u" access="read"/>
              </interface>
              <node name="child"/>
            </node>
            """)

        #expect(node.name == nil, "The root node of a reply carries no name")
        #expect(node.interfaces.count == 1)

        let interface = try #require(node.interface(named: testInterface))
        #expect(node.implements(testInterface))

        let echo = try #require(interface.method(named: DBusMember(rawValue: "Echo")!))
        #expect(echo.inputSignature.rawValue == "s")
        #expect(echo.outputSignature.rawValue == "s")
        #expect(echo.arguments.first?.name == "input")

        let reset = try #require(interface.method(named: DBusMember(rawValue: "Reset")!))
        #expect(reset.arguments.isEmpty)

        // Signal arguments have no direction attribute and are outbound.
        let bounced = try #require(interface.signal(named: DBusMember(rawValue: "Bounced")!))
        #expect(bounced.signature.rawValue == "s")
        #expect(bounced.arguments.first?.direction == .out)

        #expect(interface.property(named: "Greeting")?.access == .readwrite)
        #expect(interface.property(named: "Counter")?.type == .uint32)

        #expect(node.children.count == 1)
        #expect(node.children[0].name == "child")
    }

    /// A method argument with no direction defaults to `in`, per the specification.
    @Test func defaultsMethodArgumentDirectionToIn() throws {

        let node = try DBusIntrospection.parse("""
            <node>
              <interface name="com.example.A">
                <method name="Do"><arg type="s"/></method>
              </interface>
            </node>
            """)

        let method = try #require(node.interfaces.first?.methods.first)
        #expect(method.arguments.first?.direction == .in)
        #expect(method.inputSignature.rawValue == "s")
        #expect(method.outputSignature.rawValue == "")
    }

    @Test func ignoresAnnotations() throws {

        let node = try DBusIntrospection.parse("""
            <node>
              <annotation name="org.freedesktop.DBus.Deprecated" value="true"/>
              <interface name="com.example.A">
                <annotation name="org.freedesktop.DBus.Deprecated" value="true"/>
                <method name="Do"/>
              </interface>
            </node>
            """)

        #expect(node.interfaces.count == 1)
        #expect(node.interfaces[0].methods.count == 1)
    }

    @Test func parsesComplexTypes() throws {

        let node = try DBusIntrospection.parse("""
            <node>
              <interface name="com.example.A">
                <method name="Do">
                  <arg type="a{sv}" direction="in"/>
                  <arg type="a(is)" direction="out"/>
                </method>
                <property name="Nested" type="aa{sv}" access="read"/>
              </interface>
            </node>
            """)

        let method = try #require(node.interfaces.first?.methods.first)
        #expect(method.inputSignature.rawValue == "a{sv}")
        #expect(method.outputSignature.rawValue == "a(is)")

        #expect(node.interfaces.first?.properties.first?.type == .array(.dictionary(
            DBusSignature.DictionaryType(key: .string, value: .variant)!
        )))
    }

    @Test(arguments: [
        "<node><interface/></node>",                                    // no name
        "<node><interface name=\"nodots\"><method name=\"D\"/></interface></node>",
        "<node><interface name=\"com.example.A\"><method/></interface></node>",
        "<node><interface name=\"com.example.A\"><method name=\"1Bad\"/></interface></node>",
        "<node><interface name=\"com.example.A\"><method name=\"D\"><arg/></method></interface></node>",
        "<node><interface name=\"com.example.A\"><method name=\"D\"><arg type=\"zz\"/></method></interface></node>",
        "<node><interface name=\"com.example.A\"><method name=\"D\"><arg type=\"ss\"/></method></interface></node>",
        "<node><interface name=\"com.example.A\"><method name=\"D\"><arg type=\"s\" direction=\"sideways\"/></method></interface></node>",
        "<node><interface name=\"com.example.A\"><property name=\"P\" type=\"s\"/></interface></node>",
        "<node><interface name=\"com.example.A\"><property name=\"P\" type=\"s\" access=\"maybe\"/></interface></node>",
        "<node><unexpected/></node>",
        "<other/>"
    ])
    func rejectsInvalidDocument(xml: String) {

        #expect(throws: (any Error).self, "\(xml) should be rejected") {
            try DBusIntrospection.parse(xml)
        }
    }

    /// What the generator writes must be what the parser reads back.
    @Test func roundTripsGeneratedDocument() throws {

        let implementation = DBusInterfaceImplementation(
            name: testInterface,
            methods: [
                .init(name: DBusMember(rawValue: "Echo")!,
                      inputSignature: DBusSignature(rawValue: "s")!,
                      outputSignature: DBusSignature(rawValue: "a{sv}")!,
                      inputNames: ["input"],
                      outputNames: ["output"],
                      handler: { _ in [] }),
                .init(name: DBusMember(rawValue: "Reset")!, handler: { _ in [] })
            ],
            properties: [
                .init(name: "Greeting", type: .string, access: .readwrite,
                      get: { .string("") }, set: { _ in }),
                .init(name: "Counter", type: .uint32, access: .read, get: { .uint32(0) })
            ],
            signals: [
                .init(name: DBusMember(rawValue: "Bounced")!,
                      signature: DBusSignature(rawValue: "su")!,
                      argumentNames: ["text", "count"])
            ]
        )

        let xml = DBusIntrospection.xml(for: DBusExportedObject([implementation]),
                                        children: ["child", "other"])

        let node = try DBusIntrospection.parse(xml)

        // The standard interfaces are advertised too.
        #expect(node.implements(DBusWellKnown.peerInterface))
        #expect(node.implements(DBusWellKnown.introspectableInterface))
        #expect(node.implements(DBusWellKnown.propertiesInterface))

        let parsed = try #require(node.interface(named: testInterface))

        let echo = try #require(parsed.method(named: DBusMember(rawValue: "Echo")!))
        #expect(echo.inputSignature.rawValue == "s")
        #expect(echo.outputSignature.rawValue == "a{sv}")
        #expect(echo.arguments.map { $0.name } == ["input", "output"])

        #expect(parsed.method(named: DBusMember(rawValue: "Reset")!)?.arguments.isEmpty == true)

        let bounced = try #require(parsed.signal(named: DBusMember(rawValue: "Bounced")!))
        #expect(bounced.signature.rawValue == "su")
        #expect(bounced.arguments.allSatisfy { $0.direction == .out })

        #expect(parsed.property(named: "Greeting")?.access == .readwrite)
        #expect(parsed.property(named: "Counter")?.type == .uint32)

        #expect(node.children.map { $0.name } == ["child", "other"])
    }

    /// Names needing escaping must survive generation and parsing intact.
    @Test func roundTripsEscapedNames() throws {

        let implementation = DBusInterfaceImplementation(
            name: testInterface,
            properties: [
                .init(name: "Quote\"And<Angle>&Amp", type: .string, access: .read,
                      get: { .string("") })
            ]
        )

        let xml = DBusIntrospection.xml(for: DBusExportedObject([implementation]))
        let node = try DBusIntrospection.parse(xml)

        #expect(node.interface(named: testInterface)?.properties.first?.name
                == "Quote\"And<Angle>&Amp")
    }
}

// MARK: - Live

@Suite(.serialized, .enabled(if: hasSessionBus, "No session bus is available"))
struct IntrospectionLiveTests {

    /// The bus daemon's own document, produced by the reference implementation.
    @Test func parsesBusDaemonIntrospection() async throws {

        try await withConnection { connection in

            let node = try await connection.introspectNode(destination: DBusWellKnown.busName,
                                                           path: DBusWellKnown.busPath)

            #expect(node.implements(DBusWellKnown.busInterface))
            #expect(node.implements(DBusWellKnown.introspectableInterface))

            let bus = try #require(node.interface(named: DBusWellKnown.busInterface))

            let hello = try #require(bus.method(named: DBusMember(rawValue: "Hello")!))
            #expect(hello.inputSignature.rawValue == "")
            #expect(hello.outputSignature.rawValue == "s")

            let listNames = try #require(bus.method(named: DBusMember(rawValue: "ListNames")!))
            #expect(listNames.outputSignature.rawValue == "as")

            #expect(bus.signal(named: DBusMember(rawValue: "NameOwnerChanged")!) != nil)
        }
    }

    /// Our own generated document, read back over the bus by the parser.
    @Test func parsesOwnIntrospectionOverTheBus() async throws {

        let path = DBusObjectPath(rawValue: "/com/example/Introspected")!
        let interface = DBusInterface(rawValue: "com.example.Introspected")!

        try await withConnections { server, client in

            let implementation = DBusInterfaceImplementation(
                name: interface,
                methods: [
                    .init(name: DBusMember(rawValue: "Combine")!,
                          inputSignature: DBusSignature(rawValue: "si")!,
                          outputSignature: DBusSignature(rawValue: "s")!,
                          inputNames: ["text", "count"],
                          outputNames: ["result"],
                          handler: { _ in [] })
                ],
                properties: [
                    .init(name: "Enabled", type: .boolean, access: .readwrite,
                          get: { .boolean(true) }, set: { _ in })
                ]
            )

            await server.export(DBusExportedObject([implementation]), at: path)

            let name = try #require(await server.uniqueName)

            let node = try await client.introspectNode(destination: name, path: path)

            let parsed = try #require(node.interface(named: interface))
            let combine = try #require(parsed.method(named: DBusMember(rawValue: "Combine")!))

            #expect(combine.inputSignature.rawValue == "si")
            #expect(combine.outputSignature.rawValue == "s")
            #expect(combine.arguments.map { $0.name } == ["text", "count", "result"])
            #expect(parsed.property(named: "Enabled")?.access == .readwrite)
        }
    }
}
