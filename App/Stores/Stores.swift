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

/// The user's favourite filters, saved on the device.
final class FavoritesStore: ObservableObject {
    @Published private(set) var ids: Set<String>

    private static let storageKey = "handtone.favoriteFilters.v1"

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: FavoritesStore.storageKey) ?? []
        ids = Set(saved)
    }

    func contains(_ filter: CameraFilter) -> Bool {
        return ids.contains(filter.rawValue)
    }

    func toggle(_ filter: CameraFilter) {
        guard filter != .original else { return }
        if ids.contains(filter.rawValue) {
            ids.remove(filter.rawValue)
        } else {
            ids.insert(filter.rawValue)
        }
        UserDefaults.standard.set(Array(ids).sorted(), forKey: FavoritesStore.storageKey)
    }

    var filters: [CameraFilter] {
        return CameraFilter.allCases.filter { ids.contains($0.rawValue) }
    }
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
