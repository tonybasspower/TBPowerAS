// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "TBPowerAS",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TBPowerAS", targets: ["TBPowerAS"]),
        .executable(name: "tbpower-as-helper", targets: ["tbpower-as-helper"]),
    ],
    targets: [
        // Accesso SMC (lettura temperature/ventole/inibizione carica, scrittura inibizione carica) in C.
        .target(
            name: "CSMC",
            path: "Sources/CSMC",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        // App barra dei menu (gira come utente normale, mai root).
        .executableTarget(
            name: "TBPowerAS",
            dependencies: ["CSMC"],
            path: "Sources/TBPower",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Metal"),
                             .linkedFramework("ServiceManagement")]
        ),
        // Helper root minimale, invocato solo via `sudo -n` (regola NOPASSWD).
        .executableTarget(
            name: "tbpower-as-helper",
            dependencies: ["CSMC"],
            path: "Sources/tbpower-as-helper"
        ),
    ]
)
