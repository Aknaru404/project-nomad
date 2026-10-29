// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZimKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ZimKit", targets: ["ZimKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/facebook/zstd.git", from: "1.5.6"),
    ],
    targets: [
        .target(
            name: "ZimKit",
            dependencies: [.product(name: "libzstd", package: "zstd")]
        ),
        .testTarget(
            name: "ZimKitTests",
            dependencies: ["ZimKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
