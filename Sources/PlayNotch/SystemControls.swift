import AppKit

/// A few Control-Center-style system toggles that don't need private APIs.
enum Appearance { case light, dark, auto }

@MainActor
final class SystemControls: ObservableObject {
    /// Shared so the notch and the desktop widget show the same state.
    static let shared = SystemControls()

    @Published private(set) var appearance: Appearance = .light
    @Published private(set) var isAwake = false

    private var caffeinate: Process?
    private var timer: Timer?

    private init() {
        refresh()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        appearance = Self.readAppearance()
    }

    // MARK: - Appearance (Light / Dark / Auto)

    /// Cycle Light → Dark → Auto → Light, matching System Settings.
    func cycleAppearance() {
        switch appearance {
        case .light: setAppearance(.dark)
        case .dark:  setAppearance(.auto)
        case .auto:  setAppearance(.light)
        }
    }

    private func setAppearance(_ a: Appearance) {
        appearance = a
        switch a {
        case .light:
            setAutoSwitch(false)
            setDark(false)
        case .dark:
            setAutoSwitch(false)
            setDark(true)
        case .auto:
            setAutoSwitch(true)
        }
    }

    private func setDark(_ on: Bool) {
        AppleScriptRunner.run("""
        tell application "System Events"
            tell appearance preferences to set dark mode to \(on)
        end tell
        """)
    }

    private func setAutoSwitch(_ on: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["write", "-g", "AppleInterfaceStyleSwitchesAutomatically", "-bool", on ? "true" : "false"]
        try? p.run()
    }

    private static func readAppearance() -> Appearance {
        let auto = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyleSwitchesAutomatically"] as? Bool ?? false
        if auto { return .auto }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    // MARK: - Keep awake (caffeinate)

    func toggleAwake() {
        if isAwake {
            caffeinate?.terminate()
            caffeinate = nil
            isAwake = false
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            // Prevent display + idle sleep, until we exit (even if we crash).
            p.arguments = ["-d", "-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
            try? p.run()
            caffeinate = p
            isAwake = true
        }
    }

    // MARK: - Sleep display

    func sleepDisplay() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }
}
