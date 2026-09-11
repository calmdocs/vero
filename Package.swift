// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vero",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "Vero", targets: ["Vero"]),
    ],
    targets: [
        // The C archive built from ./cshim, which is the same for every
        // application: the worker's path arrives at runtime and every message
        // is JSON.
        //
        // On main this is only the declarations, and the application links the
        // archive itself.  scripts/release.sh replaces this with a binaryTarget
        // pointing at the release's CVero.xcframework.zip, so a tagged version
        // carries the archive with it and nobody has to build one.
        .binaryTarget(
            name: "CVero",
            url: "https://github.com/calmdocs/vero/releases/download/v0.7.3/CVero.xcframework.zip",
            checksum: "74172e8fb54d7c18a9af96876c55ff6695f4213f5926c07620a9967341df53c8"
        ),
        .target(name: "Vero", dependencies: ["CVero"]),
    ]
)
