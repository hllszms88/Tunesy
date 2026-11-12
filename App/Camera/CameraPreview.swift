import AVFoundation
import CoreImage
import MetalKit
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
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

// MARK: - Filtered preview (colour effects)

/// Holds the most recent filtered frame. Written on the video queue, read on the main thread.
final class FilteredFrameStore {
    private let lock = NSLock()
    private var image: CIImage?
    private var version = 0

    func set(_ newImage: CIImage?) {
        lock.lock()
        if newImage != nil || image != nil {
            image = newImage
            version += 1
        }
        lock.unlock()
    }

    func latest() -> (image: CIImage?, version: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (image, version)
    }
}

/// Draws filtered frames with Core Image on Metal, aspect-filled like the live preview.
final class MetalFilterView: MTKView, MTKViewDelegate {
    /// If the filtered picture ever appears upside down on a device, flip this.
    static let flipVertically = false

    private let store: FilteredFrameStore
    private var commandQueue: MTLCommandQueue?
    private var ciContext: CIContext?
    private var lastVersion = -1

    init(store: FilteredFrameStore) {
        self.store = store
        let metalDevice = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: metalDevice)
        if let metalDevice = metalDevice {
            commandQueue = metalDevice.makeCommandQueue()
            ciContext = CIContext(mtlDevice: metalDevice, options: [.cacheIntermediates: false])
        }
        framebufferOnly = false
        isOpaque = true
        backgroundColor = .black
        isUserInteractionEnabled = false
        preferredFramesPerSecond = 60
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("MetalFilterView is created in code only")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lastVersion = -1
    }

    func draw(in view: MTKView) {
        let latest = store.latest()
        guard latest.version != lastVersion,
              let source = latest.image,
              let ciContext = ciContext,
              let commandQueue = commandQueue else { return }
        let size = drawableSize
        guard size.width > 0, size.height > 0, source.extent.width > 0, source.extent.height > 0,
              let drawable = currentDrawable,
              let buffer = commandQueue.makeCommandBuffer() else { return }
        lastVersion = latest.version

        var image = source.transformed(by: CGAffineTransform(
            translationX: -source.extent.minX, y: -source.extent.minY))
        if MetalFilterView.flipVertically {
            image = image.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
                .transformed(by: CGAffineTransform(translationX: 0, y: source.extent.height))
        }
        let scale = max(size.width / source.extent.width, size.height / source.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offsetX = (image.extent.width - size.width) / 2
        let offsetY = (image.extent.height - size.height) / 2
        image = image.transformed(by: CGAffineTransform(translationX: -offsetX, y: -offsetY))

        let destination = CIRenderDestination(
            width: Int(size.width), height: Int(size.height),
            pixelFormat: colorPixelFormat, commandBuffer: buffer,
            mtlTextureProvider: { () -> MTLTexture in
                return drawable.texture
            })
        let bounds = CGRect(origin: .zero, size: size)
        _ = try? ciContext.startTask(toRender: image, from: bounds, to: destination, at: .zero)
        buffer.present(drawable)
        buffer.commit()
    }
}

struct FilteredPreview: UIViewRepresentable {
    let store: FilteredFrameStore

    func makeUIView(context: Context) -> MetalFilterView {
        return MetalFilterView(store: store)
    }

    func updateUIView(_ uiView: MetalFilterView, context: Context) {}
}
