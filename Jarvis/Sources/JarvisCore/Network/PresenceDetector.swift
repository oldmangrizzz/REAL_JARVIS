import Foundation

public final class PresenceDetector {
    private let scanner: WiFiEnvironmentScanner
    private var baselineRSSI: [String: [Int]] = [:]
    private let threshold: Int

    public init(scanner: WiFiEnvironmentScanner = WiFiEnvironmentScanner(), threshold: Int = 10) {
        self.scanner = scanner
        self.threshold = threshold
    }

    public func recordBaseline(for room: String, samples: Int = 10) {
        var rssiValues: [Int] = []
        for _ in 0..<samples {
            let snapshot = scanner.currentSnapshot()
            if let bssid = snapshot.bssid {
                rssiValues.append(snapshot.rssi)
            }
        }
        if !rssiValues.isEmpty {
            baselineRSSI[room] = rssiValues
        }
    }

    public func estimateRoom() -> String? {
        let snapshot = scanner.currentSnapshot()
        guard let bssid = snapshot.bssid else { return nil }

        let liveRSSI = snapshot.rssi
        var bestRoom: String?
        var bestDiff: Int = Int.max

        for (room, baseline) in baselineRSSI {
            let avgBaseline = baseline.reduce(0, +) / baseline.count
            let diff = abs(liveRSSI - avgBaseline)
            if diff < threshold && diff < bestDiff {
                bestDiff = diff
                bestRoom = room
            }
        }
        return bestRoom
    }
}
