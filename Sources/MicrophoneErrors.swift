import Foundation

func microphoneErrorMessage(_ bytes: [UInt8]) -> String {
    guard bytes.count >= 3 else { return "Remote returned an incomplete microphone error. Reconnect and try again." }
    let code = UInt16(bytes[1]) << 8 | UInt16(bytes[2])
    switch code {
    case 0x0f02: return "Remote is asleep. Press a navigation button, then start the microphone again."
    case 0x0f03: return "Remote audio notifications are disabled. Inspect Bluetooth services again."
    case 0x0f80: return "Remote microphone is already active. Release its mic button, then try again."
    default: return String(format: "Remote rejected microphone start (0x%04X). Release its mic button, wake it with a navigation button, then try again.", code)
    }
}
