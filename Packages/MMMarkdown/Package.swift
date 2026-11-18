// swift-tools-version: 6.2

import PackageDescription

// Uses the same MIT-licensed Markdown renderer as Micro.blog for Mac.
let package = Package(
  name: "MMMarkdown",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "MMMarkdown", targets: ["MMMarkdown"]),
  ],
  targets: [
    .target(
      name: "MMMarkdown",
      cSettings: [.unsafeFlags(["-fobjc-arc"])],
      linkerSettings: [.linkedFramework("Foundation")]
    ),
  ]
)
