import AVFoundation
import CoreMotion
import Foundation

/// Owns the capture session: camera selection, switching, and frame delivery.
///
/// Frames are delivered upright (portrait) and, for the front camera, mirrored —
/// exactly as shown on screen — so nothing downstream has to think about orientation.
final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    /// Every frame is processed on this serial queue.
    let videoQueue = DispatchQueue(label: "handtone.camera.video", qos: .userInteractive)

    /// Called on `videoQueue`: pixel buffer, timestamp in seconds, whether the frame is mirrored.
    var onFrame: ((CVPixelBuffer, Double, Bool) -> Void)?
    /// Called on the main queue with `true` when the front camera is active.
    var onPositionChange: ((Bool) -> Void)?
    /// Called on the main queue with a readable message.
    var onError: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "handtone.camera.session")
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .front
    private var isConfigured = false
    private var shouldRun = false
    private var observers: [NSObjectProtocol] = []
    /// Shows the same frames the hand tracker reads, so picture and tracking always agree.
    private let displayLock = NSLock()
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    /// Video queue only: set once we have tried to re-rotate sideways frames.
    private var rotationRepairRequested = false

    // Rotation. Apple's rotation coordinator reports the angle that makes each camera's
    // picture upright; some iPhones' front cameras do not use the classic 90°.
    // Session queue only.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var baseAngle: CGFloat = 90
    private var userOffset: CGFloat = 0
    private let infoLock = NSLock()
    private var appliedAngleInfo = "—"
    /// Reads gravity to tell whether the phone is physically upright. Unlike the screen
    /// orientation, this is not fooled by the Portrait Orientation Lock.
    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private let gravityLock = NSLock()
    private var gravity: CMAcceleration?

    override init() {
        super.init()
        startGravityUpdates()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { [weak self] _ in
            self?.restartAfterError()
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil
        ) { [weak self] _ in
            self?.restartAfterError()
        })
    }

    private func startGravityUpdates() {
        guard motion.isDeviceMotionAvailable else { return }
        motionQueue.maxConcurrentOperationCount = 1
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            self.gravityLock.lock()
            self.gravity = data.gravity
            self.gravityLock.unlock()
        }
    }

    /// true = held upright in portrait, false = clearly tilted or flat, nil = not known yet.
    private var isHeldUpright: Bool? {
        gravityLock.lock()
        let current = gravity
        gravityLock.unlock()
        guard motion.isDeviceMotionAvailable else { return true }
        guard let g = current else { return nil }
        return g.y < -0.75 && abs(g.x) < 0.5
    }

    // The upright angle for each camera never changes on a given iPhone, so once learned
    // it is saved and reused on every launch.
    private static func storageKey(_ position: AVCaptureDevice.Position) -> String {
        return position == .front ? "handtone.uprightAngle.front" : "handtone.uprightAngle.back"
    }

    private func storedUprightAngle(_ position: AVCaptureDevice.Position) -> CGFloat? {
        guard let value = UserDefaults.standard.object(forKey: CameraController.storageKey(position)) as? Double else {
            return nil
        }
        return CGFloat(value)
    }

    private func storeUprightAngle(_ angle: CGFloat, for position: AVCaptureDevice.Position) {
        UserDefaults.standard.set(Double(angle), forKey: CameraController.storageKey(position))
    }

    deinit {
        motion.stopDeviceMotionUpdates()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: Control

    /// The on-screen picture. Frames are drawn exactly as delivered: upright, and mirrored
    /// for the front camera.
    func attach(displayLayer: AVSampleBufferDisplayLayer) {
        displayLayer.videoGravity = .resizeAspectFill
        displayLock.lock()
        self.displayLayer = displayLayer
        displayLock.unlock()
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.shouldRun = true
            self.configureIfNeeded()
            if self.isConfigured && !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.shouldRun = false
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    /// Extra rotation chosen by the user (0, 90, 180 or 270), as a last-resort correction.
    func setRotationOffset(_ degrees: Int) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let normalized = CGFloat(((degrees % 360) + 360) % 360)
            guard normalized != self.userOffset else { return }
            self.userOffset = normalized
            self.applyOutputSettings()
        }
    }

    /// Shown in Settings → Diagnostics.
    var rotationDescription: String {
        infoLock.lock()
        defer { infoLock.unlock() }
        return appliedAngleInfo
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.isConfigured else { return }
            let target: AVCaptureDevice.Position = self.position == .front ? .back : .front
            guard let device = self.device(for: target),
                  let newInput = try? AVCaptureDeviceInput(device: device) else {
                self.report("That camera is not available.")
                return
            }
            self.session.beginConfiguration()
            let previous = self.input
            if let previous = previous {
                self.session.removeInput(previous)
            }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.input = newInput
                self.position = target
                self.setUpRotation(for: device)
            } else if let previous = previous, self.session.canAddInput(previous) {
                self.session.addInput(previous)
            }
            self.applyOutputSettings()
            self.session.commitConfiguration()
            self.videoQueue.async { [weak self] in
                self?.rotationRepairRequested = false
            }
            self.notifyPosition()
        }
    }

    // MARK: Session queue

    private func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        guard let device = device(for: position) ?? device(for: .back) else {
            report("No camera was found on this device.")
            return
        }
        position = device.position
        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            }
            guard session.canAddInput(newInput) else {
                session.commitConfiguration()
                report("The camera could not be attached.")
                return
            }
            session.addInput(newInput)
            input = newInput
            setUpRotation(for: device)

            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                report("The camera output could not be attached.")
                return
            }
            session.addOutput(output)
            applyOutputSettings()
            session.commitConfiguration()
            isConfigured = true
            notifyPosition()
        } catch {
            report(error.localizedDescription)
        }
    }

    /// Upright, and mirrored for the front camera.
    private func applyOutputSettings() {
        guard let connection = output.connection(with: .video) else { return }
        configure(connection, front: position == .front)
    }

    /// Session queue. Learns the upright angle for this camera from Apple's rotation coordinator,
    /// but only at moments when gravity says the phone is held upright. The screen is always
    /// portrait, so when the phone is tilted the picture must tilt with it — like a plain camera —
    /// rather than stay level with the horizon.
    private func setUpRotation(for device: AVCaptureDevice) {
        rotationObservation = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        let position = device.position
        let reading = coordinator.videoRotationAngleForHorizonLevelCapture
        if isHeldUpright == true {
            baseAngle = reading
            storeUprightAngle(reading, for: position)
        } else if let stored = storedUprightAngle(position) {
            baseAngle = stored
        } else {
            // Nothing learned yet: best guess until the phone is held upright.
            baseAngle = reading
        }
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture,
                                                  options: [.new]) { [weak self] coordinator, _ in
            // Let the phone settle, then learn the new angle only if it is held upright.
            self?.sessionQueue.asyncAfter(deadline: .now() + 0.4) {
                guard let self = self, self.rotationCoordinator === coordinator,
                      self.isHeldUpright == true else { return }
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                self.storeUprightAngle(angle, for: position)
                guard self.baseAngle != angle else { return }
                self.baseAngle = angle
                self.applyOutputSettings()
            }
        }
    }

    private func configure(_ connection: AVCaptureConnection, front: Bool) {
        let angle = (baseAngle + userOffset).truncatingRemainder(dividingBy: 360)
        let supported = connection.isVideoRotationAngleSupported(angle)
        if supported, connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
        let info = "\(Int(baseAngle))° + \(Int(userOffset))° = \(Int(connection.videoRotationAngle))°"
            + (supported ? "" : " (\(Int(angle))° unsupported)")
        infoLock.lock()
        appliedAngleInfo = info
        infoLock.unlock()
        if connection.isVideoMirroringSupported {
            if connection.automaticallyAdjustsVideoMirroring {
                connection.automaticallyAdjustsVideoMirroring = false
            }
            if connection.isVideoMirrored != front {
                connection.isVideoMirrored = front
            }
        }
    }

    private func restartAfterError() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.shouldRun, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func notifyPosition() {
        let front = position == .front
        DispatchQueue.main.async { [weak self] in
            self?.onPositionChange?(front)
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(message)
        }
    }

    // MARK: Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // The UI is portrait-only, so frames must be taller than wide. If they are not,
        // the rotation did not take effect: apply it again once.
        if !rotationRepairRequested,
           CVPixelBufferGetWidth(pixelBuffer) > CVPixelBufferGetHeight(pixelBuffer) {
            rotationRepairRequested = true
            sessionQueue.async { [weak self] in
                self?.applyOutputSettings()
            }
        }
        show(sampleBuffer)
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        onFrame?(pixelBuffer, time, connection.isVideoMirrored)
    }

    /// Video queue. Puts the frame on screen immediately, before any tracking work.
    private func show(_ sampleBuffer: CMSampleBuffer) {
        displayLock.lock()
        let layer = displayLayer
        displayLock.unlock()
        guard let layer = layer else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
        }
        renderer.enqueue(sampleBuffer)
    }
}
