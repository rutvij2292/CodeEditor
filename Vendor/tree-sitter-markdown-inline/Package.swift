// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TreeSitterMarkdownInline",
    products: [.library(name: "TreeSitterMarkdownInline", targets: ["TreeSitterMarkdownInline"])],
    targets: [
        .target(
            name: "TreeSitterMarkdownInline",
            path: ".",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        )
    ]
)
