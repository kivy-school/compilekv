// swift-tools-version: 6.2
import PackageDescription

/// Build against the SwiftyKvLang checkout next door instead of GitHub.
/// Flip to true while changing the parser and the generator together;
/// flip back before committing, since CI only has this repository.
let useLocalSwiftyKvLang = true

let swiftyKvLang: Package.Dependency = useLocalSwiftyKvLang
    ? .package(path: "../../SwiftyKvLang")
    : .package(url: "https://github.com/Py-Swift/SwiftyKvLang.git", branch: "master")

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
        // SwiftyKvLang parser, from GitHub or the local checkout (see above)
        swiftyKvLang,
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
