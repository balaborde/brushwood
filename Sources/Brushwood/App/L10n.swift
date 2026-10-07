import Foundation

/// Localized UI string. Keys are the English text; translations live in `<lang>.lproj/Localizable.strings`.
@inline(__always) func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Localized format string.
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
