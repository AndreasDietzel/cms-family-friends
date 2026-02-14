// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CMSFamilyFriends",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CMSFamilyFriends", targets: ["CMSFamilyFriends"])
    ],
    dependencies: [
        // Zukünftige Dependencies hier einfügen
    ],
    targets: [
        .executableTarget(
            name: "CMSFamilyFriends",
            dependencies: [],
            path: "CMSFamilyFriends/Sources",
            resources: [
                .process("../Resources")
            ]
        )
    ]
)
