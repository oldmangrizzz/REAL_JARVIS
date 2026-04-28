import Foundation
import Combine

/// Manages telemetry for GrizzOS. Polls the local Charlie VPS for bridge status.
/// Trauma-Informed Design: Evaluates A&Ox4 status and fails closed (distress) if unreachable.
public class TelemetryManager: ObservableObject {
    @Published public var isSynced: Bool = false
    @Published public var distressState: String = "nominal"
    @Published public var aox4Status: String = "NOMINAL"

    private var timer: AnyCancellable?
    private let endpoint = URL(string: "http://192.168.7.114:8000/homekit-bridge-status.json")! // Local fallback

    public init() {
        startPolling()
    }

    private func startPolling() {
        timer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchTelemetry()
            }
        // Initial fetch
        fetchTelemetry()
    }

    private func fetchTelemetry() {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 3.0

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.failClosed(reason: error.localizedDescription)
                    return
                }

                guard let data = data,
                      let status = try? JSONDecoder().decode(BridgeStatus.self, from: data) else {
                    self.failClosed(reason: "Invalid payload")
                    return
                }

                self.isSynced = status.reachable
                self.distressState = status.distressState

                if status.distressState == "elevated" || !status.reachable {
                    self.aox4Status = "DISTRESS"
                } else {
                    self.aox4Status = "NOMINAL"
                }
            }
        }.resume()
    }

    private func failClosed(reason: String) {
        self.isSynced = false
        self.distressState = "elevated"
        self.aox4Status = "SYNC LOST"
        print("[SYS] Telemetry Poll Failed: \(reason). Failsafe engaged.")
    }
}

struct BridgeStatus: Decodable {
    let reachable: Bool
    let distressState: String
}