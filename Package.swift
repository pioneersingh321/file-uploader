// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BoltFileUploader",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "BoltFileUploader",
            targets: ["BoltFileUploaderPlugin"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm", from: "8.0.0")
    ],
    targets: [
        // Swift implementation target
        .target(
            name: "BoltFileUploaderPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                "BoltFileUploaderObjC"
            ],
            path: "ios/Sources/BoltFileUploader",
            publicHeadersPath: "public"
        ),
        // Objective-C CAP_PLUGIN registration macro target
        .target(
            name: "BoltFileUploaderObjC",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/BoltFileUploaderObjC",
            publicHeadersPath: "."
        )
    ]
)
