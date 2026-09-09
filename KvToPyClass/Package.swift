// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KvToPyClass",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "KvToPyClass",
            targets: ["KvToPyClass"]
        ),
        .executable(
            name: "KvToPyClassCLI",
            targets: ["KvToPyClassCLI"]
        )
    ],
    dependencies: [
        // Local dependency on SwiftyKvLang parser
        .package(url: "https://github.com/kivy-school/SwiftyKvLang.git", exact: "0.0.0"),
        // PySwiftAST for generating Python code
        .package(url: "https://github.com/Py-Swift/PySwiftAST.git", exact: "0.0.1")
    ],
    targets: [
        .target(
            name: "KvToPyClass",
            dependencies: [
                .product(name: "KivyWidgetRegistry", package: "SwiftyKvLang"),
                .product(name: "KvParser", package: "SwiftyKvLang"),
                .product(name: "PySwiftAST", package: "PySwiftAST"),
                .product(name: "PySwiftCodeGen", package: "PySwiftAST"),
                .product(name: "PyFormatters", package: "PySwiftAST")
            ],
            path: "Sources/KvToPyClass"
        ),
        .executableTarget(
            name: "KvToPyClassCLI",
            dependencies: [
                "KvToPyClass",
                .product(name: "KivyWidgetRegistry", package: "SwiftyKvLang")
            ],
            path: "Sources/KvToPyClassCLI"
        ),
        .testTarget(
            name: "KvToPyClassTests",
            dependencies: [
                "KvToPyClass",
                .product(name: "KivyWidgetRegistry", package: "SwiftyKvLang")
            ],
            path: "Tests/KvToPyClassTests"
        )
    ]
)
