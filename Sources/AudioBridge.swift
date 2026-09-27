import Foundation
import CoreAudio

/// Plays decoded remote audio into the "Vibote Mic" loopback device, so other apps can record it as a microphone.
/// Uses a Core Audio IOProc directly on the device (AVAudioEngine did not reliably switch output devices).
final class AudioBridge {
    private static let deviceUID = "ViboteMic_UID" as CFString
    private static let deviceRate = 48000.0
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var ring: [Float] = []
    private var readIndex = 0
    private var inputRate = 16000.0
    private var previous = 0.0, highPass = 0.0, lastSample: Float = 0
    private(set) var deviceName = "Vibote Mic"

    func start(rate: Double) throws {
        stop()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid = Self.deviceUID, found = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), &uid, &size, &found)
        guard status == noErr, found != kAudioObjectUnknown else {
            throw NSError(domain: "Vibote", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vibote Mic isn't installed. Run scripts/install-mic.sh."])
        }
        device = found; inputRate = rate
        var id: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&id, device, nil) { [weak self] _, _, _, output, _ in
            self?.render(into: output)
        }
        guard created == noErr, let id else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(created)) }
        procID = id
        let started = AudioDeviceStart(device, id)
        guard started == noErr else { stop(); throw NSError(domain: NSOSStatusErrorDomain, code: Int(started)) }
    }

    /// Queues remote samples: DC-filtered and resampled to the device rate. Drops audio beyond ~1 s of backlog.
    func append(_ samples: [Int16]) {
        guard procID != nil, !samples.isEmpty else { return }
        let factor = Self.deviceRate / inputRate
        var out: [Float] = []; out.reserveCapacity(Int(Double(samples.count) * factor) + 1)
        for sample in samples {
            let x = Double(sample) / 32768
            highPass = x - previous + 0.995 * highPass; previous = x
            let current = Float(max(-1, min(1, highPass)))
            let steps = Int(factor.rounded())
            for step in 1...steps { out.append(lastSample + (current - lastSample) * Float(step) / Float(steps)) }
            lastSample = current
        }
        lock.lock()
        if readIndex > 0 { ring.removeFirst(readIndex); readIndex = 0 }
        if ring.count < Int(Self.deviceRate) { ring += out }
        lock.unlock()
    }

    private func render(into output: UnsafeMutablePointer<AudioBufferList>) {
        lock.lock(); defer { lock.unlock() }
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let channels = Int(max(buffer.mNumberChannels, 1)), frames = Int(buffer.mDataByteSize) / 4 / channels
            for frame in 0..<frames {
                let value: Float = readIndex < ring.count ? ring[readIndex] : 0
                if readIndex < ring.count { readIndex += 1 }
                for channel in 0..<channels { data[frame * channels + channel] = value }
            }
        }
    }

    func stop() {
        if let procID { AudioDeviceStop(device, procID); AudioDeviceDestroyIOProcID(device, procID) }
        procID = nil
        lock.lock(); ring.removeAll(); readIndex = 0; lock.unlock()
        previous = 0; highPass = 0; lastSample = 0
    }
}
