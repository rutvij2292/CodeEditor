// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TreeSitterBlade",
    products: [.library(name: "TreeSitterBlade", targets: ["TreeSitterBlade"])],
    targets: [
        .target(
            name: "TreeSitterBlade",
            path: ".",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        )
    ]
)
