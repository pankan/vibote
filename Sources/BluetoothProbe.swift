import Foundation
import CoreBluetooth
import Combine
import AVFoundation
import AppKit
import Speech

final class BluetoothProbe: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var lines = ["Remote microphone protocol not verified."]
    @Published var micStatus = "Not connected"
    @Published var sampleCount = 0
    @Published var remoteTranscript = ""
    @Published var listening = false
    @Published var live = false
    @Published private(set) var bluetoothAuthorization = CBManager.authorization
    @Published private(set) var speechAuthorization = SFSpeechRecognizer.authorizationStatus()

    func refreshPermissions() {
        bluetoothAuthorization = CBManager.authorization
        speechAuthorization = SFSpeechRecognizer.authorizationStatus()
    }

    func requestSpeechPermission() {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { refreshPermissions(); return }
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async { self?.refreshPermissions() }
        }
    }

    @Published private(set) var batteryPercentage: Int?
    private let batteryServiceID = CBUUID(string: "180F")
    private let batteryLevelID = CBUUID(string: "2A19")
    private var batteryPoll: Timer?
    /// Remote mic input level, 0…1 (peak with decay), for the meter.
    @Published var level: Float = 0
    /// Called when the front mic button sends an ATV voice-search request (BLE, not HID).
    var onMicButton: (() -> Void)?
    private let bridge = AudioBridge()
    private var keepAlive: Timer?
    private var tx: CBCharacteristic?
    private var rx: CBCharacteristic?
    private var ctl: CBCharacteristic?
    private var version: UInt16?
    private var codec: UInt8 = 2
    private var negotiated = false
    private var openingMic = false
    private var negotiationTimer: Timer?
    private var openingTimer: Timer?
    private var decoder = ADPCM()
    private var pending: [UInt8] = []
    private var rate = 16000.0
    private var voiceTimer: Timer?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var central: CBCentralManager?
    private var remote: CBPeripheral?
    private var timeout: Timer?
    func inspect() {
        guard !listening else { micStatus = "Stop the microphone before reconnecting."; return }
        negotiationTimer?.invalidate()
        clearBattery()
        negotiated = false; version = nil; tx = nil; rx = nil; ctl = nil
        micStatus = "Connecting and checking microphone capabilities…"
        lines = ["Inspecting remote Bluetooth services…"]
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if central?.state == .poweredOn { discover() }
        else { lines.append("Bluetooth unavailable or permission required.") }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        refreshPermissions()
        if central.state == .poweredOn { discover() }
        else { clearBattery(); lines.append("Bluetooth state: \(central.state.rawValue). Allow Bluetooth access in System Settings.") }
    }
    private func discover() {
        guard let central else { return }
        let known = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: "1812")])
        if let device = known.first(where: { $0.name?.localizedCaseInsensitiveContains(supportedRemote.bluetoothName) == true }) { connect(device); return }
        if let id = UUID(uuidString: "74655BCF-7DE6-A84E-498E-8D65CF15D195"), let device = central.retrievePeripherals(withIdentifiers: [id]).first { connect(device); return }
        note("\(supportedRemote.name) not found among connected devices; scanning…")
        central.scanForPeripherals(withServices: nil)
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.central?.stopScan(); self?.lines.append("Scan ended. Wake the remote and inspect again if nothing appeared.")
            self?.micStatus = "Remote not found. Wake it and Inspect again."
        }
    }
    private func connect(_ device: CBPeripheral) {
        central?.stopScan(); timeout?.invalidate(); remote = device; device.delegate = self
        lines.append("Found \(device.name ?? supportedRemote.name). Connecting for service discovery…")
        if device.state == .connected { device.discoverServices(nil) }
        else { central?.connect(device) }
        // CoreBluetooth connection attempts never time out on their own; a sleeping remote would leave inspection stuck.
        timeout = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            guard let self, self.version == nil, !self.negotiated else { return }
            if device.state != .connected { self.central?.cancelPeripheralConnection(device) }
            self.note("Connection timed out (state \(device.state.rawValue)).")
            self.micStatus = "Remote did not respond. Press any remote button to wake it, then Inspect again."
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if peripheral.name?.localizedCaseInsensitiveContains(supportedRemote.bluetoothName) == true { connect(peripheral) }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { peripheral.discoverServices(nil) }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        clearBattery()
        finish(); tx = nil; rx = nil; ctl = nil; version = nil; negotiated = false
        micStatus = "Remote disconnected. Inspect services to reconnect."
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        clearBattery()
        timeout?.invalidate(); lines.append(error?.localizedDescription ?? "Connection failed")
        micStatus = "Connection failed. Wake the remote and Inspect again."
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { lines.append(error.localizedDescription); return }
        for service in peripheral.services ?? [] { lines.append("Service \(service.uuid)"); peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { lines.append(error.localizedDescription); return }
        for characteristic in service.characteristics ?? [] {
            lines.append("  \(characteristic.uuid) properties=\(characteristic.properties.rawValue)")
            if service.uuid == batteryServiceID && characteristic.uuid == batteryLevelID {
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                    batteryPoll?.invalidate()
                    batteryPoll = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self, weak peripheral] _ in
                        guard self != nil, let peripheral, peripheral.state == .connected else { return }
                        peripheral.readValue(for: characteristic)
                    }
                }
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                continue
            }
            switch characteristic.uuid.uuidString.uppercased() {
            case "AB5E0002-5A21-4F05-BC7D-AF01F617B664": tx = characteristic
            case "AB5E0003-5A21-4F05-BC7D-AF01F617B664": rx = characteristic; peripheral.setNotifyValue(true, for: characteristic)
            case "AB5E0004-5A21-4F05-BC7D-AF01F617B664": ctl = characteristic; peripheral.setNotifyValue(true, for: characteristic)
            default: break
            }
        }
        negotiateIfReady()
    }

    private func clearBattery() {
        batteryPoll?.invalidate()
        batteryPoll = nil
        batteryPercentage = nil
    }

    private func note(_ message: String) {
        lines.append(message)
        if lines.count > 100 { lines.removeFirst() }
        // Protocol metadata only; no captured audio or transcripts.
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vibote")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: folder.appendingPathComponent("bluetooth-diagnostics.txt"), atomically: true, encoding: .utf8)
    }
    private func send(_ bytes: [UInt8]) {
        guard let remote, let tx else { return }
        let type: CBCharacteristicWriteType = tx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        remote.writeValue(Data(bytes), for: tx, type: type)
        note("TX " + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
    }
    private func negotiateIfReady() {
        guard tx != nil, rx?.isNotifying == true, ctl?.isNotifying == true, !negotiated else { return }
        negotiated = true; timeout?.invalidate()
        // Request legacy on-demand interaction: inspection never opens the mic.
        micStatus = "Checking remote microphone capabilities…"
        send([0x0a, 0x01, 0x00, 0x00, 0x03, 0x00])
        negotiationTimer?.invalidate()
        negotiationTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self, self.version == nil else { return }
            self.negotiated = false
            self.micStatus = "No capability reply. Wake the remote and click Inspect Bluetooth services again."
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { note("Notify error: " + error.localizedDescription); return }
        negotiateIfReady()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.service?.uuid == batteryServiceID && characteristic.uuid == batteryLevelID {
            guard peripheral == remote else { return }
            batteryPercentage = error == nil ? remoteBatteryPercentage(characteristic.value) : nil
            return
        }
        if let error { note(error.localizedDescription); return }
        let bytes = [UInt8](characteristic.value ?? Data())
        if characteristic == ctl {
            note("CTL " + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
            guard let op = bytes.first else { return }
            switch op {
            case 0x0b:
                negotiationTimer?.invalidate()
                guard bytes.count >= 5 else { return }
                let value = UInt16(bytes[1]) << 8 | UInt16(bytes[2])
                guard value == 4 || value == 0x100 else { micStatus = "Unsupported ATV version \(value)"; return }
                // v0.4 has a two-byte codec mask; v1.0 a one-byte mask.
                let mask = value == 4 ? bytes[4] : bytes[3]
                guard mask & 3 != 0 else { micStatus = "No supported ADPCM codec advertised"; return }
                if value == 4 && (bytes.count < 7 || (Int(bytes[5]) << 8 | Int(bytes[6])) != 134) { micStatus = "Unsupported legacy audio frame size"; return }
                version = value; codec = mask & 2 != 0 ? 2 : 1; rate = codec == 2 ? 16000 : 8000
                micStatus = "Remote mic ready · ATV \(value == 4 ? "0.4" : "1.0") · \(Int(rate)) Hz · test required"
            case 0x04:
                if listening {
                    openingMic = false; openingTimer?.invalidate()
                    decoder = ADPCM(); pending.removeAll()
                    micStatus = live ? "Remote microphone streaming → BlackHole 2ch" : "Receiving remote microphone…"
                }
            case 0x00:
                if listening { finish() }
            case 0x08:
                // The front mic button requests voice search. This is not a rejected host request.
                if let onMicButton { onMicButton() }
                else if !listening && version != nil { micStatus = "Mic button detected. Choose Start live microphone or Transcribe remote mic." }
            case 0x0c:
                guard openingMic else { note("Ignored unsolicited mic status; no host open request pending."); return }
                let detail = microphoneErrorMessage(bytes)
                finish()
                micStatus = detail
            case 0x0a:
                if version == 0x100 && bytes.count >= 7 {
                    guard bytes[6] <= 88 else { return }
                    guard bytes[1] == codec else { stop(); micStatus = "Codec changed; capture stopped to preserve audio timing"; return }
                    decoder.predictor = Int(Int16(bitPattern: UInt16(bytes[4]) << 8 | UInt16(bytes[5])))
                    decoder.index = Int(bytes[6])
                }
            default: break
            }
        } else if characteristic == rx && listening {
            var samples: [Int16] = []
            if version == 4 {
                pending += bytes
                while pending.count >= 134 {
                    let frame = Array(pending.prefix(134)); pending.removeFirst(134)
                    guard frame[5] <= 88 else { micStatus = "Unexpected audio frame; decoding stopped"; stop(); return }
                    decoder.predictor = Int(Int16(bitPattern: UInt16(frame[3]) << 8 | UInt16(frame[4])))
                    decoder.index = Int(frame[5])
                    samples += decoder.decode(Array(frame[6...]))
                }
            } else { samples = decoder.decode(bytes) }
            if let peak = samples.map({ abs(Int32($0)) }).max() { level = max(Float(peak) / 32768, level * 0.8) }
            if live { bridge.append(samples); sampleCount += samples.count }
            else { sampleCount += samples.count }
            if let request = speechRequest, let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false), !samples.isEmpty,
               let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) {
                buffer.frameLength = AVAudioFrameCount(samples.count)
                for (index, sample) in samples.enumerated() { buffer.floatChannelData![0][index] = Float(sample) / 32768 }
                request.append(buffer)
            }
        }
    }
    func start() {
        guard version != nil, !listening else { micStatus = "Inspect Bluetooth services first"; return }
        pending.removeAll(); sampleCount = 0; decoder = ADPCM(); remoteTranscript = ""
        guard rx?.isNotifying == true, ctl?.isNotifying == true else { micStatus = "Audio notifications unavailable. Inspect Bluetooth services again."; return }
        listening = true; openingMic = true; micStatus = "Requesting remote microphone (15-second test)…"
        openingTimer?.invalidate()
        openingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self, self.openingMic else { return }
            self.stop()
            self.micStatus = "No microphone-start reply. Wake the remote and try again."
        }
        send(version == 4 ? [0x0c, 0x00, codec] : [0x0c, 0x00])
        voiceTimer?.invalidate()
        voiceTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.stop() }
    }
    func startLive(limit: TimeInterval = 1800) {
        guard version != nil, !listening else { micStatus = "Inspect Bluetooth services first, and stop any active capture."; return }
        do { try bridge.start(rate: rate) } catch { micStatus = error.localizedDescription; return }
        start()
        guard listening else { bridge.stop(); return }
        live = true
        voiceTimer?.invalidate()
        voiceTimer = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { [weak self] _ in self?.stop() }
        if version == 0x100 {
            keepAlive = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.send([0x0e, 0x00]) }
        }
        micStatus = "Live remote mic → \(bridge.deviceName). Select it as the microphone in your voice app."
    }
    // MARK: Hold-to-talk (button held on the remote)
    private var holdCompletion: ((String) -> Void)?
    /// Starts streaming while a button is held: to on-device speech recognition, or to the virtual microphone.
    func beginHold(transcribe: Bool) {
        guard version != nil else { micStatus = "Remote mic not connected yet. Wake the remote; reconnecting…"; inspect(); return }
        guard !listening else { return }
        if !transcribe { startLive(); return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async { self.refreshPermissions(); self.micStatus = "Speech Recognition permission updated. Hold the button again." } }
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { micStatus = "On-device speech recognition is unavailable for this language."; return }
        speechTask?.cancel(); remoteTranscript = ""
        let request = SFSpeechAudioBufferRecognitionRequest(); request.requiresOnDeviceRecognition = true; request.addsPunctuation = true
        speechRequest = request
        speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result { self.remoteTranscript = result.bestTranscription.formattedString }
                if error != nil || result?.isFinal == true, let done = self.holdCompletion { self.holdCompletion = nil; done(self.remoteTranscript) }
            }
        }
        start()
        voiceTimer?.invalidate() // held dictation ends on release, capped at 2 minutes
        voiceTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in self?.stop() }
        micStatus = "Listening on the remote mic…"
    }
    /// Ends a hold. For dictation, `completion` receives the final transcript.
    func endHold(completion: ((String) -> Void)? = nil) {
        guard listening else { return }
        holdCompletion = speechRequest == nil ? nil : completion
        // Keep the stream open briefly so the last word isn't clipped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.stop()
            if let self, self.holdCompletion != nil { self.micStatus = "Transcribing…" }
        }
    }
    func stop() { if listening { send(version == 4 ? [0x0d] : [0x0d, 0x00]); finish() } }
    private func finish() {
        openingMic = false; openingTimer?.invalidate(); level = 0
        voiceTimer?.invalidate(); keepAlive?.invalidate(); bridge.stop(); live = false; speechRequest?.endAudio(); speechRequest = nil
        note("Capture finished: \(sampleCount) decoded samples at \(Int(rate)) Hz")
        if listening { micStatus = sampleCount > 0 ? "Remote mic ready" : "No audio received. Wake the remote and try again." }
        listening = false
    }
}
