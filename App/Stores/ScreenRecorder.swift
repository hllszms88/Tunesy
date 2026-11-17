import Foundation
import ReplayKit
import UIKit

/// Records the app's screen together with the instrument's sound (ReplayKit), so a
/// performance looks exactly as it did on screen: camera, hand dots and chord names.
/// When recording stops, the system preview opens, where the video can be trimmed,
/// saved to Photos or shared. Everything stays on the device unless the user shares it.
final class ScreenRecorder: NSObject, ObservableObject, RPPreviewViewControllerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false

    /// Called on the main thread with a readable message.
    var onError: ((String) -> Void)?

    func toggle() {
        guard !isBusy else { return }
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            onError?("Recording is not available right now. Check that Screen Recording is allowed in Screen Time settings.")
            return
        }
        // The instrument's sound is recorded; the microphone is not.
        recorder.isMicrophoneEnabled = false
        isBusy = true
        recorder.startRecording { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isBusy = false
                if let error = error {
                    self.isRecording = false
                    if (error as NSError).code != RPRecordingErrorCode.userDeclined.rawValue {
                        self.onError?("Recording could not start: \(error.localizedDescription)")
                    }
                    return
                }
                self.isRecording = true
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        isBusy = true
        RPScreenRecorder.shared().stopRecording { [weak self] preview, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isBusy = false
                self.isRecording = false
                if let error = error {
                    self.onError?("Recording could not be finished: \(error.localizedDescription)")
                    return
                }
                guard let preview = preview else { return }
                preview.previewControllerDelegate = self
                preview.modalPresentationStyle = .fullScreen
                ScreenRecorder.topViewController()?.present(preview, animated: true)
            }
        }
    }

    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        previewController.dismiss(animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
