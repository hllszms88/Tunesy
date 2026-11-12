import CoreGraphics
import CoreVideo
import Foundation
import GestureCore

/// The per-frame work, all on the camera's video queue:
/// camera frame → tracking → gesture logic → synth parameters, plus a snapshot for the UI.
///
/// Sound never waits for the main thread: synth parameters go straight to the audio engine.
final class FramePipeline {
    enum Activity: Equatable {
        case idle, play, lesson, filters
    }

    /// What the UI wants the pipeline to do. Copied in under a lock.
    struct Settings {
        var activity: Activity = .idle
        var engine = InstrumentConfig()
        var voice = SynthVoice.all[0]
        var masterGain: Float = 0.8
        var filter: CameraFilter = .original
    }

    /// What the UI needs to draw one frame.
    struct Snapshot {
        /// Hands in display space (0...1), 21 points each.
        var hands: [[CGPoint]] = []
        var chordHand: Int?
        var expressionHand: Int?
        var instrument = InstrumentState()
        var lesson: LessonSnapshot?
        var face: FacePose?
        var imageSize = CGSize(width: 720, height: 1280)
        var framesPerSecond: Double = 0
    }

    let filterStore = FilteredFrameStore()
    /// Called on the main queue, at most once per frame.
    var onSnapshot: ((Snapshot) -> Void)?

    private let audio: AudioEngine
    private let queue: DispatchQueue

    private let lock = NSLock()
    private var settings = Settings()
    private var pendingSnapshot: Snapshot?
    private var deliveryScheduled = false

    // Used only on the video queue.
    private let handTracker = HandTracker()
    private let faceTracker = FaceTracker()
    private let colorRenderer = ColorFilterRenderer()
    private var engine = InstrumentEngine()
    private var lesson: LessonEngine?
    private var params = SynthParams()
    private var lastActivity: Activity = .idle
    private var lastFrameTime: Double = 0
    private var smoothedFPS: Double = 0

    init(audio: AudioEngine, queue: DispatchQueue) {
        self.audio = audio
        self.queue = queue
    }

    // MARK: Called from the main thread

    func update(_ change: (inout Settings) -> Void) {
        lock.lock()
        change(&settings)
        lock.unlock()
    }

    func startLesson(_ song: Song) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lesson = LessonEngine(song: song)
            self.engine.reset()
        }
    }

    func endLesson() {
        queue.async { [weak self] in
            self?.lesson = nil
        }
    }

    func skipChord() {
        queue.async { [weak self] in
            self?.lesson?.skip()
        }
    }

    func repeatSection() {
        queue.async { [weak self] in
            self?.lesson?.repeatSection()
        }
    }

    func restartLesson() {
        queue.async { [weak self] in
            self?.lesson?.restart()
        }
    }

    // MARK: Video queue

    func process(pixelBuffer: CVPixelBuffer, time: Double, isMirrored: Bool) {
        lock.lock()
        let current = settings
        lock.unlock()

        var snapshot = Snapshot()
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        snapshot.imageSize = CGSize(width: width, height: height)

        if lastFrameTime > 0, time > lastFrameTime {
            let instant = 1 / (time - lastFrameTime)
            smoothedFPS = smoothedFPS == 0 ? instant : smoothedFPS * 0.9 + instant * 0.1
        }
        lastFrameTime = time
        snapshot.framesPerSecond = smoothedFPS

        if current.activity != lastActivity {
            // Never carry a sounding note or a stale filter across screens.
            engine.reset()
            lastActivity = current.activity
            if current.activity != .filters {
                filterStore.set(nil)
            }
        }

        params.setVoice(current.voice)
        params.masterGain = current.masterGain

        switch current.activity {
        case .idle:
            params.apply(InstrumentState())

        case .play, .lesson:
            let displayHands = handTracker.detect(in: pixelBuffer)
            snapshot.hands = displayHands.map { hand in
                hand.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
            }
            // Gesture logic works from the player's point of view. The front camera is already
            // mirrored; for the rear camera, mirror the coordinates.
            let playerHands: [HandPose] = isMirrored ? displayHands : displayHands.compactMap { hand in
                HandPose(points: hand.points.map { Vec2(1 - $0.x, $0.y) })
            }
            let frame = HandFrame(time: time, aspect: Float(width) / Float(max(height, 1)), hands: playerHands)

            var config = current.engine
            let inLesson = current.activity == .lesson && lesson != nil
            if inLesson, let song = lesson?.song {
                config.mode = .chords
                config.key = song.key
            }
            if engine.config != config {
                engine.config = config
            }

            let state = engine.process(frame, lessonMode: inLesson)
            var audible = state
            if inLesson, var active = lesson {
                // In a lesson you only hear the chord when you play the right one.
                let correct = active.update(state, time: time)
                lesson = active
                snapshot.lesson = active.snapshot()
                if !correct {
                    audible.frequencies = []
                    audible.volume = 0
                }
            }
            params.apply(audible)
            snapshot.instrument = state
            snapshot.chordHand = state.chordHandIndex
            snapshot.expressionHand = state.expressionHandIndex

        case .filters:
            params.apply(InstrumentState())
            switch current.filter.kind {
            case .face:
                snapshot.face = faceTracker.detect(in: pixelBuffer)
                filterStore.set(nil)
            case .color:
                filterStore.set(colorRenderer.render(current.filter, pixelBuffer: pixelBuffer, time: time))
            case .none:
                filterStore.set(nil)
            }
        }

        audio.set(params)
        deliver(snapshot)
    }

    /// Sends the newest snapshot to the main thread, dropping older ones that were never shown.
    private func deliver(_ snapshot: Snapshot) {
        lock.lock()
        pendingSnapshot = snapshot
        let needsSchedule = !deliveryScheduled
        deliveryScheduled = true
        lock.unlock()
        guard needsSchedule else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let latest = self.pendingSnapshot
            self.pendingSnapshot = nil
            self.deliveryScheduled = false
            self.lock.unlock()
            if let latest = latest {
                self.onSnapshot?(latest)
            }
        }
    }
}
