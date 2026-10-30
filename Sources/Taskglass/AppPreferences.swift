import Foundation

/// View settings only. Standalone test executables use memory and never modify
/// the app's preferences. Monitoring history, process names and searches stay out.
@MainActor final class AppPreferences {
    private let defaults: UserDefaults?
    private var memory: [String: Any] = [:]
    init(defaults: UserDefaults? = nil) { self.defaults = defaults }
    static func forApplication() -> AppPreferences {
        AppPreferences(defaults: Bundle.main.bundleIdentifier == "dev.taskglass.app" ? .standard : nil)
    }
    private func value(_ key: String) -> Any? { defaults?.object(forKey: key) ?? memory[key] }
    func number(_ key: String, fallback: Double) -> Double { (value(key) as? NSNumber)?.doubleValue ?? fallback }
    func bool(_ key: String, fallback: Bool) -> Bool { value(key) as? Bool ?? fallback }
    func string(_ key: String, fallback: String) -> String { value(key) as? String ?? fallback }
    func strings(_ key: String) -> [String: String] { value(key) as? [String: String] ?? [:] }
    func save(_ value: Any, for key: String) {
        if let defaults { defaults.set(value, forKey: key) }
        else { memory[key] = value }
    }
}
