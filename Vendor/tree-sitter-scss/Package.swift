// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TreeSitterSCSS",
    products: [.library(name: "TreeSitterSCSS", targets: ["TreeSitterSCSS"])],
    targets: [
        .target(
            name: "TreeSitterSCSS",
            path: ".",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        )
    ]
)
