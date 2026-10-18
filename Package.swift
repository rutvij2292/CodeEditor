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
        .package(path: "Vendor/tree-sitter-typescript"),
        .package(path: "Vendor/tree-sitter-tsx"),
        .package(path: "Vendor/tree-sitter-blade"),
        .package(path: "Vendor/tree-sitter-markdown"),
        .package(path: "Vendor/tree-sitter-markdown-inline"),
        .package(path: "Vendor/tree-sitter-yaml"),
        .package(path: "Vendor/tree-sitter-bash"),
        .package(path: "Vendor/tree-sitter-xml"),
        .package(path: "Vendor/tree-sitter-scss"),
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
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterTSX", package: "tree-sitter-tsx"),
                .product(name: "TreeSitterBlade", package: "tree-sitter-blade"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
                .product(name: "TreeSitterMarkdownInline", package: "tree-sitter-markdown-inline"),
                .product(name: "TreeSitterYAML", package: "tree-sitter-yaml"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterXML", package: "tree-sitter-xml"),
                .product(name: "TreeSitterSCSS", package: "tree-sitter-scss"),
            ]
        ),
    ]
)
