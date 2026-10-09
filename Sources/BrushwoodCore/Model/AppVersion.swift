import Foundation

/// A version number such as 1.0.1, compared component by component (a leading "v", as in tags, is ignored).
public struct AppVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]
    public let description: String

    public init?(_ string: String) {
        let s = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
        description = s
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// Missing components count as 0, so 1.0 equals 1.0.0.
    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}
