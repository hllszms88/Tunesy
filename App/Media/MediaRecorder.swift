import AVFoundation
import CoreImage
import Photos
import UIKit

/// Photos and videos of a performance, made entirely on the device: the camera picture with
/// the hand dots, the wave and the chord name drawn in, plus the instrument's sound.
/// There is no prompt per recording; access to Photos is asked for once, on the first save.
final class MediaRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    /// Goes up by one each time a photo is taken, so the screen can flash.
    @Published private(set) var photoCount = 0
    /// Short confirmation such as "Saved to Photos", cleared after a moment.
    @Published private(set) var notice: String?

    /// Called on the main thread with a readable message.
    var onError: ((String) -> Void)?
    /// Installs (or with nil removes) a tap on the instrument's sound. Set by the app model.
    var setAudioTap: (((AVAudioPCMBuffer, AVAudioTime) -> Void)?) -> Void = { _ in }
    /// The instrument's sound format. Set by the app model.
    var audioFormat: () -> AVAudioFormat? = { nil }

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    // Everything below is guarded by `lock`. Appends happen while holding it, so a recording
    // can never be finished while a frame or sound buffer is half-way through being added.
    private let lock = NSLock()
    private var wantsPhoto = false
    private var recording = false
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private var plannedAudioFormat: AVAudioFormat?
    private var outputURL: URL?

    // MARK: Main thread

    func takePhoto() {
        lock.lock()
        wantsPhoto = true
        lock.unlock()
        photoCount += 1
    }

    func startVideo() {
        guard !isRecording else { return }
        let format = audioFormat()
        lock.lock()
        recording = true
        sessionStarted = false
        writer = nil
        plannedAudioFormat = format
        lock.unlock()
        isRecording = true
        setAudioTap { [weak self] buffer, time in
            self?.appendAudio(buffer, time: time)
        }
    }

    func stopVideo() {
        guard isRecording else { return }
        isRecording = false
        setAudioTap(nil)

        lock.lock()
        recording = false
        let finishing = writer
        let video = videoInput
        let audio = audioInput
        let started = sessionStarted
        let url = outputURL
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        sessionStarted = false
        outputURL = nil
        lock.unlock()

        guard let writer = finishing, started, let file = url else {
            finishing?.cancelWriting()
            if let file = url { try? FileManager.default.removeItem(at: file) }
            return
        }
        video?.markAsFinished()
        audio?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            if writer.status == .completed {
                self.saveVideo(at: file)
            } else {
                try? FileManager.default.removeItem(at: file)
                self.report("The video could not be finished: \(writer.error?.localizedDescription ?? "unknown error").")
            }
        }
    }

    // MARK: Camera queue

    /// Called for every camera frame while playing. Does nothing unless a photo or video is wanted.
    func consume(_ pixelBuffer: CVPixelBuffer, time: Double, overlay: RecordingOverlay) {
        lock.lock()
        let photo = wantsPhoto
        wantsPhoto = false
        let video = recording
        lock.unlock()
        guard photo || video else { return }

        let base = CIImage(cvPixelBuffer: pixelBuffer)
        let size = base.extent.size
        var composed = base
        if let drawing = overlay.render(size: size, time: time) {
            composed = CIImage(cgImage: drawing).composited(over: base)
        }

        if photo, let image = ciContext.createCGImage(composed, from: base.extent) {
            savePhoto(UIImage(cgImage: image))
        }
        if video {
            appendVideo(composed, size: size, time: time)
        }
    }

    private func appendVideo(_ image: CIImage, size: CGSize, time: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard recording else { return }
        if writer == nil {
            guard startWriter(size: size, time: time) else { return }
        }
        guard let adaptor = adaptor, let input = videoInput, input.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output)
        guard let buffer = output else { return }
        ciContext.render(image, to: buffer)
        adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
    }

    /// Called with `lock` held.
    private func startWriter(size: CGSize, time: Double) -> Bool {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Handtone-\(UUID().uuidString).mov")
        guard let newWriter = try? AVAssetWriter(outputURL: file, fileType: .mov) else {
            failRecording("The video file could not be created.")
            return false
        }
        let width = Int(size.width)
        let height = Int(size.height)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        video.expectsMediaDataInRealTime = true
        let newAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard newWriter.canAdd(video) else {
            failRecording("The video could not be set up.")
            return false
        }
        newWriter.add(video)

        if let format = plannedAudioFormat {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: Int(format.channelCount),
                AVEncoderBitRateKey: 128_000
            ])
            audio.expectsMediaDataInRealTime = true
            if newWriter.canAdd(audio) {
                newWriter.add(audio)
                audioInput = audio
            }
        }

        guard newWriter.startWriting() else {
            failRecording("The video could not start: \(newWriter.error?.localizedDescription ?? "unknown error").")
            return false
        }
        newWriter.startSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 600))
        writer = newWriter
        videoInput = video
        adaptor = newAdaptor
        sessionStarted = true
        outputURL = file
        return true
    }

    /// Called with `lock` held.
    private func failRecording(_ message: String) {
        recording = false
        audioInput = nil
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = false
            self.setAudioTap(nil)
            self.onError?(message)
        }
    }

    // MARK: Audio tap thread

    private func appendAudio(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        lock.lock()
        defer { lock.unlock() }
        guard recording, sessionStarted, let input = audioInput, input.isReadyForMoreMediaData,
              time.isHostTimeValid else { return }
        let seconds = AVAudioTime.seconds(forHostTime: time.hostTime)
        let stamp = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(buffer.format.sampleRate))
        guard let sample = MediaRecorder.sampleBuffer(from: buffer, at: stamp) else { return }
        input.append(sample)
    }

    private static func sampleBuffer(from buffer: AVAudioPCMBuffer, at time: CMTime) -> CMSampleBuffer? {
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                             asbd: buffer.format.streamDescription,
                                             layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil,
                                             extensions: nil,
                                             formatDescriptionOut: &format) == noErr,
              let description = format else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
                                        presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                                   makeDataReadyCallback: nil, refcon: nil,
                                   formatDescription: description,
                                   sampleCount: CMItemCount(buffer.frameLength),
                                   sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0, sampleSizeArray: nil,
                                   sampleBufferOut: &sample) == noErr,
              let result = sample else { return nil }
        guard CMSampleBufferSetDataBufferFromAudioBufferList(result,
                                                             blockBufferAllocator: kCFAllocatorDefault,
                                                             blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                             flags: 0,
                                                             bufferList: buffer.audioBufferList) == noErr else {
            return nil
        }
        return result
    }

    // MARK: Saving

    private func savePhoto(_ image: UIImage) {
        withPhotosAccess(then: { [weak self] in
            PHPhotoLibrary.shared().performChanges({
                _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { saved, error in
                if saved {
                    self?.announce("Photo saved")
                } else {
                    self?.report("The photo could not be saved: \(error?.localizedDescription ?? "unknown error").")
                }
            })
        })
    }

    private func saveVideo(at file: URL) {
        withPhotosAccess(then: { [weak self] in
            PHPhotoLibrary.shared().performChanges({
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: file)
            }, completionHandler: { saved, error in
                try? FileManager.default.removeItem(at: file)
                if saved {
                    self?.announce("Video saved")
                } else {
                    self?.report("The video could not be saved: \(error?.localizedDescription ?? "unknown error").")
                }
            })
        }, otherwise: {
            try? FileManager.default.removeItem(at: file)
        })
    }

    private func withPhotosAccess(then work: @escaping () -> Void, otherwise denied: @escaping () -> Void = {}) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            if status == .authorized || status == .limited {
                work()
            } else {
                denied()
                self?.report("To save photos and videos, allow Handtone to add to Photos in Settings.")
            }
        }
    }

    private func announce(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.notice = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                if self?.notice == message { self?.notice = nil }
            }
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(message)
        }
    }
}

/// What is drawn on top of the camera in photos and videos: the same white hand dots,
/// wave and chord name as on screen.
struct RecordingOverlay {
    /// Hands in frame coordinates (0...1), 21 points each.
    var hands: [[CGPoint]]
    /// The chord (or theremin pitch) being played, or nil when silent.
    var label: String?
    var showDots: Bool

    func render(size: CGSize, time: Double) -> CGImage? {
        guard (showDots && !hands.isEmpty) || label != nil, size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let scale = size.width / 390
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            if showDots {
                cg.setFillColor(UIColor.white.withAlphaComponent(0.95).cgColor)
                let radius = 3 * scale
                for hand in hands {
                    for point in hand {
                        let center = CGPoint(x: point.x * size.width, y: point.y * size.height)
                        cg.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2))
                    }
                }
            }
            if let label = label {
                let band = CGRect(x: 0, y: size.height * 0.70, width: size.width, height: 90 * scale)
                let font = WaveStyle.uiFont(size: WaveStyle.fontSize * scale)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let text = NSAttributedString(string: label, attributes: attributes)
                let textSize = text.size()
                let gap = textSize.width + WaveStyle.gapPadding * scale

                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 8 * scale,
                             color: UIColor(red: 0.94, green: 0.60, blue: 0.68, alpha: 0.9).cgColor)
                cg.addPath(WaveStyle.path(in: band, gap: gap, time: time))
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
                cg.setLineWidth(2.5 * scale)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.strokePath()
                cg.restoreGState()

                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: scale), blur: 8 * scale,
                             color: UIColor.black.withAlphaComponent(0.35).cgColor)
                text.draw(at: CGPoint(x: band.midX - textSize.width / 2, y: band.midY - textSize.height / 2))
                cg.restoreGState()
            }
        }
        return image.cgImage
    }
}

/// The decorative wave: a calm line at a fixed rhythm, split in the middle to hold the chord name.
/// Shared by the screen and by recordings so both look the same.
enum WaveStyle {
    static let fontSize: CGFloat = 40
    static let gapPadding: CGFloat = 36

    static func uiFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        if let serif = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: serif, size: size)
        }
        return base
    }

    static func path(in rect: CGRect, gap: CGFloat, time: Double) -> CGPath {
        let path = CGMutablePath()
        let amplitude = rect.height * 0.28
        let centerX = rect.midX
        let segments: [(CGFloat, CGFloat)] = [(rect.minX + 12, centerX - gap / 2),
                                               (centerX + gap / 2, rect.maxX - 12)]
        for (start, end) in segments where end - start > 8 {
            let steps = max(8, Int((end - start) / 3))
            for step in 0...steps {
                let local = CGFloat(step) / CGFloat(steps)
                let x = start + (end - start) * local
                let u = Double((x - rect.minX) / max(rect.width, 1))
                // Taper each half at both ends so the line fades into the edges and the text.
                let envelope = sin(local * .pi)
                let wave = sin(u * 2 * .pi * 3 - time * 2.4) * 0.8 + sin(u * 2 * .pi * 7 - time * 3.1) * 0.2
                let point = CGPoint(x: x, y: rect.midY - CGFloat(wave) * amplitude * envelope)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        return path
    }
}
