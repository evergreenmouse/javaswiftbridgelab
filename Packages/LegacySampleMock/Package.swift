// swift-tools-version: 6.0
import PackageDescription

// Only the Objective-C SDK mock is packaged; Swift application layers belong to Xcode.
let package = Package(
    name: "LegacySampleMock",
    platforms: [.iOS("26.0")],
    products: [.library(name: "LegacySampleMock", targets: ["LegacySampleMock"])],
    targets: [
        .target(name: "LegacySampleMock", publicHeadersPath: "include",
                cSettings: [.unsafeFlags(["-fobjc-arc"])])
    ]
)
