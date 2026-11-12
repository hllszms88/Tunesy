import Foundation

/// One Euro filter (Casiez, Roussel, Vogel 2012): smooths a noisy signal with
/// little lag by raising its cutoff frequency when the signal moves fast.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Float
    public var beta: Float
    public var derivativeCutoff: Float

    private var lastValue: Float = 0
    private var lastDerivative: Float = 0
    private var lastTime: Double = 0
    private var hasValue = false

    public init(minCutoff: Float = 1.5, beta: Float = 0.05, derivativeCutoff: Float = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    public mutating func reset() {
        hasValue = false
        lastDerivative = 0
    }

    public mutating func filter(_ value: Float, time: Double) -> Float {
        guard hasValue else {
            hasValue = true
            lastValue = value
            lastTime = time
            return value
        }
        let dt = Float(time - lastTime)
        guard dt > 0 else { return lastValue }
        lastTime = time

        let derivative = (value - lastValue) / dt
        let aD = OneEuroFilter.alpha(cutoff: derivativeCutoff, dt: dt)
        lastDerivative += aD * (derivative - lastDerivative)

        let cutoff = minCutoff + beta * abs(lastDerivative)
        let a = OneEuroFilter.alpha(cutoff: cutoff, dt: dt)
        lastValue += a * (value - lastValue)
        return lastValue
    }

    private static func alpha(cutoff: Float, dt: Float) -> Float {
        let tau = 1 / (2 * Float.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}
