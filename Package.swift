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
            url: "https://github.com/calmdocs/vero/releases/download/v0.5.0/CVero.xcframework.zip",
            checksum: "3c1a3f332a9eda2b1769be6c8c9e4f3ee4bdc257106afec1cef35ddd20f9d1b7"
        ),
        .target(name: "Vero", dependencies: ["CVero"]),
    ]
)
