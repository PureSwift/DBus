// swift-tools-version:6.4
import PackageDescription
#if canImport(FoundationEssentials)
import class FoundationEssentials.ProcessInfo
#else
import class Foundation.ProcessInfo
#endif

// force building as dynamic library
let dynamicLibrary = ProcessInfo.processInfo.environment["SWIFT_BUILD_DYNAMIC_LIBRARY"] != nil
let libraryType: PackageDescription.Product.Library.LibraryType? = dynamicLibrary ? .dynamic : nil

let package = Package(
    name: "DBus",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "DBus",
            type: libraryType,
            targets: ["DBus"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/PureSwift/Socket.git",
            from: "0.7.0"
        )
    ],
    targets: [
        .target(
            name: "DBus",
            dependencies: [
                "Socket"
            ]
        ),
        .testTarget(
            name: "DBusTests",
            dependencies: [
                "DBus"
            ]
        )
    ]
)

// Standard service clients are separate products so consumers choose their domains.
let services = ["BlueZ", "NetworkManager", "UPower", "Login1", "ScreenSaver",
                "Avahi", "SecretService", "DesktopNotifications", "StatusNotifier",
                "FreedesktopPortal", "MPRIS", "Polkit", "UDisks2"]
for service in services {
    package.products.append(.library(name: service, type: libraryType, targets: [service]))
    package.targets.append(.target(name: service, dependencies: ["DBus"]))
}
package.targets.append(.testTarget(
    name: "ServiceTests",
    dependencies: [.byName(name: "DBus")] + services.map { .byName(name: $0) }
))

// The libdbus-1 C ABI, built only when `SWIFTPM_DBUS_CABI=1`.
//
// Off by default because it exports fixed C symbol names: linking it into a
// process that also links the real libdbus-1 is a duplicate symbol error, and
// a Swift package that merely depends on `DBus` should never be exposed to
// that. `CMakeLists.txt`, which builds the installable shared library, always
// sets it.
if ProcessInfo.processInfo.environment["SWIFTPM_DBUS_CABI"] == "1" {

    package.products.append(
        .library(
            name: "DBusABI",
            type: libraryType,
            targets: ["DBusABI"]
        )
    )

    package.targets.append(contentsOf: [
        .target(
            name: "CDBusABI"
        ),
        .target(
            name: "DBusABI",
            dependencies: [
                "DBus",
                "CDBusABI"
            ]
        ),
        .testTarget(
            name: "DBusABITests",
            dependencies: [
                "DBusABI",
                "CDBusABI"
            ]
        )
    ])
}
