import AVFoundation
import Foundation
import GestureCore
import os

/// Memory shared with the real-time audio thread. Lives at a fixed address so the
/// render callback can use it without touching any Swift object.
private struct RenderState {
    var lock = os_unfair_lock()
    var pending = SynthParams()
    var current = SynthParams()
    var dsp = SynthDSP()
}

/// Hosts the synthesizer in an AVAudioEngine and keeps the audio session healthy.
final class AudioEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var tapInstalled = false
    private let state: UnsafeMutablePointer<RenderState>
    private var observers: [NSObjectProtocol] = []
    private var wantsToRun = false

    private(set) var isRunning = false
    private(set) var sampleRate: Double = 0
    private(set) var bufferDuration: Double = 0
    private(set) var lastError: String?

    init() {
        state = UnsafeMutablePointer<RenderState>.allocate(capacity: 1)
        state.initialize(to: RenderState())
        _ = SynthVoice.all.count
        observeSystemEvents()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        engine.stop()
        state.deinitialize(count: 1)
        state.deallocate()
    }

    /// The instrument's sound format (for recordings).
    var outputFormat: AVAudioFormat? {
        return sourceNode?.outputFormat(forBus: 0)
    }

    /// Main thread. Delivers the instrument's sound to `handler` for recording; nil stops it.
    /// The tap runs on its own thread, never on the real-time audio thread.
    func setRecordingTap(_ handler: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?) {
        guard let node = sourceNode else { return }
        if tapInstalled {
            node.removeTap(onBus: 0)
            tapInstalled = false
        }
        guard let handler = handler else { return }
        node.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, time in
            handler(buffer, time)
        }
        tapInstalled = true
    }

    /// Hands new parameters to the audio thread. Safe to call from any thread.
    func set(_ params: SynthParams) {
        os_unfair_lock_lock(&state.pointee.lock)
        state.pointee.pending = params
        os_unfair_lock_unlock(&state.pointee.lock)
    }

    func start() {
        wantsToRun = true
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback keeps the instrument audible with the ring/silent switch on.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            try rebuildGraph()
            try engine.start()
            sampleRate = session.sampleRate
            bufferDuration = session.ioBufferDuration
            isRunning = true
            lastError = nil
        } catch {
            isRunning = false
            lastError = error.localizedDescription
        }
    }

    func stop() {
        wantsToRun = false
        silence()
        engine.stop()
        isRunning = false
    }

    private func silence() {
        os_unfair_lock_lock(&state.pointee.lock)
        state.pointee.pending.mode = .silent
        state.pointee.pending.noteCount = 0
        state.pointee.pending.volume = 0
        state.pointee.pending.thereminGain = 0
        os_unfair_lock_unlock(&state.pointee.lock)
    }

    private func rebuildGraph() throws {
        if let node = sourceNode {
            if tapInstalled {
                node.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.detach(node)
            sourceNode = nil
        }
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = hardwareRate > 0 ? hardwareRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
            throw NSError(domain: "Handtone.Audio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create an audio format."])
        }
        // The engine is stopped here, so the audio thread is not using the DSP state.
        state.pointee.dsp.sampleRate = Float(rate)

        let shared = state
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // Never wait on the audio thread: if the lock is busy, keep the previous parameters.
            if os_unfair_lock_trylock(&shared.pointee.lock) {
                shared.pointee.current = shared.pointee.pending
                os_unfair_lock_unlock(&shared.pointee.lock)
            }
            guard buffers.count > 0, let first = buffers[0].mData else { return noErr }
            let frames = Int(frameCount)
            let out = first.assumingMemoryBound(to: Float.self)
            shared.pointee.dsp.render(into: out, count: frames, params: shared.pointee.current)
            if buffers.count > 1 {
                for index in 1..<buffers.count {
                    if let other = buffers[index].mData {
                        memcpy(other, first, frames * MemoryLayout<Float>.size)
                    }
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        engine.prepare()
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default

        // Phone call, Siri, alarm…
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.isRunning = false
            case .ended:
                if self.wantsToRun { self.start() }
            @unknown default:
                break
            }
        })

        // Headphones plugged in or out: the hardware format may have changed.
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isRunning = false
            if self.wantsToRun { self.start() }
        })
    }
}
