import AVFoundation
import SwiftUI
import UIKit

/// Maps a normalized camera-frame point to a point in a view that shows the
/// frame "aspect fill" (scaled to cover the view, centred, edges cropped).
struct AspectFill {
    let image: CGSize
    let view: CGSize

    var scale: CGFloat {
        guard image.width > 0, image.height > 0 else { return 1 }
        return max(view.width / image.width, view.height / image.height)
    }

    func point(_ normalized: CGPoint) -> CGPoint {
        let s = scale
        let width = image.width * s
        let height = image.height * s
        return CGPoint(x: normalized.x * width - (width - view.width) / 2,
                       y: normalized.y * height - (height - view.height) / 2)
    }
}

// MARK: - Live camera preview

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // The layer class is fixed above, so this cast always succeeds.
        return layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: CameraController

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        camera.attach(previewLayer: view.previewLayer)
        let camera = self.camera
        view.onLayout = { [weak camera] in
            camera?.applyPreviewRotation()
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
