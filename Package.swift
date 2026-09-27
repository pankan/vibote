// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Vibote", platforms: [.macOS(.v14)], products: [.executable(name: "Vibote", targets: ["Vibote"])], targets: [.executableTarget(name: "Vibote", path: "Sources", swiftSettings: [.swiftLanguageMode(.v5)])])
