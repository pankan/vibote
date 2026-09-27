import AppKit
import Foundation

/// A third-party dictation app Vibote can drive. Apps with direct control are started and stopped by Vibote;
/// the rest are driven by holding their hotkey. In every case the app records from Vibote Mic.
struct VoiceApp: Identifiable, Hashable {
    enum Control: Hashable {
        /// Handy: SIGUSR2 / `--toggle-transcription` (see HandyBridge).
        case handy
        /// URL deep links that start and stop recording without focusing the app.
        case deepLink(start: String, stop: String)
        /// Hold the app's hotkey while the remote button is held.
        case hotkey
    }
    let id: String
    let name: String
    /// Known bundle identifiers; the app is also found by its name in /Applications.
    let bundleIDs: [String]
    let control: Control
    let website: String
    /// Extra setup note shown under the picker.
    var note: String = ""

    var isDirect: Bool { control != .hotkey }
}

let voiceApps: [VoiceApp] = [
    VoiceApp(id: "handy", name: "Handy", bundleIDs: ["com.pais.handy"], control: .handy, website: "https://handy.computer",
             note: "Free, open source, local Whisper and Parakeet models."),
    VoiceApp(id: "wispr", name: "Wispr Flow", bundleIDs: ["com.electron.wispr-flow"],
             control: .deepLink(start: "wispr-flow://start-hands-free", stop: "wispr-flow://stop-hands-free"), website: "https://wisprflow.ai",
             note: "Driven through Wispr Flow’s hands-free deep links."),
    VoiceApp(id: "superwhisper", name: "Superwhisper", bundleIDs: ["com.superduper.superwhisper"],
             // `record` starts recording; switching mode ends it (the documented stop link is unpublished).
             control: .deepLink(start: "superwhisper://record", stop: "superwhisper://mode"), website: "https://superwhisper.com",
             note: "Driven through Superwhisper deep links (beta). If stopping doesn’t work, switch it to Other app · hotkey."),
    VoiceApp(id: "voiceink", name: "VoiceInk", bundleIDs: ["com.prakashjoshipax.VoiceInk"], control: .hotkey, website: "https://tryvoiceink.com"),
    VoiceApp(id: "spokenly", name: "Spokenly", bundleIDs: [], control: .hotkey, website: "https://spokenly.app"),
    VoiceApp(id: "macwhisper", name: "MacWhisper", bundleIDs: ["com.goodsnooze.MacWhisper"], control: .hotkey, website: "https://goodsnooze.gumroad.com/l/macwhisper"),
    VoiceApp(id: "aqua", name: "Aqua Voice", bundleIDs: [], control: .hotkey, website: "https://withaqua.com"),
    VoiceApp(id: "openwhispr", name: "OpenWhispr", bundleIDs: [], control: .hotkey, website: "https://openwhispr.com"),
    VoiceApp(id: "monologue", name: "Monologue", bundleIDs: [], control: .hotkey, website: "https://monologue.to"),
    VoiceApp(id: "willow", name: "Willow Voice", bundleIDs: [], control: .hotkey, website: "https://willowvoice.com"),
    VoiceApp(id: "other", name: "Other app", bundleIDs: [], control: .hotkey, website: "",
             note: "Any dictation app: pick the hotkey it listens for."),
]

final class VoiceAppManager: ObservableObject {
    @Published private(set) var installed: Set<String> = []
    @Published var message = ""

    func refresh() {
        let folders = ["/Applications", NSHomeDirectory() + "/Applications"]
        installed = Set(voiceApps.filter { app in
            app.bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
                || folders.contains { FileManager.default.fileExists(atPath: "\($0)/\(app.name).app") }
        }.map(\.id))
    }

    /// Opens a deep link in the background so the app you're typing into keeps focus.
    func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.message = "Couldn't reach the app: \(error.localizedDescription)" } }
        }
    }

    /// Asks Wispr Flow to record from Vibote Mic.
    func useViboteMicInWispr() {
        open("wispr-flow://switch-mic?mic_name=Vibote%20Mic")
        message = "Asked Wispr Flow to use Vibote Mic."
    }
}
