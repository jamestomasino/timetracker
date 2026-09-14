import Foundation

/// Formats a duration in seconds as `h:mm:ss` / `mm:ss` / `ss`.
public enum TimeFormat {
    public static func string(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        if m > 0 {
            return String(format: "%d:%02d", m, s)
        }
        return String(format: "%d", s)
    }
}
