import AppKit
import Foundation

/// Drives Handy (https://handy.computer, MIT), a local Whisper/Parakeet speech-to-text app.
/// Vibote streams the remote into Vibote Mic and starts/stops Handy through its CLI
/// (SIGUSR2, or `--toggle-transcription` as a fallback); Handy types the text.
final class HandyBridge: ObservableObject {
    static let bundleID = "com.pais.handy"
    private static let downloadPage = URL(string: "https://handy.computer")!

    @Published private(set) var installed = false
    @Published private(set) var running = false
    /// Handy's selected microphone, read from its settings; nil when unknown or unset (Handy then uses the system default).
    @Published private(set) var microphone: String?
    @Published private(set) var installing = false
    @Published var message = ""

    var micReady: Bool { microphone == "Vibote Mic" }
    var brewPath: String? { ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) } }
    private var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) }

    func refresh() {
        installed = appURL != nil
        running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        let store = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.bundleID).appendingPathComponent("settings_store.json")
        if let data = try? Data(contentsOf: store),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let settings = json["settings"] as? [String: Any] {
            microphone = settings["selected_microphone"] as? String
        } else { microphone = nil }
    }

    /// Installs Handy with Homebrew (`brew install --cask handy`), or opens the download page without Homebrew.
    func install() {
        guard let brew = brewPath else { NSWorkspace.shared.open(Self.downloadPage); message = "Download Handy from handy.computer, then come back."; return }
        guard !installing else { return }
        installing = true; message = "Installing Handy with Homebrew…"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: brew)
        task.arguments = ["install", "--cask", "handy"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
        // Drain while the process runs: waiting for termination before reading can
        // deadlock if Homebrew fills the pipe buffer.
        do {
            try task.run()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                let output = String(decoding: data, as: UTF8.self)
                let status = task.terminationStatus
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.installing = false
                    self.refresh()
                    if status == 0 && self.installed {
                        self.message = "Handy installed. Open it once to download a model."
                        self.open(showWindow: true)
                    } else {
                        self.message = "Install failed: " + (output.split(separator: "\n").last.map(String.init) ?? "exit \(status)")
                    }
                }
            }
        } catch { installing = false; message = error.localizedDescription }
    }

    /// Launches Handy (hidden unless `showWindow`) so it can receive toggles and keep its model loaded.
    func open(showWindow: Bool = false) {
        guard let appURL else { refresh(); return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = showWindow
        if !showWindow { configuration.arguments = ["--start-hidden"] }
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    /// Starts or stops a Handy recording in the running instance. Returns false if Handy couldn't be reached
    /// (it is then launched for next time), so callers can skip the matching stop toggle.
    @discardableResult func toggle() -> Bool {
        guard let executable = appURL.flatMap({ Bundle(url: $0)?.executableURL }) else { message = "Handy isn't installed."; return false }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { message = "Starting Handy… hold again in a moment."; open(); return false }
        // Handy toggles plain transcription on SIGUSR2; faster than spawning its CLI for each press.
        if kill(app.processIdentifier, SIGUSR2) == 0 { message = ""; return true }
        let task = Process()
        task.executableURL = executable
        task.arguments = ["--toggle-transcription"]
        do { try task.run(); message = ""; return true } catch { message = "Couldn't reach Handy: \(error.localizedDescription)"; return false }
    }
}
