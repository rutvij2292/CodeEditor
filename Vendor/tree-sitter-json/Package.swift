// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TreeSitterJSON",
    products: [.library(name: "TreeSitterJSON", targets: ["TreeSitterJSON"])],
    targets: [
        .target(
            name: "TreeSitterJSON",
            path: ".",
            sources: ["src/parser.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        )
    ]
)
