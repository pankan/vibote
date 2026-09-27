import SwiftUI
import AppKit
import IOKit.hid
import CoreBluetooth
import Speech

/// A supported remote. Add new models here as more remotes are supported.
struct RemoteModel { let name: String; let vendorID: Int; let productID: Int; let bluetoothName: String; let buttons: [FrontButton] }
/// A front-panel button. `source` is the HID usage macOS remaps (page << 32 | usage); `raw` is how IOHIDManager reports a press.
struct FrontButton: Identifiable { let id: String; let name: String; let source: UInt64; let raw: String }
let supportedRemote = RemoteModel(name: "T6 Remote", vendorID: 0x620a, productID: 0x0407, bluetoothName: "T6", buttons: [
    // Assistant sends a momentary Search tap (000C:0221) plus key 0xAA that stays down while held.
    FrontButton(id: "assistant", name: "Assistant", source: 0x7000000AA, raw: "0007:00AA"),
    FrontButton(id: "home", name: "Home", source: 0xC00000223, raw: "000C:0223"),
    FrontButton(id: "back", name: "Back", source: 0xC00000224, raw: "000C:0224"),
    FrontButton(id: "menu", name: "Menu", source: 0xC00000040, raw: "000C:0040"),
    FrontButton(id: "volup", name: "Volume +", source: 0xC000000E9, raw: "000C:00E9"),
    FrontButton(id: "voldown", name: "Volume −", source: 0xC000000EA, raw: "000C:00EA"),
])
let frontButtons = supportedRemote.buttons
/// Assistant's Search tap opens Spotlight; always send it to F24 instead.
let searchTap: UInt64 = 0xC00000221
let unusedKey: UInt64 = 0x700000073 // F24

enum ButtonMode: String, Codable, CaseIterable {
    var icon: String { ["Default": "circle.dashed", "Keyboard key": "keyboard", "Shortcut": "command", "Open app": "app.badge", "Remote mic": "mic.fill"][rawValue] ?? "circle" }
    case standard = "Default", key = "Keyboard key", shortcut = "Shortcut", app = "Open app"
    /// Hold to use the remote mic. Advanced settings choose Mac transcription or the Vibote Mic device.
    case dictation = "Remote mic"
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Earlier builds saved separate "Remote dictation" / "Remote mic + key" modes.
        self = ButtonMode(rawValue: raw) ?? (raw.hasPrefix("Remote") ? .dictation : .standard)
    }
}
/// What a Remote mic button does with the remote's audio.
enum VoiceMode: String, CaseIterable {
    case onDevice = "On-device transcription"
    case voiceApp = "AI voice app"
    var detail: String {
        switch self {
        case .onDevice: return "Hold, speak, release: Apple on-device speech recognition types the text into the focused app. Nothing leaves your Mac."
        case .voiceApp: return "Holding streams the remote to “Vibote Mic” and starts your voice app, directly or by holding its hotkey; the app types the text. Select Vibote Mic as that app’s microphone."
        }
    }
    var available: Bool { true }
    var icon: String { switch self { case .onDevice: return "waveform"; case .voiceApp: return "sparkles" } }
}
struct ButtonSetting: Codable {
    var mode = ButtonMode.standard; var key: UInt8 = 0xE6; var appPath = ""
    // Shortcut mode. Optional so settings saved before this mode existed still decode.
    var shortcutKey: UInt8? = 0x1D; var command: Bool? = true; var option: Bool? = false; var control: Bool? = false; var shift: Bool? = false
}

struct KeyOption {
    let name: String; let usage: UInt8
    /// macOS virtual key code, for keys usable in a Shortcut.
    var mac: CGKeyCode? { macKeyCodes[usage] }
}
let macKeyCodes: [UInt8: CGKeyCode] = {
    var map: [UInt8: CGKeyCode] = [0x28: 36, 0x29: 53, 0x2A: 51, 0x2B: 48, 0x2C: 49, 0x52: 126, 0x51: 125, 0x50: 123, 0x4F: 124, 0x4B: 116, 0x4E: 121, 0x4A: 115, 0x4D: 119]
    let letters: [CGKeyCode] = [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6]
    for (i, code) in letters.enumerated() { map[UInt8(0x04 + i)] = code }
    let digits: [CGKeyCode] = [18,19,20,21,23,22,26,28,25,29] // 1…9, 0
    for (i, code) in digits.enumerated() { map[UInt8(0x1E + i)] = code }
    let fkeys: [CGKeyCode] = [122,120,99,118,96,97,98,100,101,109,103,111] // F1…F12
    for (i, code) in fkeys.enumerated() { map[UInt8(0x3A + i)] = code }
    return map
}()
let keyOptions: [KeyOption] = [
    ("Right Option", 0xE6), ("Right Command", 0xE7), ("Right Control", 0xE4), ("Right Shift", 0xE5),
    ("Left Option", 0xE2), ("Left Command", 0xE3), ("Left Control", 0xE0), ("Left Shift", 0xE1),
    ("Return", 0x28), ("Escape", 0x29), ("Delete", 0x2A), ("Tab", 0x2B), ("Space", 0x2C),
    ("Up", 0x52), ("Down", 0x51), ("Left", 0x50), ("Right", 0x4F), ("Page Up", 0x4B), ("Page Down", 0x4E), ("Home key", 0x4A), ("End", 0x4D),
].map { KeyOption(name: $0.0, usage: $0.1) }
    + (1...12).map { KeyOption(name: "F\($0)", usage: UInt8(0x39 + $0)) }
    + (13...24).map { KeyOption(name: "F\($0)", usage: UInt8(0x67 + $0 - 12)) }
    + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated().map { KeyOption(name: String($0.element), usage: UInt8(0x04 + $0.offset)) }
    + (0...9).map { KeyOption(name: "\($0)", usage: $0 == 0 ? 0x27 : UInt8(0x1D + $0)) }

final class Controller: ObservableObject {
    @Published var connected = false
    @Published var status = "Starting…"
    @Published var events: [String] = []
    @Published var deviceInfo = "Waiting for \(supportedRemote.name)"
    @Published var canListen = false
    /// Button id currently held on the remote, for highlighting it in the map.
    @Published var held: String?
    @Published var canSend = false
    /// Remote-mic buttons: on-device transcription (default), or stream to Vibote Mic while holding `micKey` for a voice app.
    @Published var voiceMode = VoiceMode.onDevice {
        didSet { UserDefaults.standard.set(voiceMode.rawValue, forKey: "voiceMode"); applyRemap() }
    }
    var useMacTranscription: Bool { voiceMode == .onDevice }
    /// The voice app used when `voiceMode` is `.voiceApp` (an id from `voiceApps`).
    @Published var voiceAppID = UserDefaults.standard.string(forKey: "voiceApp") ?? "handy" {
        didSet { UserDefaults.standard.set(voiceAppID, forKey: "voiceApp"); applyRemap() }
    }
    var voiceApp: VoiceApp { voiceApps.first { $0.id == voiceAppID } ?? voiceApps[0] }
    @Published var micKey = UInt8(UserDefaults.standard.object(forKey: "micKey") as? Int ?? 0xE6) {
        didSet { UserDefaults.standard.set(Int(micKey), forKey: "micKey"); applyRemap() }
    }
    @Published var settings: [String: ButtonSetting] = [:] { didSet { save(); applyRemap() } }
    private var manager: IOHIDManager!
    private var pressed = Set<String>()
    private var attached = Set<UInt64>()
    private var motionTime = Date.distantPast
    /// Called with (mode, isDown) when a hold-to-talk button is pressed or released.
    var onHold: ((ButtonMode, Bool) -> Void)?

    init() {
        // Carry settings over from the app's previous name (T6 Controller).
        let defaults = UserDefaults.standard
        if defaults.data(forKey: "buttonSettings") == nil, let old = UserDefaults(suiteName: "local.t6.controller") {
            for key in ["buttonSettings", "micKey"] { if let value = old.object(forKey: key) { defaults.set(value, forKey: key) } }
        }
        // Earlier builds stored a Bool toggle; false meant the voice-app route.
        let storedMode = defaults.string(forKey: "voiceMode")
        if storedMode == "Handy AI transcription" { voiceMode = .voiceApp; voiceAppID = "handy" } // Handy was its own mode before the app registry
        else { voiceMode = storedMode.flatMap(VoiceMode.init) ?? ((defaults.object(forKey: "useMacTranscription") as? Bool) == false ? .voiceApp : .onDevice) }
        // Before the registry, "AI voice app" always meant holding a hotkey.
        if voiceMode == .voiceApp && defaults.string(forKey: "voiceApp") == nil && storedMode != "Handy AI transcription" { voiceAppID = "other" }
        micKey = UInt8(defaults.object(forKey: "micKey") as? Int ?? 0xE6)
        if let data = UserDefaults.standard.data(forKey: "buttonSettings"), let saved = try? JSONDecoder().decode([String: ButtonSetting].self, from: data) { settings = saved }
        else { settings = defaultSettings }
    }
    /// Assistant → remote dictation (hold-to-talk), Home → F11 (Show Desktop), Back → ⌘Z (Undo). Menu, volume, OK and arrows keep their native behavior.
    let defaultSettings: [String: ButtonSetting] = [
        "assistant": ButtonSetting(mode: .dictation, key: 0xE6),
        "home": ButtonSetting(mode: .key, key: 0x44),
        "back": ButtonSetting(mode: .shortcut, shortcutKey: 0x1D, command: true),
    ]
    func update(_ id: String, _ change: (inout ButtonSetting) -> Void) { var s = setting(id); change(&s); settings[id] = s }
    func setting(_ id: String) -> ButtonSetting { settings[id] ?? ButtonSetting() }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: "buttonSettings") }

    /// Applies key remaps for this remote only. macOS clears them when the remote reconnects, so this also runs on every attach.
    func applyRemap() {
        var pairs: [(UInt64, UInt64)] = [(searchTap, unusedKey)]
        for button in frontButtons {
            let s = setting(button.id)
            switch s.mode {
            case .standard: break
            case .key: pairs.append((button.source, 0x700000000 | UInt64(s.key)))
            // Only hotkey-driven voice apps hold a key; directly controlled apps are started by Vibote.
            case .dictation: pairs.append((button.source, voiceMode == .voiceApp && voiceApp.control == .hotkey ? 0x700000000 | UInt64(micKey) : unusedKey))
            case .app, .shortcut: pairs.append((button.source, unusedKey)) // silence the original key; handled on press below
            }
        }
        let list = pairs.map { String(format: #"{"HIDKeyboardModifierMappingSrc":0x%llX,"HIDKeyboardModifierMappingDst":0x%llX}"#, $0.0, $0.1) }.joined(separator: ",")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        task.arguments = ["property", "--matching", "{\"VendorID\":\(supportedRemote.vendorID),\"ProductID\":\(supportedRemote.productID)}", "--set", #"{"UserKeyMapping":["# + list + "]}"]
        task.standardOutput = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit(); if task.terminationStatus != 0 { status = "Couldn't apply key mapping (hidutil \(task.terminationStatus))." } }
        catch { status = "hidutil unavailable: \(error.localizedDescription)" }
    }
    func resetRemap() {
        settings = defaultSettings
        voiceMode = .onDevice
        status = "Restored: Assistant → Mac transcription, Home → Show Desktop (F11), Back → Undo."
    }

    func connect() {
        guard manager == nil else { return }
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: supportedRemote.vendorID, kIOHIDProductIDKey: supportedRemote.productID] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let model = Unmanaged<Controller>.fromOpaque(ctx).takeUnretainedValue()
            model.attached.insert(UInt64(IOHIDDeviceGetService(device)))
            model.connected = true
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? supportedRemote.name
            model.deviceInfo = name
            model.applyRemap()
            model.status = model.canListen ? "Remote connected. Mappings applied." : "Remote connected. Keyboard keys applied; allow Input Monitoring for Shortcut and Open app."
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let model = Unmanaged<Controller>.fromOpaque(ctx).takeUnretainedValue()
            model.attached.remove(UInt64(IOHIDDeviceGetService(device)))
            model.connected = !model.attached.isEmpty
            model.pressed.removeAll()
            if !model.connected { model.status = "Remote disconnected. Mappings return when it reconnects." }
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            guard let ctx else { return }
            Unmanaged<Controller>.fromOpaque(ctx).takeUnretainedValue().receive(value)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        applyRemap()
        refreshPermissions(prompt: true)
        let result = IOHIDManagerOpen(manager, 0)
        status = result == kIOReturnSuccess ? "Listening for the remote…" : "Keyboard remaps are active, but reading buttons failed (\(result)). Allow Input Monitoring for “Open app” and relaunch."
    }
    func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element), usage = IOHIDElementGetUsage(element)
        let amount = IOHIDValueGetIntegerValue(value)
        let key = String(format: "%04X:%04X", page, usage)
        if page == 1 && [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x38].contains(usage) {
            if Date().timeIntervalSince(motionTime) > 0.15 { log("Motion \(key) = \(amount)"); motionTime = Date() }
            return
        }
        guard [7, 9, 12].contains(page), usage != 0, usage != 0xFFFFFFFF else { return }
        if amount == 0 {
            pressed.remove(key)
            if let button = frontButtons.first(where: { $0.raw == key }) {
                if button.id == held { held = nil }
                let mode = setting(button.id).mode
                if mode == .dictation { onHold?(mode, false) }
            }
            return
        }
        guard pressed.insert(key).inserted else { return }
        let button = frontButtons.first { $0.raw == key }
        log("Button \(key)" + (button.map { " · \($0.name)" } ?? ""))
        guard let button else { return }
        held = button.id
        switch setting(button.id).mode {
        case .app: openApp(for: button)
        case .shortcut: sendShortcut(setting(button.id), name: button.name)
        case .dictation: onHold?(setting(button.id).mode, true)
        default: break
        }
    }
    /// Types text into the focused app as keyboard input (no clipboard use).
    func type(_ text: String) {
        guard !text.isEmpty else { status = "Nothing recognized."; return }
        guard AXIsProcessTrusted() else { status = "Allow Accessibility to type dictated text."; return }
        let source = CGEventSource(stateID: .privateState)
        let units = Array(text.utf16)
        for start in stride(from: 0, to: units.count, by: 20) {
            var chunk = Array(units[start..<min(start + 20, units.count)])
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event?.post(tap: .cghidEventTap)
            }
        }
        status = "Typed: \(text)"
    }
    private func sendShortcut(_ s: ButtonSetting, name: String) {
        guard AXIsProcessTrusted() else { status = "\(name): allow Accessibility to send shortcuts, then relaunch."; return }
        guard let code = macKeyCodes[s.shortcutKey ?? 0x1D] else { return }
        var flags: CGEventFlags = []
        if s.command == true { flags.insert(.maskCommand) }
        if s.option == true { flags.insert(.maskAlternate) }
        if s.control == true { flags.insert(.maskControl) }
        if s.shift == true { flags.insert(.maskShift) }
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] { let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down); event?.flags = flags; event?.post(tap: .cghidEventTap) }
        log("  → sent \(name) shortcut")
    }
    private func openApp(for button: FrontButton) {
        let path = setting(button.id).appPath
        guard !path.isEmpty else { status = "\(button.name): choose an app first."; return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.status = "Couldn't open app: \(error.localizedDescription)" } }
        }
    }
    /// Short label for the map callouts.
    func summary(_ button: FrontButton) -> String {
        let s = setting(button.id)
        switch s.mode {
        case .standard: return ["menu": "Right-click", "volup": "Volume up", "voldown": "Volume down"][button.id] ?? "Nothing"
        case .key: return keyOptions.first { $0.usage == s.key }?.name ?? "Key"
        case .shortcut:
            let mods = (s.control == true ? "⌃" : "") + (s.option == true ? "⌥" : "") + (s.shift == true ? "⇧" : "") + (s.command == true ? "⌘" : "")
            return mods + (keyOptions.first { $0.usage == s.shortcutKey }?.name ?? "?")
        case .dictation:
            switch voiceMode {
            case .onDevice: return "On-device dictation"
            case .voiceApp: return voiceApp.isDirect ? voiceApp.name : voiceApp.name + " · " + (keyOptions.first { $0.usage == micKey }?.name ?? "key")
            }
        case .app: return s.appPath.isEmpty ? "Choose app" : FileManager.default.displayName(atPath: s.appPath)
        }
    }
    func chooseApp(for button: FrontButton) {
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.application]; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { settings[button.id, default: ButtonSetting()].appPath = url.path }
    }
    /// Rebuilding re-signs the app, which can silently invalidate earlier grants, so check them directly.
    func refreshPermissions(prompt: Bool = false) {
        if prompt {
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        canListen = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        canSend = AXIsProcessTrusted()
    }
    func log(_ message: String) { events.insert(message, at: 0); if events.count > 80 { events.removeLast(events.count - 80) } }
    func permissions(_ pane: String) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!) }
}

struct ButtonRow: View {
    let button: FrontButton
    @ObservedObject var model: Controller
    private func flag(_ value: SwiftUI.Binding<Bool?>) -> SwiftUI.Binding<Bool> { SwiftUI.Binding(get: { value.wrappedValue ?? false }, set: { value.wrappedValue = $0 }) }
    var body: some View {
        let binding = SwiftUI.Binding(get: { model.setting(button.id) }, set: { model.settings[button.id] = $0 })
        HStack(spacing: 12) {
            Picker("", selection: binding.mode) { ForEach(ButtonMode.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.icon).tag($0) } }.labelsHidden().frame(width: 160)
            switch binding.wrappedValue.mode {
            case .standard: Text(button.id == "assistant" ? "Does nothing (Spotlight disabled)" : "Original remote behavior").foregroundStyle(.secondary)
            case .dictation:
                Text("Uses the voice mode below.").foregroundStyle(.secondary)
            case .key: Picker("", selection: binding.key) { ForEach(keyOptions, id: \.usage) { Text($0.name).tag($0.usage) } }.labelsHidden().frame(width: 160)
            case .shortcut:
                Toggle("⌘", isOn: flag(binding.command)); Toggle("⌥", isOn: flag(binding.option)); Toggle("⌃", isOn: flag(binding.control)); Toggle("⇧", isOn: flag(binding.shift))
                Picker("", selection: binding.shortcutKey) { ForEach(keyOptions.filter { $0.mac != nil }, id: \.usage) { Text($0.name).tag(Optional($0.usage)) } }.labelsHidden().frame(width: 110)
            case .app:
                Button("Choose app…") { model.chooseApp(for: button) }
                let path = binding.wrappedValue.appPath
                Text(path.isEmpty ? "No app chosen" : FileManager.default.displayName(atPath: path)).foregroundStyle(path.isEmpty ? .secondary : .primary)
            }
            Spacer()
        }
    }
}

/// Vector drawing of the remote front panel. Mappable buttons are clickable; the map labels sit beside them.
/// Common shortcuts offered directly in the map menus: name, key usage, ⌘, ⇧.
let quickShortcuts: [(String, UInt8, Bool, Bool)] = [
    ("Undo ⌘Z", 0x1D, true, false), ("Redo ⇧⌘Z", 0x1D, true, true), ("Copy ⌘C", 0x06, true, false), ("Paste ⌘V", 0x19, true, false),
    ("Cut ⌘X", 0x1B, true, false), ("Select all ⌘A", 0x04, true, false), ("Save ⌘S", 0x16, true, false), ("Find ⌘F", 0x09, true, false),
    ("New tab ⌘T", 0x17, true, false), ("Close tab ⌘W", 0x1A, true, false), ("Command palette ⇧⌘P", 0x13, true, true), ("Send ⌘Return", 0x28, true, false),
]

/// Segmented input-level meter, matching the native macOS audio settings style.
struct LevelMeter: View {
    let level: Float
    private let segmentCount = 20
    private var normalizedLevel: Float {
        level.isFinite ? sqrt(min(1, max(0, level))) : 0
    }
    var body: some View {
        let litSegments = Int((normalizedLevel * Float(segmentCount)).rounded(.up))
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index < litSegments ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 12)
        .animation(.linear(duration: 0.08), value: litSegments)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone input level")
        .accessibilityValue("\(Int(normalizedLevel * 100)) percent")
    }
}

/// Rounded cross traced as a single outline, as printed on the T6 navigation pad.
struct RemoteCross: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0.33, y: 0), CGPoint(x: 0.67, y: 0),
            CGPoint(x: 0.67, y: 0.33), CGPoint(x: 1, y: 0.33),
            CGPoint(x: 1, y: 0.67), CGPoint(x: 0.67, y: 0.67),
            CGPoint(x: 0.67, y: 1), CGPoint(x: 0.33, y: 1),
            CGPoint(x: 0.33, y: 0.67), CGPoint(x: 0, y: 0.67),
            CGPoint(x: 0, y: 0.33), CGPoint(x: 0.33, y: 0.33)
        ].map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        var path = Path()
        let radius: CGFloat = 11
        for i in points.indices {
            let previous = points[(i + points.count - 1) % points.count]
            let corner = points[i], next = points[(i + 1) % points.count]
            func inset(toward point: CGPoint) -> CGPoint {
                let dx = point.x - corner.x, dy = point.y - corner.y
                let length = hypot(dx, dy)
                return CGPoint(x: corner.x + dx / length * radius, y: corner.y + dy / length * radius)
            }
            let entry = inset(toward: previous), exit = inset(toward: next)
            if i == 0 { path.move(to: entry) } else { path.addLine(to: entry) }
            path.addQuadCurve(to: exit, control: corner)
        }
        path.closeSubpath()
        return path
    }
}

struct RemoteMap: View {
    @ObservedObject var model: Controller
    @Binding var selected: String
    var level: Float = 0
    private let key = Color(white: 0.23), purple = Color(red: 0.34, green: 0.08, blue: 0.66)
    // Photo proportions: a long charcoal shell with all controls in its upper two thirds.
    private let spots: [String: CGPoint] = ["assistant": CGPoint(x: 216, y: 300), "home": CGPoint(x: 304, y: 300), "back": CGPoint(x: 216, y: 369), "menu": CGPoint(x: 216, y: 438), "volup": CGPoint(x: 304, y: 369), "voldown": CGPoint(x: 304, y: 438)]
    private let icons = ["home": "house", "back": "arrow.uturn.backward", "menu": "line.3.horizontal", "volup": "plus", "voldown": "minus"]

    var body: some View {
        ZStack {
            shell.position(x: 260, y: 350)
            fixed("power", at: CGPoint(x: 216, y: 72))
            fixed("computermouse", at: CGPoint(x: 304, y: 72))
            Capsule().fill(.black).frame(width: 4, height: 14).position(x: 260, y: 72)
            Circle().fill(.black).frame(width: 4, height: 4).position(x: 260, y: 105)
                .accessibilityLabel("Microphone opening")
            dpad.position(x: 260, y: 187)
            Capsule().fill(key)
                .overlay(Capsule().stroke(.black.opacity(0.8), lineWidth: 1.5))
                .frame(width: 53, height: 122).position(x: 304, y: 403.5)
            ForEach(frontButtons) { button in
                if let point = spots[button.id] { mappable(button, at: point) }
            }
            callout("Power", at: CGPoint(x: 216, y: 72), left: true, dim: true)
            callout("Air mouse", at: CGPoint(x: 304, y: 72), left: false, dim: true)
            callout("Arrows · OK = Return", at: CGPoint(x: 187, y: 187), left: true, dim: true)
        }.frame(width: 520, height: 700)
    }
    private var shell: some View {
        RoundedRectangle(cornerRadius: 51, style: .continuous)
            .fill(Color(white: 0.08))
            .overlay(RoundedRectangle(cornerRadius: 49, style: .continuous).stroke(Color(white: 0.38), lineWidth: 1).padding(3))
            .overlay {
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .fill(Color(white: 0.18))
                    .overlay(RoundedRectangle(cornerRadius: 46, style: .continuous).stroke(.black.opacity(0.6), lineWidth: 3))
                    .padding(7)
            }
            .frame(width: 196, height: 660)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 5)
    }
    private var dpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(purple)
                .overlay(RoundedRectangle(cornerRadius: 42, style: .continuous).stroke(Color.black.opacity(0.65), lineWidth: 2))
            // One continuous rounded cross, without seams through the OK button.
            RemoteCross().stroke(Color(white: 0.92), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round)).padding(7)
            RoundedRectangle(cornerRadius: 17).fill(purple)
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(.black.opacity(0.65), lineWidth: 2))
                .frame(width: 48, height: 48)
            Text("OK").font(.system(size: 17, weight: .medium, design: .monospaced)).foregroundStyle(Color(white: 0.94))
            ForEach([("arrowtriangle.up", 0.0, -47.0), ("arrowtriangle.down", 0, 47), ("arrowtriangle.left", -47, 0), ("arrowtriangle.right", 47, 0)], id: \.0) { icon, x, y in
                Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(Color(white: 0.94)).offset(x: x, y: y)
            }
        }.frame(width: 146, height: 143)
    }
    /// Dot positions match the printed Assistant mark on the physical remote.
    private var assistantDots: some View {
        ZStack {
            Circle().fill(.white).frame(width: 12, height: 12).offset(x: -6, y: -4)
            Circle().fill(.white).frame(width: 6, height: 6).offset(x: 4, y: 0)
            Circle().fill(.white).frame(width: 7, height: 7).offset(x: 4, y: 8)
            Circle().fill(.white).frame(width: 3, height: 3).offset(x: 9, y: -5)
        }
    }
    private func buttonFace(_ color: Color) -> some View {
        Circle().fill(color)
            .overlay(Circle().stroke(.black.opacity(0.8), lineWidth: 1.5))

    }
    private func fixed(_ icon: String, at point: CGPoint) -> some View {
        buttonFace(purple).frame(width: 52, height: 52)
            .overlay {
                HStack(spacing: 1) {
                    if icon == "computermouse" { Text("〃").font(.system(size: 15)) }
                    Image(systemName: icon).font(.system(size: icon == "power" ? 24 : 20, weight: .regular))
                    if icon == "computermouse" { Text("〃").font(.system(size: 15)) }
                }.foregroundStyle(Color(white: 0.94))
            }.position(point)
    }
    private func mappable(_ button: FrontButton, at point: CGPoint) -> some View {
        let isSelected = selected == button.id, isHeld = model.held == button.id
        let volume = button.id.hasPrefix("vol")
        return Button { selected = button.id } label: {
            Group {
                // Volume is one silicone rocker; circles and symbols are printed on its face.
                // Keep separate hit targets and held feedback for its two actions.
                if volume { Circle().fill(isHeld ? purple : .clear) }
                else { buttonFace(isHeld ? purple : key) }
            }
                .overlay(Circle().stroke(volume ? Color(white: 0.94) : .clear, lineWidth: 1.8).padding(5))
                .overlay(Group {
                    if button.id == "assistant" { assistantDots } else { Image(systemName: icons[button.id] ?? "circle").font(.system(size: 22, weight: .regular)).foregroundStyle(Color(white: 0.94)) }
                })
                .overlay(Circle().stroke(Color.accentColor, lineWidth: isSelected ? 2 : 0).padding(-4))
                // Mic level ring on remote-mic buttons while streaming.
                .overlay(Circle().stroke(Color.green.opacity(0.9), lineWidth: 3).padding(-5 - CGFloat(sqrt(level)) * 14).opacity(model.setting(button.id).mode == .dictation && level > 0.01 ? 1 : 0))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(button.name).accessibilityLabel(button.name)
        .position(point)
        .background(callout(model.summary(button), at: point, left: point.x < 260, dim: model.setting(button.id).mode == .standard, title: button.name, selected: isSelected, menu: button))
    }
    /// Everything a button can be set to, editable straight from its label on the map.
    @ViewBuilder private func mappingMenu(_ button: FrontButton) -> some View {
        let id = button.id
        Button("Default", systemImage: ButtonMode.standard.icon) { model.update(id) { $0.mode = .standard } }
        Menu("Keyboard key", systemImage: ButtonMode.key.icon) {
            ForEach(keyOptions, id: \.usage) { option in Button(option.name) { model.update(id) { $0.mode = .key; $0.key = option.usage } } }
        }
        Menu("Shortcut", systemImage: ButtonMode.shortcut.icon) {
            ForEach(quickShortcuts, id: \.0) { item in
                Button(item.0) { model.update(id) { $0.mode = .shortcut; $0.shortcutKey = item.1; $0.command = item.2; $0.shift = item.3; $0.option = false; $0.control = false } }
            }
            Divider()
            Button("Custom…") { model.update(id) { $0.mode = .shortcut }; selected = id }
        }
        Button("Open app…", systemImage: ButtonMode.app.icon) { model.update(id) { $0.mode = .app }; model.chooseApp(for: button) }
        Menu("Remote mic", systemImage: ButtonMode.dictation.icon) {
            Button("On-device transcription (default)", systemImage: VoiceMode.onDevice.icon) { model.update(id) { $0.mode = .dictation }; model.voiceMode = .onDevice }
            Menu("AI voice app", systemImage: VoiceMode.voiceApp.icon) {
                ForEach(voiceApps) { app in
                    Button(app.name + (app.isDirect ? "" : " · hotkey")) { model.update(id) { $0.mode = .dictation }; model.voiceAppID = app.id; model.voiceMode = .voiceApp; selected = id }
                }
            }
        }
    }
    private func callout(_ text: String, at point: CGPoint, left: Bool, dim: Bool, title: String? = nil, selected: Bool = false, menu button: FrontButton? = nil) -> some View {
        let lineStart = left ? point.x - 40 : point.x + 40, lineEnd = left ? 140.0 : 380.0
        return ZStack {
            Path { $0.move(to: CGPoint(x: lineStart, y: point.y)); $0.addLine(to: CGPoint(x: lineEnd, y: point.y)) }
                .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            let label = VStack(alignment: left ? .trailing : .leading, spacing: 1) {
                if let title { Text(title).font(.caption2).foregroundStyle(.secondary) }
                HStack(spacing: 3) {
                    if button != nil && !left { Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary) }
                    Text(text).font(.callout.weight(selected ? .bold : .medium)).foregroundStyle(dim ? .secondary : .primary).lineLimit(1)
                    if button != nil && left { Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Group {
                if let button {
                    Menu { mappingMenu(button) } label: { label }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help("Change \(button.name)")
                } else { label }
            }
            .frame(width: 130, alignment: left ? .trailing : .leading)
            .position(x: left ? lineEnd - 70 : lineEnd + 70, y: point.y)
        }
    }
}

/// Native radio controls allow the selected voice-app row to contain its own picker.
struct VoiceModeRadio: NSViewRepresentable {
    let mode: VoiceMode
    @Binding var selection: VoiceMode

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(radioButtonWithTitle: "", target: context.coordinator, action: #selector(Coordinator.selectMode))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.title = mode.rawValue + (mode.available ? "" : " (coming soon)")
        button.state = selection == mode ? .on : .off
        button.isEnabled = mode.available
    }
    final class Coordinator: NSObject {
        var parent: VoiceModeRadio
        init(_ parent: VoiceModeRadio) { self.parent = parent }
        @objc func selectMode() {
            guard parent.mode.available else { return }
            parent.selection = parent.mode
        }
    }
}

/// Prevent the system scroll-edge material from changing the top strip on hover.
struct NoTopScrollEffect: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}

/// Use a solid window background behind the title bar instead of system material.
struct SolidTitleBar: NSViewRepresentable {
    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
        }
    }
    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ view: WindowView, context: Context) {}
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let status: String
    let allowed: Bool
    var actionTitle = "Settings…"
    var restricted = false
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Label(status, systemImage: allowed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.caption).foregroundStyle(allowed ? Color.green : Color.secondary).fixedSize()
            if !allowed {
                Button(actionTitle, action: action).controlSize(.small).disabled(restricted)
            }
        }.padding(.vertical, 10)
    }
}

struct ContentView: View {
    @StateObject var model = Controller()
    @StateObject var bluetooth = BluetoothProbe()
    @StateObject var handy = HandyBridge()
    @StateObject var apps = VoiceAppManager()
    /// True while a hold has started a direct-control recording that the release must stop.
    @State private var appRecording = false
    @State private var selected = "assistant"
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                RemoteMap(model: model, selected: $selected, level: bluetooth.level).padding(.vertical, 20)
            }.modifier(NoTopScrollEffect()).frame(width: 560).background(.purple.opacity(0.05))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    connectionHeader
                    mappingSection
                    voiceSection
                    permissionsSection
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Clear") { model.events.removeAll() }.controlSize(.small)
                            Text(model.events.isEmpty ? "Press a remote button to see its code…" : model.events.prefix(12).joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.top, 8)
                    } label: { Label("Live input monitor", systemImage: "waveform.path.ecg").foregroundStyle(.secondary) }
                }.padding(28)
            }.modifier(NoTopScrollEffect()).background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 1160, minHeight: 740)
        .background(SolidTitleBar().frame(width: 0, height: 0))
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
            handy.refresh(); apps.refresh()
        }
        .onChange(of: model.voiceAppID) { _, _ in prepareVoiceApp() }
        .onChange(of: model.voiceMode) { _, _ in prepareVoiceApp() }
        .onAppear {
            refreshPermissions()
            model.connect()
            bluetooth.inspect() // connect the remote mic up front so holds start fast
            handy.refresh(); apps.refresh()
            prepareVoiceApp()
            model.onHold = { _, down in
                if model.voiceMode == .onDevice {
                    if down { bluetooth.beginHold(transcribe: true) } else { bluetooth.endHold { text in model.type(text) } }
                    return
                }
                let app = model.voiceApp
                if down {
                    bluetooth.beginHold(transcribe: false)
                    switch app.control {
                    case .handy: appRecording = handy.toggle()
                    case .deepLink(let start, _): apps.open(start); appRecording = true
                    case .hotkey: appRecording = false // the remapped hotkey is held by macOS itself
                    }
                } else {
                    // Let the last words reach the app before stopping it, then close the stream.
                    let started = appRecording; appRecording = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if started {
                            switch app.control {
                            case .handy: handy.toggle()
                            case .deepLink(_, let stop): apps.open(stop)
                            case .hotkey: break
                            }
                        }
                        bluetooth.endHold()
                    }
                }
            }
        }
    }

    /// Keeps Handy launched in the background when it's the selected app, so its model stays loaded.
    private func prepareVoiceApp() {
        guard model.voiceMode == .voiceApp, model.voiceAppID == "handy" else { return }
        handy.refresh()
        if handy.installed && !handy.running { handy.open() }
    }

    private func refreshPermissions() {
        model.refreshPermissions()
        bluetooth.refreshPermissions()
    }

    private var connectionHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your remote").font(.title2.bold())
                    HStack(spacing: 6) {
                        Circle().fill(model.connected ? Color.green : Color.secondary).frame(width: 7, height: 7)
                        Text("\(supportedRemote.name) · \(model.connected ? "Connected" : "Not connected")").font(.subheadline).foregroundStyle(.secondary)
                        if let battery = bluetooth.batteryPercentage {
                            Text("·").foregroundStyle(.tertiary)
                            Label("\(battery)%", systemImage: battery <= 20 ? "battery.25percent" : "battery.100percent")
                                .font(.subheadline).foregroundStyle(battery <= 20 ? Color.orange : Color.secondary)
                                .accessibilityLabel("Remote battery \(battery) percent")
                        }
                    }
                }
                Spacer()
                Button("Restore defaults", systemImage: "arrow.counterclockwise") { model.resetRemap() }.controlSize(.small)
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mappingSection: some View {
        SettingsCard(title: "Button action") {
            if let button = frontButtons.first(where: { $0.id == selected }) {
                HStack(spacing: 10) {
                    Image(systemName: model.setting(button.id).mode.icon).font(.title3).foregroundStyle(.purple)
                        .frame(width: 34, height: 34).background(.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    Text(button.name).font(.headline)
                }
                ButtonRow(button: button, model: model)
                Text("Select a button on the remote to customize its action.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var voiceSection: some View {
        SettingsCard(title: "Voice") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(VoiceMode.allCases, id: \.self) { mode in
                    HStack(spacing: 12) {
                        VoiceModeRadio(mode: mode, selection: $model.voiceMode).fixedSize()
                        if mode == .voiceApp && model.voiceMode == .voiceApp {
                            Picker("", selection: $model.voiceAppID) {
                                Section("Direct control") { ForEach(voiceApps.filter(\.isDirect)) { appRow($0) } }
                                Section("Hotkey") { ForEach(voiceApps.filter { !$0.isDirect }) { appRow($0) } }
                            }.labelsHidden().frame(width: 240).controlSize(.small)
                        }
                    }
                }
            }
            Text(model.voiceMode.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.voiceMode == .voiceApp { voiceAppStatus }
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "mic").foregroundStyle(.secondary)
                LevelMeter(level: bluetooth.level)
                Text(bluetooth.listening ? "Listening" : "Mic idle").font(.caption).foregroundStyle(.secondary).frame(width: 55, alignment: .trailing)
            }
            Text(bluetooth.micStatus).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func appRow(_ app: VoiceApp) -> some View {
        Text(app.name + (apps.installed.contains(app.id) ? "  ✓" : "")).tag(app.id)
    }

    /// Setup for the selected voice app: Handy's checklist, Wispr Flow's mic switch, or a hotkey picker.
    @ViewBuilder private var voiceAppStatus: some View {
        let app = model.voiceApp
        if app.control == .handy { handyStatus }
        else {
            VStack(alignment: .leading, spacing: 8) {
                if app.id != "other" {
                    HStack {
                        let found = apps.installed.contains(app.id)
                        Label(found ? "\(app.name) is installed" : "\(app.name) not found in Applications", systemImage: found ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(found ? Color.green : Color.secondary)
                        Spacer()
                        if !found, let url = URL(string: app.website) { Button("Get \(app.name)…") { NSWorkspace.shared.open(url) }.controlSize(.small) }
                    }
                }
                if app.control == .hotkey {
                    Picker("Hotkey Vibote holds", selection: $model.micKey) { ForEach(keyOptions, id: \.usage) { Text($0.name).tag($0.usage) } }.frame(width: 300)
                    Text("Set the same key as \(app.id == "other" ? "your app’s" : app.name + "’s") push-to-talk shortcut, and choose Vibote Mic as its microphone.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if app.id == "wispr" {
                    HStack {
                        Text("Wispr Flow must record from Vibote Mic.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Use Vibote Mic in Wispr Flow") { apps.useViboteMicInWispr() }.controlSize(.small)
                    }
                } else {
                    Text("Choose Vibote Mic as \(app.name)’s microphone.").foregroundStyle(.secondary)
                }
                if !app.note.isEmpty { Text(app.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if !apps.message.isEmpty { Text(apps.message).foregroundStyle(.secondary) }
            }.font(.caption)
        }
    }

    /// Setup checklist for the Handy route: installed, running, and listening to Vibote Mic.
    @ViewBuilder private var handyStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !handy.installed {
                HStack {
                    Label("Handy isn’t installed", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    Spacer()
                    if handy.installing { ProgressView().controlSize(.small) }
                    Button(handy.brewPath != nil ? "Install Handy" : "Download Handy…", systemImage: "arrow.down.circle") { handy.install() }
                        .controlSize(.small).disabled(handy.installing)
                }
                Text(handy.brewPath != nil ? "Installs the free Handy app with Homebrew (brew install --cask handy)." : "Opens handy.computer to download the free Handy app.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Label(handy.running ? "Handy is running" : "Handy isn’t running", systemImage: handy.running ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(handy.running ? Color.green : Color.secondary)
                    Spacer()
                    Button(handy.running ? "Open Handy" : "Start Handy") { handy.open(showWindow: handy.running) }.controlSize(.small)
                }
                HStack {
                    Label(handy.micReady ? "Handy’s microphone is Vibote Mic" : "Set Handy’s microphone to Vibote Mic", systemImage: handy.micReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(handy.micReady ? Color.green : Color.orange)
                    Spacer()
                    Button("Recheck", systemImage: "arrow.clockwise") { handy.refresh() }.controlSize(.small)
                }
                if !handy.micReady {
                    Text("In Handy’s settings, choose Vibote Mic as the microphone and download a model. Vibote starts and stops Handy for you; Handy’s own shortcut is not used.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !handy.message.isEmpty { Text(handy.message).font(.caption).foregroundStyle(.secondary) }
        }
        .font(.caption)
    }

    private var permissionsSection: some View {
        SettingsCard(title: "Permissions") {
            VStack(spacing: 0) {
                PermissionRow(title: "Input Monitoring", detail: "Read remote buttons and hold-to-talk.", status: model.canListen ? "Allowed" : "Not allowed", allowed: model.canListen) {
                    model.permissions("Privacy_ListenEvent")
                }
                Divider()
                PermissionRow(title: "Accessibility", detail: "Send shortcuts and type dictated text.", status: model.canSend ? "Allowed" : "Not allowed", allowed: model.canSend) {
                    model.permissions("Privacy_Accessibility")
                }
                Divider()
                PermissionRow(title: "Bluetooth", detail: "Connect remote audio and read battery level.", status: bluetoothPermissionText, allowed: bluetooth.bluetoothAuthorization == .allowedAlways,
                              actionTitle: bluetooth.bluetoothAuthorization == .notDetermined ? "Allow…" : "Settings…",
                              restricted: bluetooth.bluetoothAuthorization == .restricted) {
                    if bluetooth.bluetoothAuthorization == .notDetermined { bluetooth.inspect() }
                    else { model.permissions("Privacy_Bluetooth") }
                }
                if model.voiceMode == .onDevice {
                    Divider()
                    PermissionRow(title: "Speech Recognition", detail: "Transcribe speech on this Mac.", status: speechPermissionText, allowed: bluetooth.speechAuthorization == .authorized,
                                  actionTitle: bluetooth.speechAuthorization == .notDetermined ? "Allow…" : "Settings…",
                                  restricted: bluetooth.speechAuthorization == .restricted) {
                        if bluetooth.speechAuthorization == .notDetermined { bluetooth.requestSpeechPermission() }
                        else { model.permissions("Privacy_SpeechRecognition") }
                    }
                }
            }
            Text(model.voiceMode == .voiceApp ? "Allow microphone access in your voice app and select Vibote Mic as its input." : "Remote audio arrives over Bluetooth; Vibote does not need Mac microphone access.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Updates automatically when you return to Vibote.").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var bluetoothPermissionText: String {
        switch bluetooth.bluetoothAuthorization {
        case .allowedAlways: return "Allowed"
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Not allowed"
        @unknown default: return "Unavailable"
        }
    }
    private var speechPermissionText: String {
        switch bluetooth.speechAuthorization {
        case .authorized: return "Allowed"
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Not allowed"
        @unknown default: return "Unavailable"
        }
    }

}
@main struct ViboteApp: App {
    var body: some Scene { WindowGroup("Vibote") { ContentView() } }
}
