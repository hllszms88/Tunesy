import Foundation
import GestureCore

/// User preferences, saved on the device.
struct AppSettings: Codable, Equatable {
    var key: MusicalKey = .c
    var voiceID: String = "classic"
    var mode: InstrumentMode = .chords
    var modeControl: ModeControl = .tilt
    /// 0 = the right hand's fingers choose; 1...4 = locked.
    var fixedQuality: Int = 0
    var lockOctave: Bool = false
    var fixedOctave: Int = 0
    var volume: Float = 0.8
    var muted: Bool = false
    var showSkeleton: Bool = true
    /// Misty look over the camera picture, 0...1.
    var softCamera: Float = 0.3

    init() {}

    /// Missing keys (from older versions of the app) fall back to defaults instead of
    /// discarding every saved setting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        key = try c.decodeIfPresent(MusicalKey.self, forKey: .key) ?? d.key
        voiceID = try c.decodeIfPresent(String.self, forKey: .voiceID) ?? d.voiceID
        mode = try c.decodeIfPresent(InstrumentMode.self, forKey: .mode) ?? d.mode
        modeControl = try c.decodeIfPresent(ModeControl.self, forKey: .modeControl) ?? d.modeControl
        fixedQuality = try c.decodeIfPresent(Int.self, forKey: .fixedQuality) ?? d.fixedQuality
        lockOctave = try c.decodeIfPresent(Bool.self, forKey: .lockOctave) ?? d.lockOctave
        fixedOctave = try c.decodeIfPresent(Int.self, forKey: .fixedOctave) ?? d.fixedOctave
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? d.volume
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? d.muted
        showSkeleton = try c.decodeIfPresent(Bool.self, forKey: .showSkeleton) ?? d.showSkeleton
        softCamera = try c.decodeIfPresent(Float.self, forKey: .softCamera) ?? d.softCamera
    }

    private static let storageKey = "handtone.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.storageKey)
        }
    }

    var voice: SynthVoice { SynthVoice.named(voiceID) }

    var engineConfig: InstrumentConfig {
        var config = InstrumentConfig()
        config.mode = mode
        config.key = key
        config.modeControl = modeControl
        config.fixedQuality = (1...4).contains(fixedQuality) ? fixedQuality : nil
        config.fixedOctave = lockOctave ? fixedOctave : nil
        return config
    }

    var outputGain: Float { muted ? 0 : volume }
}

/// Best result per song (share of chords played correctly), saved on the device.
final class ProgressStore: ObservableObject {
    @Published private(set) var best: [String: Double]

    private static let storageKey = "handtone.songProgress.v1"

    init() {
        best = (UserDefaults.standard.dictionary(forKey: ProgressStore.storageKey) as? [String: Double]) ?? [:]
    }

    func value(for songID: String) -> Double {
        return best[songID] ?? 0
    }

    /// Keeps the highest value ever reached.
    func record(_ fraction: Double, for songID: String) {
        guard fraction > (best[songID] ?? 0) + 0.0001 else { return }
        best[songID] = min(1, fraction)
        UserDefaults.standard.set(best, forKey: ProgressStore.storageKey)
    }
}
