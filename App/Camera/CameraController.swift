import AVFoundation
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
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var observers: [NSObjectProtocol] = []
    /// Main thread only: whether the preview should be mirrored.
    private var previewIsFront = true
    /// Video queue only: set once we have tried to re-rotate sideways frames.
    private var rotationRepairRequested = false

    override init() {
        super.init()
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
        // The preview layer's connection may only exist once the session runs; orient it then.
        observers.append(center.addObserver(
            forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main
        ) { [weak self] _ in
            self?.applyPreviewRotation()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: Control

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.applyPreviewSettings(front: self.position == .front)
        }
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
            } else if let previous = previous, self.session.canAddInput(previous) {
                self.session.addInput(previous)
            }
            self.applyOutputSettings()
            self.session.commitConfiguration()
            self.videoQueue.async { [weak self] in
                self?.rotationRepairRequested = false
            }
            self.applyPreviewSettings(front: self.position == .front)
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
            applyPreviewSettings(front: position == .front)
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

    private func applyPreviewSettings(front: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.previewIsFront = front
            self.applyPreviewRotation()
        }
    }

    /// Main thread. Safe to call often (it is called on every layout pass):
    /// it only changes the connection when something is wrong.
    func applyPreviewRotation() {
        guard let connection = previewLayer?.connection else { return }
        configure(connection, front: previewIsFront)
    }

    /// Main thread. Shown in Settings → Diagnostics.
    var previewRotationDescription: String {
        guard let connection = previewLayer?.connection else { return "not connected" }
        return "\(Int(connection.videoRotationAngle))°" + (connection.isVideoMirrored ? " · mirrored" : "")
    }

    private func configure(_ connection: AVCaptureConnection, front: Bool) {
        // 90° = portrait for both cameras.
        if connection.isVideoRotationAngleSupported(90), connection.videoRotationAngle != 90 {
            connection.videoRotationAngle = 90
        }
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
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        onFrame?(pixelBuffer, time, connection.isVideoMirrored)
    }
}
