// swift-tools-version: 6.0

import Foundation
import PackageDescription

// Deliberately a *separate* package from the root NeedleFoundation manifest: it
// carries ~12 MB of generated sources, and nobody building or testing Needle
// should pay for that.
//
// Which NeedleFoundation it links is picked by the NEEDLE_SOURCE environment
// variable, so the exact same benchmark sources run against both:
//
//   NEEDLE_SOURCE=upstream  uber/needle 0.25.1 from GitHub
//   NEEDLE_SOURCE=fork      this repository (default)
//
// run.sh builds each mode into its own --scratch-path so both stay cached.
let useUpstream = ProcessInfo.processInfo.environment["NEEDLE_SOURCE"] == "upstream"

let needle: Package.Dependency = useUpstream
    ? .package(url: "https://github.com/uber/needle.git", exact: "0.25.1")
    : .package(path: "../..")
let needleIdentity = useUpstream ? "needle" : "needle-fork"

let package = Package(
    name: "SharedProtocolsBench",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [needle],
    targets: [
        // 10 000 protocol/class pairs. No DI dependency, so this is the expensive
        // half of the build and does not depend on which Needle is linked.
        //
        // Always compiled unoptimised, even under `-c release`: optimising (and
        // whole-module-compiling) 10 000 classes is what makes a release build
        // take ~20 minutes, and it buys nothing — the effect under test lives in
        // the conformance records this module emits, which are the same at any
        // optimisation level. The flags come after SwiftPM's `-O -wmo`, so they win.
        .target(
            name: "BenchModels",
            path: "Sources/BenchModels",
            swiftSettings: [.unsafeFlags(["-Onone", "-no-whole-module-optimization"])]
        ),
        .executableTarget(
            name: "BenchNeedle",
            dependencies: [
                "BenchModels",
                .product(name: "NeedleFoundation", package: needleIdentity)
            ],
            path: "Sources/BenchNeedle"
        )
    ],
    swiftLanguageModes: [.v5]
)
