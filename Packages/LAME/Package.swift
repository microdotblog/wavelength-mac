// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "LAME",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "LAME", targets: ["LAME"]),
  ],
  targets: [
    .target(
      name: "LAME",
      cSettings: [
        .headerSearchPath("."),
        .define("HAVE_CONFIG_H"),
        .define("STDC_HEADERS"),
        .define("HAVE_MEMCPY"),
        .define("HAVE_STRCHR"),
        .unsafeFlags(["-w"]),
      ]
    ),
  ]
)
