// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ChuannongCore", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "ChuannongCore", targets: ["ChuannongCore"])], targets: [.target(name: "ChuannongCore"), .testTarget(name: "ChuannongCoreTests", dependencies: ["ChuannongCore"])])
