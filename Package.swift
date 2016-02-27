import PackageDescription

let package = Package(
    name: "DBus",
    dependencies: [
        .Package(url: "https://github.com/PureSwift/CDBus.git", majorVersion: 1),
    ]
)