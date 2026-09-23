import AppKit
import AssistantCore
import Foundation

enum Page: Equatable {
    case loading
    case loadFailed
    case platform
    case architecture
    case packageFormat
    case presets
    case custom
    case folder
    case working
    case finished
    case failed
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// nil = אישור בלבד. אחרת — "המשך" מריץ את הפעולה.
    let onContinue: (() -> Void)?
}

let customPresetId = "custom"

/// מכונת המצבים של האשף. כל הלוגיקה של הבחירה נמצאת ב-AssistantCore; כאן רק הניווט.
final class AssistantModel: ObservableObject {
    @Published private(set) var page: Page = .loading
    @Published var error: AssistantError?
    @Published var alert: AlertItem?

    @Published private(set) var platforms: [String] = []
    @Published var platform = "macos"
    @Published private(set) var architectures: [String] = []
    @Published var architecture = "x64"
    @Published private(set) var packageFormats: [String] = []
    @Published var packageFormat = ""
    @Published private(set) var presets: [AssistantPreset] = []
    @Published var presetId = ""
    @Published var customChecked = Set<String>()

    @Published var outputBase: URL
    @Published private(set) var outputFellBack = false

    @Published private(set) var status: PreparationStatus?
    @Published private(set) var result: PreparationResult?
    @Published var revealWhenDone = true

    private(set) var manifest: ReleaseManifest?
    private var history: [Page] = []
    private var loader: ReleaseLoader?
    private var runner: PreparationRunner?

    init() {
        let location = OutputLocation.defaultBase(bundleURL: Bundle.main.bundleURL)
        outputBase = location.url
        outputFellBack = location.usedFallback
    }

    var target: AssistantTarget {
        AssistantTarget(platform: platform, architecture: architecture, packageFormat: packageFormat)
    }

    var offeredComponents: [ManifestComponent] {
        guard let manifest = manifest else { return [] }
        return manifest.components.filter { componentIsOffered(manifest, $0, target) }
    }

    var canGoBack: Bool {
        !history.isEmpty && [.architecture, .packageFormat, .presets, .custom, .folder].contains(page)
    }

    // MARK: - טעינה

    func load() {
        guard page == .loading, loader == nil else { return }
        let loader = ReleaseLoader()
        self.loader = loader
        loader.load(embeddedTag: embeddedReleaseTag) { [weak self] result in
            guard let self = self else { return }
            self.loader = nil
            switch result {
            case .failure(let error):
                self.error = error
                self.page = .loadFailed
            case .success(let release):
                self.manifest = release.manifest
                self.platforms = platformChoices(release.manifest)
                if !self.platforms.contains(self.platform) {
                    self.platform = self.platforms.first ?? "macos"
                }
                self.page = .platform
            }
        }
    }

    // MARK: - ניווט

    func next() {
        guard let manifest = manifest else { return }
        switch page {
        case .platform:
            architectures = architectureChoices(manifest, platform)
            // המסייע רץ על Mac, ולכן יעד Windows/Linux הוא תמיד מחשב אחר — x64 כברירת מחדל.
            if !architectures.contains(architecture) {
                architecture = architectures.contains("x64") ? "x64" : (architectures.first ?? "")
            }
            if architectures.count > 1 {
                go(.architecture)
            } else {
                afterArchitecture()
            }
        case .architecture:
            afterArchitecture()
        case .packageFormat:
            goToPresets()
        case .presets:
            if presetId == customPresetId {
                if customChecked.isEmpty {
                    customChecked = Set(offeredComponents.filter { $0.required }.map { $0.id })
                }
                go(.custom)
            } else {
                go(.folder)
            }
        case .custom:
            let valid = Set(offeredComponents.map { $0.id })
            customChecked.formIntersection(valid)
            if customChecked.isEmpty {
                alert = AlertItem(title: "", message: "יש לבחור לפחות רכיב אחד להורדה.", onContinue: nil)
                return
            }
            go(.folder)
        case .folder:
            confirmFolderAndStart()
        default:
            break
        }
    }

    func back() {
        guard canGoBack, let previous = history.popLast() else { return }
        page = previous
    }

    private func go(_ next: Page) {
        history.append(page)
        page = next
    }

    private func afterArchitecture() {
        guard let manifest = manifest else { return }
        packageFormats = packageFormatChoices(manifest, platform, architecture)
        if !packageFormats.contains(packageFormat) {
            packageFormat = defaultPackageFormat(nil, packageFormats)
        }
        if packageFormats.count > 1 {
            go(.packageFormat)
        } else {
            goToPresets()
        }
    }

    private func goToPresets() {
        guard let manifest = manifest else { return }
        presets = buildPresets(manifest, target)
        if presetId != customPresetId && !presets.contains(where: { $0.id == presetId }) {
            presetId = presets.first(where: { $0.id == defaultPresetId })?.id
                ?? presets.first?.id ?? customPresetId
        }
        customChecked.removeAll()
        go(.presets)
    }

    var selectedMembers: [String] {
        guard let manifest = manifest else { return [] }
        if let preset = presets.first(where: { $0.id == presetId }) {
            return preset.members
        }
        let ordered = manifest.components.map { $0.id }.filter { customChecked.contains($0) }
        return withDependencies(manifest, ordered, target)
    }

    func size(of members: [String]) -> Int64 {
        let set = Set(members)
        return manifest?.components.filter { set.contains($0.id) }.reduce(0) { $0 + $1.downloadSize } ?? 0
    }

    // MARK: - תיקייה

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "בחר"
        panel.message = "לאן לשמור את הקבצים?"
        panel.directoryURL = outputBase
        if panel.runModal() == .OK, let url = panel.url {
            outputBase = url
            outputFellBack = false
        }
    }

    private func confirmFolderAndStart() {
        if !OutputLocation.isWritable(outputBase) {
            let fallback = OutputLocation.fallbackBase()
            if outputBase != fallback && OutputLocation.isWritable(fallback) {
                outputBase = fallback
                alert = AlertItem(
                    title: "",
                    message: "לא ניתן לשמור בתיקייה שנבחרה. במקומה מוצעת התיקייה:\n\(fallback.path)\n\nאפשר להמשיך איתה או לבחור תיקייה אחרת.",
                    onContinue: nil
                )
            } else {
                alert = AlertItem(title: "", message: "לא ניתן לשמור בתיקייה שנבחרה. נסה תיקייה אחרת.", onContinue: nil)
            }
            return
        }
        guard let manifest = manifest else { return }
        let plan: PreparationPlan
        do {
            plan = try PreparationPlan.make(manifest: manifest, selectedIds: selectedMembers, target: target)
        } catch let failure as AssistantError {
            fail(failure)
            return
        } catch {
            fail(AssistantError("לא ניתן להכין את ההתקנה.", technical: "\(error)"))
            return
        }
        if let shortfall = missingSpace(for: plan) {
            alert = AlertItem(
                title: "",
                message: "נראה שאין מספיק מקום פנוי. דרושים בערך \(humanSize(shortfall)).\n\nלהמשיך בכל זאת?",
                onContinue: { [weak self] in self?.start(plan) }
            )
            return
        }
        start(plan)
    }

    /// כמה מקום דרוש בכרך שחסר בו, או nil כשיש מספיק (או כשאי אפשר למדוד).
    private func missingSpace(for plan: PreparationPlan) -> Int64? {
        let cache = CacheStore(directory: CacheStore.defaultDirectory())
        try? cache.prepare()
        let cacheVolume = volumeIdentifier(cache.directory)
        let outputVolume = volumeIdentifier(outputBase)
        let sameVolume = cacheVolume != nil && outputVolume != nil && cacheVolume!.isEqual(outputVolume!)
        let need = spaceNeeded(
            plan: plan,
            isCached: { item in
                let status = cache.status(name: item.name, size: item.size, sha256: item.sha256)
                return status == .ready || status == .needsHash
            },
            sameVolume: sameVolume
        )
        if sameVolume {
            let total = need.cacheBytes + need.outputBytes
            if let free = freeSpace(at: outputBase), free < total { return total }
            return nil
        }
        if let free = freeSpace(at: cache.directory), free < need.cacheBytes { return need.cacheBytes }
        if let free = freeSpace(at: outputBase), free < need.outputBytes { return need.outputBytes }
        return nil
    }

    private func volumeIdentifier(_ url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }

    /// ל"שימוש חשוב" עשוי להחזיר nil או 0 בכרכים שאינם APFS — אז הקיבולת הרגילה.
    private func freeSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        )
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        return values?.volumeAvailableCapacity.map { Int64($0) }
    }

    // MARK: - הורדה

    private func start(_ plan: PreparationPlan) {
        history.removeAll()
        page = .working
        status = nil
        let runner = PreparationRunner(plan: plan, outputBase: outputBase)
        self.runner = runner
        runner.start(update: { [weak self] status in
            self?.status = status
        }, completion: { [weak self] outcome in
            guard let self = self else { return }
            self.runner = nil
            switch outcome {
            case .success(let result):
                self.result = result
                self.page = .finished
            case .failure(let error as AssistantError):
                self.fail(error)
            case .failure(is OperationCancelled):
                NSApplication.shared.terminate(nil)
            case .failure(let error):
                self.fail(AssistantError("לא ניתן להכין את ההתקנה.", technical: "\(error)"))
            }
        })
    }

    private func fail(_ failure: AssistantError) {
        NSLog("DownloadAssistant: %@", failure.technical)
        error = failure
        page = .failed
    }

    /// ביטול: מה שכבר ירד נשאר במטמון, והפעלה חוזרת ממשיכה ממנו.
    func cancel() {
        if let runner = runner {
            runner.cancel()
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    func openDownloadsPage() {
        NSWorkspace.shared.open(Endpoints.releasesPage)
    }

    /// פתיחת Finder היא נוחות בלבד: כישלון שקט, התוצאה כבר מוכנה.
    func finish() {
        if revealWhenDone, let target = result?.revealTarget {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
        NSApplication.shared.terminate(nil)
    }
}
