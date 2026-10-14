import Foundation

/// A version number such as 1.0.1, compared component by component (a leading "v", as in tags, is ignored).
/// Editions built on a release add their name and revision: 1.0.3-plus.2 is the second Brushwood Plus on top of 1.0.3,
/// and comes after 1.0.3 and 1.0.3-plus.1.
public struct AppVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]
    /// The edition name ("plus"), nil for a plain release.
    public let edition: String?
    /// The edition's revision on top of `parts`; 0 for a plain release.
    public let revision: Int
    public let description: String

    public init?(_ string: String) {
        let s = string.hasPrefix("v") ? String(string.dropFirst()) : string
        var base = Substring(s)
        var edition: String?, revision = 0
        if let dash = s.firstIndex(of: "-") {
            let suffix = s[s.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false)
            guard suffix.count == 2, let name = suffix.first, !name.isEmpty, name.allSatisfy({ $0.isLetter }),
                  let r = Int(suffix[1]), r > 0 else { return nil }
            edition = String(name)
            revision = r
            base = s[..<dash]
        }
        let parts = base.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
        self.edition = edition
        self.revision = revision
        description = s
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return a.revision < b.revision
    }

    /// Missing components count as 0, so 1.0 equals 1.0.0.
    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}
