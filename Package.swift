// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CodeEditor",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-php", from: "0.23.0"),
        .package(path: "Vendor/tree-sitter-javascript"),
        .package(path: "Vendor/tree-sitter-html"),
        .package(path: "Vendor/tree-sitter-css"),
        .package(path: "Vendor/tree-sitter-json"),
    ],
    targets: [
        .executableTarget(
            name: "CodeEditor",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterPHP", package: "tree-sitter-php"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
            ]
        ),
    ]
)
