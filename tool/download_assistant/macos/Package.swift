// swift-tools-version:5.9
// מסייע ההורדה של אוצריא ל-macOS. build_app.sh בונה ממנו את ה-.app (Universal).
import PackageDescription

let package = Package(
    name: "OtzariaDownloadAssistant",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "DownloadAssistant", targets: ["DownloadAssistant"]),
    ],
    targets: [
        // כל הלוגיקה, בלי ממשק — כך היא נבדקת ב-XCTest בלי חלון.
        .target(name: "AssistantCore"),
        .executableTarget(
            name: "DownloadAssistant",
            dependencies: ["AssistantCore"]
        ),
        .testTarget(
            name: "AssistantCoreTests",
            dependencies: ["AssistantCore"]
        ),
    ],
    // בדיקות ה-concurrency המחמירות של Swift 6 היו מפילות את הבנייה על ה-runner.
    swiftLanguageVersions: [.v5]
)
