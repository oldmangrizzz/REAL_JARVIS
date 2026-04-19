import Foundation

// MARK: - Physics → Language Summarizer
//
// Natural Language Barrier (PRINCIPLES.md §6).
//
// The LLM never sees raw physics arrays. It sees a bounded, English summary.
// Numbers are quantized. Counts are bucketed. Object labels are surfaced.
// Anything past `maxBodies` is collapsed into "(N more)".
//
// This is the ONLY sanctioned way to inject physics state into an LLM prompt.

public struct PhysicsSummary: Codable, Sendable, Equatable {
    public let text: String
    public let simulatedTime: Double
    public let bodyCount: Int
    public let restingCount: Int
    public let movingCount: Int
    public let recentContactCount: Int

    public init(
        text: String,
        simulatedTime: Double,
        bodyCount: Int,
        restingCount: Int,
        movingCount: Int,
        recentContactCount: Int
    ) {
        self.text = text
        self.simulatedTime = simulatedTime
        self.bodyCount = bodyCount
        self.restingCount = restingCount
        self.movingCount = movingCount
        self.recentContactCount = recentContactCount
    }
}

public struct PhysicsSummarizer: Sendable {
    public let maxBodies: Int
    public let movingSpeedThreshold: Double
    public let positionPrecision: Int
    public let speedPrecision: Int

    public init(
        maxBodies: Int = 8,
        movingSpeedThreshold: Double = 0.05,
        positionPrecision: Int = 2,
        speedPrecision: Int = 2
    ) {
        self.maxBodies = max(1, maxBodies)
        self.movingSpeedThreshold = max(0, movingSpeedThreshold)
        self.positionPrecision = max(0, positionPrecision)
        self.speedPrecision = max(0, speedPrecision)
    }

    public func summarize(snapshot: [BodyState], lastReport: StepReport?) -> PhysicsSummary {
        let total = snapshot.count
        let moving = snapshot.filter { $0.linearVelocity.length() >= movingSpeedThreshold }
        let resting = total - moving.count
        let contactCount = lastReport?.contacts.count ?? 0
        let simTime = lastReport?.simulatedTime ?? 0.0

        var lines: [String] = []
        let header = "Physics state at t=\(format(simTime, precision: 3))s. \(total) bodies, \(moving.count) moving, \(resting) resting, \(contactCount) recent contacts."
        lines.append(header)

        let visible = snapshot.prefix(maxBodies)
        for b in visible {
            let p = b.transform.position
            let speed = b.linearVelocity.length()
            let movingFlag = speed >= movingSpeedThreshold ? "moving" : "at rest"
            lines.append("- \(b.label) at (\(format(p.x))/\(format(p.y))/\(format(p.z))), speed \(format(speed, precision: speedPrecision))m/s, \(movingFlag).")
        }
        if total > visible.count {
            lines.append("- (\(total - visible.count) more bodies omitted)")
        }

        return PhysicsSummary(
            text: lines.joined(separator: "\n"),
            simulatedTime: simTime,
            bodyCount: total,
            restingCount: resting,
            movingCount: moving.count,
            recentContactCount: contactCount
        )
    }

    private func format(_ v: Double, precision: Int? = nil) -> String {
        let p = precision ?? positionPrecision
        return String(format: "%.\(p)f", v)
    }
}
