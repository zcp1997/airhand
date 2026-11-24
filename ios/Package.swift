// swift-tools-version: 6.4
import PackageDescription

// Host tests compile these production files directly, without UIKit or persistent user data.
let package = Package(
    name: "AirhandCoreLogic",
    platforms: [.macOS(.v14), .iOS("16.6")],
    products: [.library(name: "AirhandCoreLogic", targets: ["AirhandCoreLogic"])],
    dependencies: [.package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.12")],
    targets: [
        .target(
            name: "AirhandCoreLogic",
            dependencies: [.product(name: "Perception", package: "swift-perception")],
            path: ".",
            exclude: ["Broadcast", "CoreTests", "Tests", "native", "scripts", "build", "Airhand.xcodeproj",
                      "project.yml", "Shared/HostRunner.swift", "Shared/Native.swift", "Shared/Opus.swift", "Shared/SharedStore.swift",
                      "Airhand/App.swift", "Airhand/Info.plist", "Airhand/Airhand.entitlements", "Airhand/Assets.xcassets", "Airhand/UI", "Airhand/Core/AppModel.swift",
                      "Airhand/Core/ControllerClient.swift", "Airhand/Core/DebugHost.swift", "Airhand/Core/Devices.swift",
                      "Airhand/Controller/Audio.swift", "Airhand/Controller/ClipFiles.swift", "Airhand/Controller/RemoteSession.swift",
                      "Airhand/Controller/VideoDecoder.swift", "Airhand/Session/GameEditor.swift", "Airhand/Session/GameLayer.swift",
                      "Airhand/Session/GameModel.swift", "Airhand/Session/SessionController.swift", "Airhand/Session/SessionMenu.swift",
                      "Airhand/Session/SessionViews.swift"],
            sources: ["Shared/Utilities.swift", "Shared/Model.swift", "Shared/L10n.swift", "Airhand/Core/Protocol.swift",
                      "Airhand/Session/Gestures.swift", "Airhand/Controller/AvSync.swift", "Airhand/Session/SessionState.swift"]
        ),
        .executableTarget(name: "AirhandCoreSelfTest", dependencies: ["AirhandCoreLogic", .product(name: "Perception", package: "swift-perception")], path: "CoreTests")
    ],
    swiftLanguageModes: [.v5]
)
