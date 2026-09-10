// swift-tools-version:6.0
//
// Two library targets so the whole app compiles and tests on a Mac with only
// the command line tools installed:
//
//   DcalKit - the model and all the layout maths. Pure Foundation and
//             CoreGraphics, no UI, so every geometry decision can be tested
//             directly instead of by looking at a screenshot.
//   DcalUI  - the SwiftUI app. UIKit-only pieces (the gesture recogniser
//             layer) sit behind #if os(iOS), so `swift build` still
//             type-checks the interface on a Mac.
//
// The iOS app target itself is a shell that imports DcalUI - see project.yml.

import PackageDescription

let package = Package(
    name: "Dcal",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DcalKit", targets: ["DcalKit"]),
        .library(name: "DcalUI", targets: ["DcalUI"]),
    ],
    targets: [
        .target(
            name: "DcalKit",
            path: "DcalKit/Sources/DcalKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "DcalUI",
            dependencies: ["DcalKit"],
            path: "DcalUI/Sources/DcalUI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DcalKitTests",
            dependencies: ["DcalKit"],
            path: "DcalKit/Tests/DcalKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
