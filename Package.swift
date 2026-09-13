// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ConBarAI",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "conbarai",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/ConBarAI"
        ),
        .testTarget(
            name: "ConBarAITests",
            dependencies: ["conbarai"],
            path: "Tests/ConBarAITests"
        ),
    ]
)
