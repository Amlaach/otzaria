import AssistantCore
import SwiftUI

struct AssistantView: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            Divider()
            buttons
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .onAppear { model.load() }
        .alert(item: $model.alert) { item in
            if let onContinue = item.onContinue {
                return Alert(
                    title: Text(item.title),
                    message: Text(item.message),
                    primaryButton: .default(Text("המשך"), action: onContinue),
                    secondaryButton: .cancel(Text("ביטול"))
                )
            }
            return Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("אישור")))
        }
    }

    // MARK: - כותרת

    private var header: some View {
        let texts = headerTexts
        return VStack(alignment: .leading, spacing: 4) {
            Text(texts.title).font(.title2).bold()
            if !texts.subtitle.isEmpty {
                Text(texts.subtitle).foregroundColor(.secondary)
            }
        }
    }

    private var headerTexts: (title: String, subtitle: String) {
        switch model.page {
        case .loading: return ("אוצריא — מסייע הורדה", "מתחבר לאתר ההורדות של אוצריא…")
        case .loadFailed: return ("אוצריא — מסייע הורדה", "")
        case .platform: return ("אוצריא — מסייע הורדה", "כלי זה אינו מתקין את אוצריא.")
        case .architecture: return ("המחשב שאליו מכינים", "איזה סוג מחשב הוא היעד?")
        case .packageFormat: return ("המחשב שאליו מכינים", "איזו הפצה של Linux מותקנת בו?")
        case .presets: return ("מה להוריד", "בחר את היקף ההורדה.")
        case .custom: return ("בחירה אישית", "סמן את הרכיבים שברצונך להוריד.")
        case .folder: return ("לאן לשמור", "כברירת מחדל התוצאה נשמרת ליד המסייע עצמו.")
        case .working:
            return ("הורדת הקבצים", "הקבצים יורדים מאתר אוצריא. אפשר לעצור בכל רגע — מה שכבר ירד יישמר.")
        case .finished: return ("ההתקנה מוכנה", "")
        case .failed: return ("לא ניתן להכין את ההתקנה", "")
        }
    }

    // MARK: - תוכן

    @ViewBuilder
    private var content: some View {
        switch model.page {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .loadFailed:
            loadFailed
        case .platform:
            platformPage
        case .architecture:
            architecturePage
        case .packageFormat:
            packageFormatPage
        case .presets:
            presetsPage
        case .custom:
            customPage
        case .folder:
            folderPage
        case .working:
            WorkingView(status: model.status)
        case .finished:
            FinishedView(model: model)
        case .failed:
            failedPage
        }
    }

    private var loadFailed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.error?.message ?? AssistantError.cannotReadList)
            Text("אפשר לפתוח את עמוד ההורדות של אוצריא בדפדפן ולהוריד משם ידנית (אפשרות מוגבלת: המסייע לא יוכל לבדוק את הקבצים או לחבר אותם).")
                .fixedSize(horizontal: false, vertical: true)
            TechnicalDetails(text: model.error?.technical ?? "")
        }
    }

    private var failedPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.error?.message ?? "לא ניתן להכין את ההתקנה.")
                .fixedSize(horizontal: false, vertical: true)
            Text("מה שכבר ירד נשמר, והפעלה חוזרת של המסייע תמשיך ממנו.")
                .foregroundColor(.secondary)
            TechnicalDetails(text: model.error?.technical ?? "")
        }
    }

    private var platformPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("הכלי מאפשר להוריד את הקבצים הדרושים ולהכין התקנה עבור מחשב זה או עבור מחשב אחר.")
                .fixedSize(horizontal: false, vertical: true)
            Text("יש אינטרנט במחשב שבו תותקן אוצריא? מספיקה ההתקנה הבסיסית — הספרייה תרד מתוך התוכנה.")
                .fixedSize(horizontal: false, vertical: true)
            Text("לאיזו מערכת להכין את ההתקנה?").bold()
            ForEach(model.platforms, id: \.self) { platform in
                ChoiceRow(
                    title: platformDisplayNames[platform] ?? platform,
                    subtitle: platform == "macos" ? "המחשב הזה" : nil,
                    selected: model.platform == platform
                ) { model.platform = platform }
            }
        }
    }

    private var architecturePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.architectures, id: \.self) { architecture in
                ChoiceRow(
                    title: architecture == "arm64" ? "מחשב עם מעבד מסוג ARM" : "מחשב רגיל",
                    subtitle: nil,
                    selected: model.architecture == architecture
                ) { model.architecture = architecture }
            }
            Text("אם אינך יודע, בחר באפשרות הראשונה — היא מתאימה כמעט לכל המחשבים.")
                .foregroundColor(.secondary)
        }
    }

    private var packageFormatPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.packageFormats, id: \.self) { format in
                ChoiceRow(title: packageFormatLabel(format), subtitle: nil, selected: model.packageFormat == format) {
                    model.packageFormat = format
                }
            }
            Text("אם אינך יודע, בחר באפשרות הראשונה — היא מתאימה לרוב המחשבים.")
                .foregroundColor(.secondary)
        }
    }

    private func packageFormatLabel(_ format: String) -> String {
        switch format {
        case "deb": return "Ubuntu, Debian, Mint והפצות דומות (DEB)"
        case "rpm": return "Fedora, openSUSE והפצות דומות (RPM)"
        case portablePackageFormat: return "הפצה אחרת — ללא התקנה"
        default: return format
        }
    }

    private var presetsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.presets, id: \.id) { preset in
                ChoiceRow(
                    title: "\(preset.caption) — \(humanSize(model.size(of: preset.members)))",
                    subtitle: preset.description,
                    selected: model.presetId == preset.id
                ) { model.presetId = preset.id }
            }
            ChoiceRow(
                title: "בחירה אישית",
                subtitle: "אני רוצה לבחור בעצמי מה להוריד.",
                selected: model.presetId == customPresetId
            ) { model.presetId = customPresetId }
            Text("אפשר לשנות את הבחירה בהמשך.").foregroundColor(.secondary)
        }
    }

    private var customPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ליד כל רכיב מופיע גודל ההורדה שלו.").foregroundColor(.secondary)
            ForEach(model.offeredComponents, id: \.id) { component in
                Toggle(isOn: Binding(
                    get: { model.customChecked.contains(component.id) },
                    set: { checked in
                        if checked {
                            model.customChecked.insert(component.id)
                        } else {
                            model.customChecked.remove(component.id)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(component.name) — \(humanSize(component.downloadSize))\(component.required ? " (נדרש)" : "")")
                        if !component.description.isEmpty {
                            Text(component.description).font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var folderPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("אפשר לבחור תיקייה אחרת. בסיום אפשר יהיה להעתיק את התוצאה לדיסק-און-קי ולהעביר אותה למחשב המנותק.")
                .fixedSize(horizontal: false, vertical: true)
            if model.outputFellBack {
                Text("אי אפשר לשמור ליד המסייע (macOS מריץ אותו מתיקייה זמנית שאין בה הרשאת כתיבה), ולכן הוצעה כאן תיקייה אחרת.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                PathText(path: model.outputBase.path)
                Spacer(minLength: 0)
                Button("בחר תיקייה…") { model.chooseFolder() }
            }
            Text("גודל ההורדה: \(humanSize(model.size(of: model.selectedMembers)))")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - כפתורים

    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            switch model.page {
            case .loadFailed:
                Button("פתח את עמוד ההורדות") {
                    model.openDownloadsPage()
                    model.cancel()
                }
                Button("סגור") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            case .failed:
                Button("סגור") { model.cancel() }
                    .keyboardShortcut(.defaultAction)
            case .finished:
                Button("סיום") { model.finish() }
                    .keyboardShortcut(.defaultAction)
            case .working, .loading:
                Button(model.page == .working ? "עצור" : "ביטול") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            default:
                Button("הקודם") { model.back() }
                    .disabled(!model.canGoBack)
                Button(model.page == .folder ? "התחל" : "הבא") { model.next() }
                    .keyboardShortcut(.defaultAction)
                Button("ביטול") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}

/// שורת בחירה אחת מתוך כמה — עיגול, כותרת, ושורת הסבר אופציונלית.
struct ChoiceRow: View {
    let title: String
    let subtitle: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle = subtitle {
                        Text(subtitle).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// נתיב, כתובת או פקודה — משמאל לימין, וניתן לבחירה ולהעתקה.
struct PathText: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .environment(\.layoutDirection, .leftToRight)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct TechnicalDetails: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            DisclosureGroup("פרטים טכניים") {
                PathText(path: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }
}

struct WorkingView: View {
    let status: PreparationStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let status = status {
                Text(status.title).bold()
                if !status.detail.isEmpty {
                    Text(status.detail).foregroundColor(.secondary).lineLimit(2)
                }
                ProgressView(value: status.fraction)
                Text("סך הכול: \(humanSize(status.doneBytes)) מתוך \(humanSize(status.totalBytes))")
                if status.phase == .downloading, let speed = status.bytesPerSecond {
                    let remaining = status.secondsRemaining.map { " · נותר \(humanRemaining($0))" } ?? ""
                    Text("מהירות: \(humanSpeed(speed))\(remaining)").foregroundColor(.secondary)
                }
            } else {
                Text("מתכונן…").bold()
                ProgressView()
            }
        }
    }
}

struct FinishedView: View {
    @ObservedObject var model: AssistantModel

    private static let runnableSuffixes = [".exe", ".dmg", ".apk", ".deb", ".rpm"]

    var body: some View {
        if let result = model.result {
            let single = result.producedFiles.count == 1
            VStack(alignment: .leading, spacing: 12) {
                if single {
                    let name = result.producedFiles[0].lastPathComponent
                    Text("הקובץ מוכן:")
                    PathText(path: name)
                    Text("הוא נמצא בתיקייה:")
                    PathText(path: result.outputDirectory.path)
                    Text(singleAdvice(name)).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("ההתקנה מוכנה בתיקייה:")
                    PathText(path: result.outputDirectory.path)
                    Text(folderAdvice(result.producedFiles.map { $0.lastPathComponent }))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("הקבצים שהוכנו:")
                    ForEach(result.producedFiles, id: \.self) { file in
                        PathText(path: "• \(file.lastPathComponent)")
                    }
                }
                if !result.keptSplitAssets.isEmpty {
                    Text("חלק מהקבצים גדולים מכדי להישמר כקובץ אחד בדיסק-און-קי, ולכן נשמרו בחלקים. במחשב היעד, כדי לחבר אותם, הרץ מתוך התיקייה:")
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(result.keptSplitAssets, id: \.self) { asset in
                        PathText(path: joinCommand(assetName: asset))
                    }
                }
                Toggle(single ? "הצג את הקובץ שהוכן" : "הצג את התיקייה שהוכנה", isOn: $model.revealWhenDone)
                    .toggleStyle(.checkbox)
                    .padding(.top, 8)
            }
        }
    }

    /// נוקב בשם המתקין שמפעילים, כשיש כזה בתיקייה.
    private func folderAdvice(_ names: [String]) -> String {
        let installer = names.first { $0.lowercased().hasSuffix(".exe") } ?? "קובץ ההתקנה"
        return "העתק את כל התיקייה הזאת לדיסק-און-קי, ובמחשב המנותק הפעל מתוכה את \(installer). "
            + "הקבצים חייבים להישאר יחד באותה תיקייה. אין צורך בחיבור לאינטרנט ואין צורך בתוכנות נוספות."
    }

    private func singleAdvice(_ name: String) -> String {
        var text = "העתק את הקובץ הזה לדיסק-און-קי ומשם למחשב המנותק."
        if Self.runnableSuffixes.contains(where: { name.lowercased().hasSuffix($0) }) {
            text += " שם הפעל אותו — אין צורך בחיבור לאינטרנט ואין צורך בתוכנות נוספות."
        }
        return text
    }
}
