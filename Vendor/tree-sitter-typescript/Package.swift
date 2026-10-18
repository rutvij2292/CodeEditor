// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TreeSitterTypeScript",
    products: [.library(name: "TreeSitterTypeScript", targets: ["TreeSitterTypeScript"])],
    targets: [
        .target(
            name: "TreeSitterTypeScript",
            path: ".",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        )
    ]
)
