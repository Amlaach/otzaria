import Foundation
import XCTest
@testable import AssistantCore

/// אותם קובצי ייחוס שמימוש הייחוס ב-Dart מפיק (generate_fixtures.dart): המסייע חייב
/// להציג ולהפיק בדיוק את מה שכתוב ב-expected-selections.json.
final class FixtureTests: XCTestCase {
    private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AssistantCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // macos
        .deletingLastPathComponent() // download_assistant
        .appendingPathComponent("fixtures", isDirectory: true)

    /// העתק של kOsReleaseSamples ב-generate_fixtures.dart; הבדיקה נכשלת אם המפתחות נפרדים.
    private static let osReleaseSamples: [String: String?] = [
        "ubuntu": "NAME=\"Ubuntu\"\nID=ubuntu\nID_LIKE=debian\nVERSION_ID=\"24.04\"\n",
        "linuxmint": "ID=linuxmint\nID_LIKE=\"ubuntu debian\"\n",
        "fedora": "NAME=\"Fedora Linux\"\nID=fedora\nVERSION_ID=40\n",
        "opensuse-tumbleweed": "ID=\"opensuse-tumbleweed\"\nID_LIKE=\"opensuse suse\"\n",
        "arch": "NAME=\"Arch Linux\"\nID=arch\n",
        "not-linux": nil,
    ]

    private var manifest: ReleaseManifest!
    private var expected: [String: Any]!

    override func setUpWithError() throws {
        let loaded = try Self.load("release-manifest.json", "expected-selections.json")
        manifest = loaded.manifest
        expected = loaded.expected
    }

    private static func load(_ manifestName: String, _ expectedName: String) throws
        -> (manifest: ReleaseManifest, expected: [String: Any]) {
        let manifestData = try Data(contentsOf: fixturesDirectory.appendingPathComponent(manifestName))
        let expectedData = try Data(contentsOf: fixturesDirectory.appendingPathComponent(expectedName))
        let manifest = try ReleaseManifest.parse(manifestData)
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: expectedData) as? [String: Any])
        return (manifest, expected)
    }

    func testPlatformChoices() {
        XCTAssertEqual(platformChoices(manifest), expected["platformChoices"] as? [String])
    }

    func testArchitectureChoices() throws {
        let table = try XCTUnwrap(expected["architectureChoices"] as? [String: [String]])
        XCTAssertEqual(Set(table.keys), Set(assistantPlatforms))
        for (platform, choices) in table {
            XCTAssertEqual(architectureChoices(manifest, platform), choices, platform)
        }
    }

    func testPackageFormatChoices() throws {
        let table = try XCTUnwrap(expected["packageFormatChoices"] as? [String: [String]])
        XCTAssertFalse(table.isEmpty)
        for (key, choices) in table {
            let architecture = String(key.dropFirst("linux/".count))
            XCTAssertEqual(packageFormatChoices(manifest, "linux", architecture), choices, key)
        }
    }

    func testDefaultPackageFormat() throws {
        let table = try XCTUnwrap(expected["defaultPackageFormat"] as? [String: String])
        XCTAssertEqual(Set(table.keys), Set(Self.osReleaseSamples.keys))
        let choices = packageFormatChoices(manifest, "linux", "x64")
        for (key, format) in table {
            let sample = Self.osReleaseSamples[key] ?? nil
            XCTAssertEqual(defaultPackageFormat(sample, choices), format, key)
        }
    }

    func testEveryTarget() throws {
        let targets = try XCTUnwrap(expected["targets"] as? [[String: Any]])
        XCTAssertEqual(targets.count, 10)
        try checkTargets(manifest, targets)
    }

    /// מתקין ה-FULL הגיע ל-4 GiB ואינו רץ: "מלאה" עוברת למתקין המאונדקס וחלקי הספרייה.
    func testLargeFullVariant() throws {
        let large = try Self.load("release-manifest-large-full.json", "expected-selections-large-full.json")
        let targets = try XCTUnwrap(large.expected["targets"] as? [[String: Any]])
        XCTAssertEqual(targets.count, 2)
        try checkTargets(large.manifest, targets)
    }

    /// ספרייה שנבחרה לבדה מגיעה עם המתקין שקורא אותה; ב-ARM64 אין מי שיתקין אותה.
    func testLibraryBringsItsInstaller() throws {
        let x64 = AssistantTarget(platform: "windows", architecture: "x64")
        XCTAssertEqual(
            withDependencies(manifest, ["library-full-indexed"], x64),
            ["otzaria-windows-full-indexed", "library-full-indexed"]
        )
        let library = try XCTUnwrap(manifest.components.first { $0.id == "library-full-indexed" })
        XCTAssertFalse(componentIsOffered(manifest, library, AssistantTarget(platform: "windows", architecture: "arm64")))
    }

    private func checkTargets(_ manifest: ReleaseManifest, _ targets: [[String: Any]]) throws {
        for entry in targets {
            let raw = try XCTUnwrap(entry["target"] as? [String: String])
            let target = AssistantTarget(
                platform: raw["platform"] ?? "",
                architecture: raw["architecture"] ?? "",
                packageFormat: raw["packageFormat"] ?? ""
            )
            let label = "\(target.platform)/\(target.architecture)/\(target.packageFormat)"

            XCTAssertEqual(
                manifest.components.filter { componentIsOffered(manifest, $0, target) }.map { $0.id },
                entry["offeredComponents"] as? [String], label
            )

            let expectedPresets = try XCTUnwrap(entry["presets"] as? [[String: Any]])
            let presets = buildPresets(manifest, target)
            XCTAssertEqual(presets.map { $0.id }, expectedPresets.map { $0["id"] as? String ?? "" }, label)
            for (preset, want) in zip(presets, expectedPresets) {
                XCTAssertEqual(preset.members, want["members"] as? [String], "\(label) \(preset.id)")
                let files = plannedOutputFiles(manifest, preset.members, target)
                XCTAssertEqual(files, want["outputFiles"] as? [String], "\(label) \(preset.id)")
                XCTAssertEqual(
                    plannedOutputSubfolder(files, target.platform),
                    want["outputSubfolder"] as? String, "\(label) \(preset.id)"
                )

                // התוכנית שהמסייע מבצע בפועל מפיקה בדיוק את אותם קבצים.
                let plan = try PreparationPlan.make(manifest: manifest, selectedIds: preset.members, target: target)
                XCTAssertEqual(plan.outputFiles, files, "\(label) \(preset.id)")
                XCTAssertEqual(plan.actions.map(Self.outputName), files, "\(label) \(preset.id)")
                XCTAssertEqual(plan.outputSubfolder, want["outputSubfolder"] as? String)
            }
        }
    }

    func testAssistantsAreNeverComponents() {
        let names = manifest.components.flatMap { $0.assets.map { $0.name } }
        XCTAssertFalse(names.contains { $0.hasPrefix("Otzaria-Download-Assistant") })
        XCTAssertFalse(names.contains("otzaria-macos.zip"))
    }

    func testFixtureTagIsTheBuildTag() {
        XCTAssertEqual(manifest.releaseTag, "0.10.3+143")
        let asset = manifest.components[0].assets[0]
        XCTAssertEqual(
            Endpoints.assetURL(repository: asset.repository, tag: asset.releaseTag, name: asset.name)?.absoluteString,
            "https://github.com/Otzaria/otzaria/releases/download/0.10.3+143/app-release.apk"
        )
    }

    private static func outputName(_ action: OutputAction) -> String {
        switch action {
        case .place(let item): return item.name
        case .assemble(let name, _, _, _, _): return name
        }
    }
}
