// swift-tools-version:4.1
import PackageDescription

let package = Package(
    name: "DBus",
    products: [
        .library(
            name: "DBus",
            targets: [
                "DBus"
            ]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/PureSwift/CDBus.git",
            .branch("master")
        )
    ],
    targets: [
        .target(
            name: "DBus",
            dependencies: [
                //"CDBus"
            ]
        ),
        .testTarget(
            name: "DBusTests",
            dependencies: [
                "DBus"
            ]
        )
        ],
    swiftLanguageVersions: [5]
)
