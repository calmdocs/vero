// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vero",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "Vero", targets: ["Vero"]),
    ],
    targets: [
        // Declarations for the archive built from ./cshim. The archive itself
        // is linked in by the application, not by this package - see the
        // README for the two lines that do it.
        .target(name: "CVero"),
        .target(name: "Vero", dependencies: ["CVero"]),
    ]
)
