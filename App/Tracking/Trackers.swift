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

/// The face features the filters need, in display space (0...1, y downward).
struct FacePose: Equatable {
    /// The eye on the left of the screen.
    var leftEye: CGPoint
    var rightEye: CGPoint
    var nose: CGPoint
    var mouth: CGPoint
    /// Mouth opening relative to the distance between the eyes.
    var mouthOpen: CGFloat

    func blended(toward other: FacePose, amount: CGFloat) -> FacePose {
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            return CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount)
        }
        return FacePose(leftEye: mix(leftEye, other.leftEye),
                        rightEye: mix(rightEye, other.rightEye),
                        nose: mix(nose, other.nose),
                        mouth: mix(mouth, other.mouth),
                        mouthOpen: mouthOpen + (other.mouthOpen - mouthOpen) * amount)
    }
}

/// Finds the largest face and its landmarks using Vision. Runs entirely on the device.
final class FaceTracker {
    private let request = VNDetectFaceLandmarksRequest()

    func detect(in pixelBuffer: CVPixelBuffer) -> FacePose? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let faces = request.results, !faces.isEmpty else { return nil }
        let largest = faces.max { a, b in
            a.boundingBox.width * a.boundingBox.height < b.boundingBox.width * b.boundingBox.height
        }
        guard let face = largest, let landmarks = face.landmarks else { return nil }
        let box = face.boundingBox

        // Landmark points are relative to the face box, with a bottom-left origin.
        func toDisplay(_ p: CGPoint) -> CGPoint {
            return CGPoint(x: box.minX + p.x * box.width, y: 1 - (box.minY + p.y * box.height))
        }
        func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let region = region, region.pointCount > 0 else { return nil }
            let points = region.normalizedPoints
            var sx: CGFloat = 0
            var sy: CGFloat = 0
            for p in points {
                sx += p.x
                sy += p.y
            }
            let n = CGFloat(points.count)
            return toDisplay(CGPoint(x: sx / n, y: sy / n))
        }

        guard let eyeA = center(landmarks.leftPupil) ?? center(landmarks.leftEye),
              let eyeB = center(landmarks.rightPupil) ?? center(landmarks.rightEye) else { return nil }
        let leftEye = eyeA.x <= eyeB.x ? eyeA : eyeB
        let rightEye = eyeA.x <= eyeB.x ? eyeB : eyeA

        let eyeMid = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let eyeDistance = hypot((rightEye.x - leftEye.x) * width, (rightEye.y - leftEye.y) * height)
        guard eyeDistance > 1 else { return nil }

        let nose = center(landmarks.nose) ?? CGPoint(x: eyeMid.x, y: eyeMid.y + 0.7 * eyeDistance / height)
        let mouth = center(landmarks.outerLips) ?? CGPoint(x: eyeMid.x, y: eyeMid.y + 1.2 * eyeDistance / height)

        var mouthOpen: CGFloat = 0
        if let inner = landmarks.innerLips, inner.pointCount > 2 {
            let ys = inner.normalizedPoints.map { $0.y }
            if let low = ys.min(), let high = ys.max() {
                mouthOpen = (high - low) * box.height * height / eyeDistance
            }
        }
        return FacePose(leftEye: leftEye, rightEye: rightEye, nose: nose, mouth: mouth, mouthOpen: mouthOpen)
    }
}
