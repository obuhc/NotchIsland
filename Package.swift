// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchUsageKit", targets: ["NotchUsageKit"]),
        .executable(name: "notch-probe", targets: ["notch-probe"]),
        .executable(name: "NotchIslandApp", targets: ["NotchIslandApp"]),
    ],
    targets: [
        .target(name: "NotchUsageKit"),
        .executableTarget(
            name: "notch-probe",
            dependencies: ["NotchUsageKit"]
        ),
        .executableTarget(
            name: "NotchIslandApp",
            dependencies: ["NotchUsageKit"]
        ),
    ]
)
