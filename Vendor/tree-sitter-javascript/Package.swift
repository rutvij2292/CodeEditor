// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TreeSitterJavaScript",
    products: [.library(name: "TreeSitterJavaScript", targets: ["TreeSitterJavaScript"])],
    targets: [
        .target(
            name: "TreeSitterJavaScript",
            path: ".",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        )
    ]
)
