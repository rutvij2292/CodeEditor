// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TreeSitterTSX",
    products: [.library(name: "TreeSitterTSX", targets: ["TreeSitterTSX"])],
    targets: [
        .target(
            name: "TreeSitterTSX",
            path: ".",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        )
    ]
)
