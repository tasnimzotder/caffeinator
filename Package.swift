// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Caffeinator",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "caffeinator", targets: ["Caffeinator"])],
  targets: [
    .systemLibrary(name: "CSQLite"),
    .target(
      name: "CaffeinatorCore", dependencies: ["CSQLite"],
      linkerSettings: [.linkedFramework("IOKit")]),
    .executableTarget(name: "Caffeinator", dependencies: ["CaffeinatorCore"]),
    .testTarget(name: "CaffeinatorCoreTests", dependencies: ["CaffeinatorCore"]),
  ]
)
