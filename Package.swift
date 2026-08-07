// swift-tools-version:6.0
import PackageDescription
import class Foundation.ProcessInfo

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
            branch: "main"
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
