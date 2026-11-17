import AVFoundation
import Combine
import GestureCore
import SwiftUI
import UIKit

/// Per-frame data for the views that redraw with the camera (overlays, chord display, lesson).
/// Kept separate from `AppModel` so the rest of the UI is not rebuilt 30 times a second.
final class LiveState: ObservableObject {
    @Published var frame = FramePipeline.Snapshot()
}

/// The app's single source of truth. Used from the main thread.
final class AppModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case play, learn
        var id: String { rawValue }
    }

    enum CameraAccess {
        case unknown, authorized, denied
    }

    @Published var tab: Tab = .play { didSet { syncPipeline() } }
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            camera.setRotationOffset(settings.cameraRotation)
            syncPipeline()
        }
    }
    @Published private(set) var activeSong: Song?
    @Published private(set) var cameraAccess: CameraAccess = .unknown
    @Published private(set) var isFrontCamera = true
    @Published var message: String?

    let live = LiveState()
    let camera: CameraController
    let audio: AudioEngine
    let pipeline: FramePipeline
    let progress = ProgressStore()
    let songs: [Song]

    private var isActive = false

    init() {
        let camera = CameraController()
        let audio = AudioEngine()
        let pipeline = FramePipeline(audio: audio, queue: camera.videoQueue)
        self.camera = camera
        self.audio = audio
        self.pipeline = pipeline
        let savedSettings = AppSettings.load()
        settings = savedSettings
        camera.setRotationOffset(savedSettings.cameraRotation)

        // Built-in lessons, plus any extra ones shipped as Songs.json in the app bundle.
        var library = SongLibrary.builtIn
        if let url = Bundle.main.url(forResource: "Songs", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            let known = Set(library.map { $0.id })
            library.append(contentsOf: SongLibrary.decode(data).filter { !known.contains($0.id) })
        }
        songs = library

        camera.onFrame = { pixelBuffer, time, isMirrored in
            pipeline.process(pixelBuffer: pixelBuffer, time: time, isMirrored: isMirrored)
        }
        camera.onPositionChange = { [weak self] front in
            self?.isFrontCamera = front
        }
        camera.onError = { [weak self] text in
            self?.message = text
        }
        pipeline.onSnapshot = { [weak self] snapshot in
            self?.receive(snapshot)
        }
    }

    // MARK: Lifecycle

    /// Call when the app becomes active.
    func activate() {
        isActive = true
        UIApplication.shared.isIdleTimerDisabled = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAccess = .authorized
            startEngines()
        case .notDetermined:
            cameraAccess = .unknown
        default:
            cameraAccess = .denied
        }
    }

    /// Call when the app leaves the foreground.
    func deactivate() {
        isActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        syncPipeline()
        camera.stop()
        audio.stop()
    }

    func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.cameraAccess = granted ? .authorized : .denied
                if granted && self.isActive {
                    self.startEngines()
                }
            }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func startEngines() {
        camera.start()
        audio.start()
        if let problem = audio.lastError {
            message = "Sound could not start: \(problem)"
        }
        syncPipeline()
    }

    // MARK: Actions

    func switchCamera() {
        camera.switchCamera()
    }

    func startLesson(_ song: Song) {
        activeSong = song
        pipeline.startLesson(song)
        syncPipeline()
    }

    func endLesson() {
        activeSong = nil
        pipeline.endLesson()
        syncPipeline()
    }

    // MARK: Pipeline

    private func syncPipeline() {
        let activity: FramePipeline.Activity
        if !isActive || cameraAccess != .authorized {
            activity = .idle
        } else {
            switch tab {
            case .play: activity = .play
            case .learn: activity = activeSong == nil ? .idle : .lesson
            }
        }
        let settings = self.settings
        pipeline.update { target in
            target.activity = activity
            target.engine = settings.engineConfig
            target.voice = settings.voice
            target.masterGain = settings.outputGain
        }
    }

    private func receive(_ snapshot: FramePipeline.Snapshot) {
        live.frame = snapshot

        if let lesson = snapshot.lesson, lesson.total > 0 {
            progress.record(Double(lesson.matched) / Double(lesson.total), for: lesson.songID)
        }
    }
}
