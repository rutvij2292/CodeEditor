// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TreeSitterXML",
    products: [.library(name: "TreeSitterXML", targets: ["TreeSitterXML"])],
    targets: [
        .target(
            name: "TreeSitterXML",
            path: ".",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [.copy("queries")],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        )
    ]
)
