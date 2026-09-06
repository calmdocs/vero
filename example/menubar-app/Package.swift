// swift-tools-version:5.9
import PackageDescription

// libvero.a is built by ./build.sh before this package is compiled. The
// unsafeFlags are how a SwiftPM package links a static archive that is not
// itself a SwiftPM product; an Xcode project would add it under "Link Binary
// With Libraries" instead.
let package = Package(
    name: "MenuBarExample",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "MenuBarExample",
            dependencies: [.product(name: "Vero", package: "vero")],
            linkerSettings: [.unsafeFlags(["-L.", "-lvero"])]
        )
    ]
)
