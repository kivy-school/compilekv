// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CompileKvWasm",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "CompileKvWasm",
            targets: ["CompileKvWasm"]
        )
    ],
    dependencies: [
        .package(path: "../KvToPyClass")
    ],
    targets: [
        .executableTarget(
            name: "CompileKvWasm",
            dependencies: [
                .product(name: "KvToPyClass", package: "KvToPyClass")
            ],
            path: "Sources/CompileKvWasm"
        )
    ]
)
