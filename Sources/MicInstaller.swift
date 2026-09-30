import AppKit
import Combine

@MainActor
final class MicInstaller: ObservableObject {
    @Published private(set) var installed = false
    @Published private(set) var installing = false
    @Published private(set) var message = ""

    init() { refresh() }

    func refresh() {
        installed = FileManager.default.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/ViboteMic.driver/Contents/MacOS/ViboteMic")
    }

    func install() {
        guard !installing else { return }
        guard let script = Bundle.main.url(forResource: "install-mic-from-app", withExtension: "sh"),
              let driver = Bundle.main.url(forResource: "ViboteMic", withExtension: "driver") else {
            message = "The microphone installer is missing. Rebuild Vibote with scripts/build.sh."
            return
        }
        installing = true
        message = "Waiting for administrator approval…"
        // Quote separately for the shell and AppleScript; app paths may contain spaces or quotes.
        func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "/bin/bash \(shellQuote(script.path)) \(shellQuote(driver.path))"
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(literal)\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            var failure: String?
            do {
                try process.run()
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let detail = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    failure = detail.contains("(-128)") ? "Installation cancelled." : "Installation failed: \(detail)"
                }
            } catch { failure = "Installation failed: \(error.localizedDescription)" }
            let result = failure
            DispatchQueue.main.async {
                self.installing = false
                self.refresh()
                self.message = result ?? (self.installed ? "Vibote Mic installed. Choose it as your voice app’s microphone." : "Installation finished, but Vibote Mic was not found. Try again.")
            }
        }
    }
}
