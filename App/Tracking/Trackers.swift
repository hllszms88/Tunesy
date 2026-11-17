import CoreGraphics
import CoreVideo
import GestureCore
import Vision

/// Finds up to two hands in a camera frame using Apple's Vision framework.
/// Runs entirely on the device.
final class HandTracker {
    var minimumConfidence: Float = 0.3

    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()

    /// Vision's joints in the order of `GestureCore.Joint`.
    private static let joints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]

    /// Hands in display space: x to the right, y downward, both 0...1.
    func detect(in pixelBuffer: CVPixelBuffer) -> [HandPose] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let observations = request.results else { return [] }

        var hands: [HandPose] = []
        for observation in observations {
            guard let recognized = try? observation.recognizedPoints(.all) else { continue }
            var points: [Vec2] = []
            var confident = 0
            for joint in HandTracker.joints {
                guard let point = recognized[joint] else { break }
                if point.confidence >= minimumConfidence { confident += 1 }
                // Vision's origin is bottom-left; the app uses top-left.
                points.append(Vec2(Float(point.location.x), Float(1 - point.location.y)))
            }
            // A hand with several unreliable joints would be misread; skip it.
            guard points.count == HandTracker.joints.count, confident >= 18,
                  let pose = HandPose(points: points) else { continue }
            hands.append(pose)
        }
        return hands
    }
}
