import Foundation

/// גודל בעברית קריאה — אותו ניסוח של המסייע ל-Windows.
public func humanSize(_ bytes: Int64) -> String {
    if bytes >= 1_073_741_824 {
        let tenths = bytes * 10 / 1_073_741_824
        return "\(tenths / 10).\(tenths % 10) ג׳יגה"
    }
    if bytes >= 1_048_576 {
        return "\(bytes / 1_048_576) מגה"
    }
    return "\((bytes + 1023) / 1024) קילו"
}

public func humanSpeed(_ bytesPerSecond: Double) -> String {
    let perSecond = Int64(max(0, bytesPerSecond))
    if perSecond >= 1_048_576 {
        let tenths = perSecond * 10 / 1_048_576
        return "\(tenths / 10).\(tenths % 10) מגה בשנייה"
    }
    return "\((perSecond + 1023) / 1024) קילו בשנייה"
}

public func humanRemaining(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return "פחות מדקה" }
    let minutes = Int((seconds / 60).rounded(.up))
    if minutes < 60 {
        return minutes == 1 ? "כדקה" : "כ-\(minutes) דקות"
    }
    let hours = minutes / 60
    let rest = minutes % 60
    let hoursText = hours == 1 ? "כשעה" : "כ-\(hours) שעות"
    return rest == 0 ? hoursText : "\(hoursText) ו-\(rest) דקות"
}

/// מהירות כממוצע נע על ~5 שניות, וזמן משוער לסיום.
public struct SpeedMeter {
    public let window: TimeInterval
    private var samples: [(time: TimeInterval, bytes: Int64)] = []

    public init(window: TimeInterval = 5) {
        self.window = window
    }

    /// `bytes` הוא מונה מצטבר של בתים שירדו בריצה הזאת.
    public mutating func record(time: TimeInterval, bytes: Int64) {
        samples.append((time, bytes))
        while let first = samples.first, time - first.time > window, samples.count > 2 {
            samples.removeFirst()
        }
    }

    /// nil עד שנצבר מספיק זמן למדידה.
    public var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.time - first.time
        guard span >= 0.5 else { return nil }
        return Double(last.bytes - first.bytes) / span
    }

    public func secondsRemaining(_ remainingBytes: Int64) -> TimeInterval? {
        guard let speed = bytesPerSecond, speed > 0 else { return nil }
        return Double(max(0, remainingBytes)) / speed
    }
}
