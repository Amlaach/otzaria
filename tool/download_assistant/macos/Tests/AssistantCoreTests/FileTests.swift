import CryptoKit
import Foundation
import XCTest
@testable import AssistantCore

final class FileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("otzaria-assistant-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func bytes(_ count: Int, seed: UInt8 = 7) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }

    private func sha(_ data: Data) -> String {
        hexString(SHA256.hash(data: data))
    }

    // MARK: - קובץ חלקי

    /// ברשת שמתעלמת מ-Range: 200 על בקשת המשך — הקובץ מקוצץ וגוף אותה תשובה נכתב מההתחלה.
    func testFullReplyOverwritesAStalePartial() throws {
        let body = bytes(100)
        let url = directory.appendingPathComponent("a.exe.download")
        try Data(repeating: 0xFF, count: 40).write(to: url)
        let sink = TransferSink(url: url, expectedSize: 100, expectedSha256: sha(body))
        XCTAssertEqual(sink.existingSize, 40)

        let action = ResumeRules.action(requestedOffset: 40, statusCode: 200, contentRange: nil, expectedSize: 100)
        try sink.begin(action)
        try sink.write(body.prefix(60))
        try sink.write(body.suffix(40))
        XCTAssertTrue(sink.finishAndVerify())
        XCTAssertEqual(try Data(contentsOf: url), body)
    }

    /// 206 תואם: ה-hash של הקיים מחושב מהדיסק פעם אחת, והשאר נצבר בזרימה.
    func testExactPartialReplyContinuesTheFile() throws {
        let body = bytes(100)
        let url = directory.appendingPathComponent("a.exe.download")
        try body.prefix(40).write(to: url)
        let sink = TransferSink(url: url, expectedSize: 100, expectedSha256: sha(body))

        let action = ResumeRules.action(
            requestedOffset: 40, statusCode: 206,
            contentRange: ResumeRules.expectedContentRange(offset: 40, size: 100), expectedSize: 100
        )
        XCTAssertEqual(action, .append(from: 40))
        try sink.begin(action, prefix: hashFilePrefix(url, length: 40))
        try sink.write(body.suffix(60))
        XCTAssertTrue(sink.finishAndVerify())
        XCTAssertEqual(try Data(contentsOf: url), body)
    }

    func testCorruptDownloadFailsVerification() throws {
        let body = bytes(50)
        let url = directory.appendingPathComponent("b.download")
        let sink = TransferSink(url: url, expectedSize: 50, expectedSha256: sha(body))
        try sink.begin(.writeFromStart)
        var corrupt = body
        corrupt[10] ^= 0x01
        try sink.write(corrupt)
        XCTAssertFalse(sink.finishAndVerify())
    }

    func testMoreBytesThanExpectedIsRejected() throws {
        let url = directory.appendingPathComponent("c.download")
        let sink = TransferSink(url: url, expectedSize: 10, expectedSha256: sha(bytes(10)))
        try sink.begin(.writeFromStart)
        XCTAssertThrowsError(try sink.write(bytes(11)))
    }

    // MARK: - מטמון

    func testPromoteWritesMarkerAndReuseNeedsNoHash() throws {
        let body = bytes(64)
        let store = CacheStore(directory: directory.appendingPathComponent("cache"))
        try store.prepare()
        try body.write(to: store.partialURL("x.dmg", sha256: sha(body)))
        try store.promotePartial(name: "x.dmg", sha256: sha(body))

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.partialURL("x.dmg", sha256: sha(body)).path))
        XCTAssertEqual(try String(contentsOf: store.markerURL("x.dmg"), encoding: .utf8), "\(sha(body))  x.dmg\n")
        XCTAssertEqual(store.status(name: "x.dmg", size: 64, sha256: sha(body)), .ready)

        // מטמון של גרסה קודמת, בלי חותם — hash אחד.
        try FileManager.default.removeItem(at: store.markerURL("x.dmg"))
        XCTAssertEqual(store.status(name: "x.dmg", size: 64, sha256: sha(body)), .needsHash)
        XCTAssertEqual(store.status(name: "x.dmg", size: 65, sha256: sha(body)), .invalid)
        XCTAssertEqual(store.status(name: "missing", size: 1, sha256: sha(body)), .missing)
    }

    /// אותו שם בשתי גרסאות: הקובץ החלקי של האחת אינו נראה לשנייה, ולכן אינו מחודש בטעות.
    func testPartialNameIsBoundToTheVersion() throws {
        let store = CacheStore(directory: directory.appendingPathComponent("cache"))
        try store.prepare()
        let old = bytes(40, seed: 1)
        let new = bytes(40, seed: 2)
        let name = "otzaria-macos-full.tar.zst"
        try old.prefix(20).write(to: store.partialURL(name, sha256: sha(old)))
        XCTAssertNotEqual(store.partialURL(name, sha256: sha(old)), store.partialURL(name, sha256: sha(new)))
        let sink = TransferSink(url: store.partialURL(name, sha256: sha(new)), expectedSize: 40, expectedSha256: sha(new))
        XCTAssertEqual(sink.existingSize, 0)
        let suffix = "\(sha(new).prefix(12)).download"
        XCTAssertEqual(store.partialURL("a.tar.zst", sha256: sha(new)).lastPathComponent, "a.tar.zst.\(suffix)")
        XCTAssertEqual(assemblyPartialName(name: "a.tar.zst", sha256: sha(new)), "a.tar.zst.\(suffix)")
    }

    func testCopyThatFailsLeavesNothing() throws {
        let source = directory.appendingPathComponent("big.bin")
        try bytes(10).write(to: source)
        let destination = directory.appendingPathComponent("missing-dir/big.bin")
        XCTAssertThrowsError(try placeFile(from: source, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testSpaceNeed() throws {
        let store = CacheStore(directory: directory.appendingPathComponent("cache"))
        let (_, parts) = try makeParts([30, 30, 7], in: store)
        let plan = PreparationPlan(
            downloads: parts,
            actions: [.place(parts[2]), .assemble(name: "w", size: 60, sha256: "", caption: "", parts: [parts[0], parts[1]])],
            outputFiles: [], outputSubfolder: "", keptSplitAssets: []
        )
        // אותו כרך: הקישור חינם, וההרכבה מוסיפה לכל היותר חלק אחד.
        XCTAssertEqual(
            spaceNeeded(plan: plan, isCached: { $0.size == 7 }, sameVolume: true),
            SpaceNeed(cacheBytes: 60, outputBytes: 30)
        )
        XCTAssertEqual(
            spaceNeeded(plan: plan, isCached: { _ in true }, sameVolume: false),
            SpaceNeed(cacheBytes: 0, outputBytes: 67)
        )
    }

    // MARK: - הרכבה

    private func makeParts(_ sizes: [Int], in store: CacheStore) throws -> (whole: Data, parts: [DownloadItem]) {
        try store.prepare()
        let whole = bytes(sizes.reduce(0, +), seed: 3)
        var offset = 0
        var parts: [DownloadItem] = []
        for (index, size) in sizes.enumerated() {
            let chunk = whole.subdata(in: offset..<(offset + size))
            let name = "w.tar.zst.part-00\(index)"
            try chunk.write(to: store.fileURL(name))
            try store.writeMarker(name: name, sha256: sha(chunk))
            parts.append(DownloadItem(
                name: name, size: Int64(size), sha256: sha(chunk),
                url: URL(string: "https://github.com/Otzaria/otzaria/releases/download/t/\(name)")!, caption: "w"
            ))
            offset += size
        }
        return (whole, parts)
    }

    func testAssemblyConcatenatesAndDeletesEachPart() throws {
        let store = CacheStore(directory: directory.appendingPathComponent("cache"))
        let (whole, parts) = try makeParts([30, 30, 7], in: store)
        let destination = directory.appendingPathComponent("out/w.tar.zst")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var verified: [Int64] = []

        try assembleSplitAsset(
            name: "w.tar.zst", size: 67, sha256: sha(whole), parts: parts, destination: destination,
            partURL: { store.fileURL($0.name) }, removePart: { store.remove(name: $0.name) },
            verificationProgress: { verified.append($0) }
        )
        XCTAssertEqual(verified.first, 0)
        XCTAssertEqual(verified.last, 67)
        XCTAssertEqual(try Data(contentsOf: destination), whole)
        for part in parts {
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(part.name).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.markerURL(part.name).path))
        }
        let working = destination.deletingLastPathComponent()
            .appendingPathComponent(assemblyPartialName(name: "w.tar.zst", sha256: sha(whole)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: working.path))
    }

    /// הרכבה שנקטעה באמצע חלק: נחתכת לגבול החלק השלם האחרון וממשיכה משם.
    func testAssemblyResumesAfterAnInterruption() throws {
        let store = CacheStore(directory: directory.appendingPathComponent("cache"))
        let (whole, parts) = try makeParts([30, 30, 7], in: store)
        let outDir = directory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let working = outDir.appendingPathComponent(assemblyPartialName(name: "w.tar.zst", sha256: sha(whole)))
        // החלק הראשון נבלע ונמחק; מהשני נכתבו 12 בתים לפני העצירה.
        try whole.prefix(42).write(to: working)
        store.remove(name: parts[0].name)
        XCTAssertEqual(assemblyResumePoint(partialSize: 42, partSizes: [30, 30, 7]).parts, 1)
        XCTAssertEqual(assemblyResumePoint(partialSize: 42, partSizes: [30, 30, 7]).keepBytes, 30)

        try assembleSplitAsset(
            name: "w.tar.zst", size: 67, sha256: sha(whole), parts: parts,
            destination: outDir.appendingPathComponent("w.tar.zst"),
            partURL: { store.fileURL($0.name) }, removePart: { store.remove(name: $0.name) }
        )
        XCTAssertEqual(try Data(contentsOf: outDir.appendingPathComponent("w.tar.zst")), whole)
    }

    func testAssemblyRejectsCorruptResumedPrefix() throws {
        let store = CacheStore(directory: directory.appendingPathComponent("cache"))
        let (whole, parts) = try makeParts([30, 30], in: store)
        let working = directory.appendingPathComponent(assemblyPartialName(name: "w.tar.zst", sha256: sha(whole)))
        var corrupt = whole.prefix(30)
        corrupt[0] ^= 0x01
        try corrupt.write(to: working)
        store.remove(name: parts[0].name)
        let destination = directory.appendingPathComponent("w.tar.zst")

        XCTAssertThrowsError(try assembleSplitAsset(
            name: "w.tar.zst", size: 60, sha256: sha(whole), parts: parts,
            destination: destination, partURL: { store.fileURL($0.name) },
            removePart: { store.remove(name: $0.name) }
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: working.path))
    }

    func testShortPartFailsTheByteCountCheck() throws {
        let store = CacheStore(directory: directory.appendingPathComponent("cache"))
        let (whole, parts) = try makeParts([30, 30], in: store)
        try Data(count: 10).write(to: store.fileURL(parts[1].name))
        let destination = directory.appendingPathComponent("w.tar.zst")
        XCTAssertThrowsError(try assembleSplitAsset(
            name: "w.tar.zst", size: 60, sha256: sha(whole), parts: parts, destination: destination,
            partURL: { store.fileURL($0.name) }, removePart: { store.remove(name: $0.name) }
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testPlaceFileLinksOrCopies() throws {
        let source = directory.appendingPathComponent("src.apk")
        let body = bytes(20)
        try body.write(to: source)
        let destination = directory.appendingPathComponent("dst/src.apk")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination)
        try placeFile(from: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), body)
    }

    // MARK: - תוכנית

    func testPlanKeepsHugeSplitAssetsAsPartsOutsideWindows() throws {
        let hash = String(repeating: "e", count: 64)
        let half = maxSingleOutputFileSize / 2
        let asset = ManifestAsset(
            kind: "split", repository: "Otzaria/otzaria", releaseTag: "t", name: "lib.tar.zst",
            size: half * 2, sha256: hash,
            parts: [ManifestPart(name: "lib.tar.zst.part-000", size: half, sha256: hash),
                    ManifestPart(name: "lib.tar.zst.part-001", size: half, sha256: hash)]
        )
        let manifest = ReleaseManifest(components: [
            ManifestComponent(id: "lib", name: "ספרייה", type: "library", platform: "any", assets: [asset]),
        ])
        let plan = try PreparationPlan.make(manifest: manifest, selectedIds: ["lib"], target: AssistantTarget(platform: "linux"))
        XCTAssertEqual(plan.outputFiles, ["lib.tar.zst.part-000", "lib.tar.zst.part-001"])
        XCTAssertEqual(plan.keptSplitAssets, ["lib.tar.zst"])
        XCTAssertEqual(plan.outputSubfolder, "אוצריא להתקנה ל-Linux")
        XCTAssertEqual(plan.downloads.count, 2)
    }
}
