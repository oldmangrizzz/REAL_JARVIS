# Network Tunneling Research - Cellular + WiFi + Mesh

## NWConnection vs URLSessionWebSocketTask

### NWConnection (Network.framework):

| Feature |NWConnection| URLSessionWebSocketTask|
|---------|------------|---------------------|
| Efficiency | ⭐⭐⭐⭐⭐ High throughput | ⭐⭐⭐⭐ Good |
| Latency | Lower | Slightly higher |
| Background | ⚠️ Limited | ✅ Better |
| Reconnect | Manual | ✅ Automatic |
| TLS Support | ✅ Native | ✅ Native |
| Connection Pooling | ❌ No | ⚠️ Limited |
| Apple Quality of Service | ✅ Yes | ⚠️ Limited |

**NWConnection Code:**
```swift
import Network

class WatchTunnelClient {
    private var connection: NWConnection?
    private let group = NWConnectionGroup()
    
    func connect(to host: String, port: Int) {
        let parameters = NWParameters.tcp
        parameters.useSecureConnection(option: .auto)
        parameters.requiredCipherSuites = [.tls_ecdhe_rsa_with_aes_256_gcm_sha384]
        
        connection = NWConnection(host: .init(host, port: port), 
                                  parameters: parameters, 
                                  queue: .global(qos: .userInitiated))
        connection?.start(queue: .global(qos: .userInitiated))
    }
    
    func send(data: Data) {
        connection?.send(content: data, completion: .contentProcessed { error in
            // Handle send completion
        })
    }
}
```

### URLSessionWebSocketTask:

| Feature | URLSessionWebSocketTask| NWConnection |
|---------|----------------------|--------------|
| Efficiency | ⭐⭐⭐⭐⭐ High throughput | ⭐⭐⭐⭐ Good |
| Latency | Lower | Slightly higher |
| Background | ⚠️ Limited | ✅ Better |
| Reconnect | Manual | ✅ Automatic |
| TLS Support | ✅ Native | ✅ Native |
| Connection Pooling | ❌ No | ⚠️ Limited |
| Apple Quality of Service | ✅ Yes | ⚠️ Limited |

**URLSessionWebSocketTask Code:**
```swift
import Foundation

class WatchTunnelClient {
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    
    func connect(to url: URL) {
        task = session.webSocketTask(with: url)
        task?.resume()
    }
    
    func send(message: URLSessionWebSocket.Message) {
        task?.send(message) { error in
            // Handle send completion
        }
    }
    
    func receive(handler: @escaping (URLSessionWebSocketTask.Message) -> Void) {
        task?.receive { result in
            switch result {
            case .success(let message):
                handler(message)
            case .failure(let error):
                print("Receive error: \(error)")
            }
        }
    }
}
```

## Cellular Connectivity Analysis

### Apple Watch Cellular (2026):

| Metric | 5G (Sub-6GHz) | 5G (mmWave) | 4G LTE |
|--------|---------------|-------------|--------|
| Peak Bandwidth | ~50 Mbps | ~1000 Mbps | ~50 Mbps |
| Real-world Bandwidth | ~10-20 Mbps | ~500 Mbps | ~20 Mbps |
| Latency | 30-100ms | 15-30ms | 80-200ms |
| Battery Impact | Medium | High | Low |
| Coverage | 90% (US) | 10% (urban) | 99% (US) |

### Background Task Constraints:

| Action | Max Duration | Background Mode |
|--------|-------------|-----------------|
| Keepalive ping | 30s | ⚠️ Emergency use only |
| Data upload | 30s | ⚠️ Same-day limit |
| Voice streaming | 10s | ⚠️ Requires VoIP push |
| WSS tunnel | Not supported | ❌ Aggressively killed |

### Adaptive Keepalive Strategy:

```swift
// Battery-aware keepalive intervals
enum KeepaliveInterval {
    case active     // Screen on: 30s
    case idle       // Screen off, in range: 120s
    case deepSleep  // Docked, charger: 600s
    
    var value: TimeInterval {
        switch self {
        case .active: return 30
        case .idle: return 120
        case .deepSleep: return 600
        }
    }
}

// Battery state monitoring
func batteryDidUpdate(_ state: BGTaskScheduler.Request) {
    switch BatteryManager.current level {
    case 0...10:
        // Critical - minimal signaling
        currentInterval = .deepSleep
    case 11...50:
        // Low - moderate signaling
        currentInterval = .idle
    case 51...100:
        // Normal - active signaling
        currentInterval = .active
    }
}
```

## Mesh Network - MultipeerConnectivity

### Range & Reliability:

| Environment | Range | Reliability | Notes |
|-------------|-------|-------------|-------|
| Indoor (open) | ~100m | ⭐⭐⭐⭐⭐ | WiFi Direct |
| Indoor (walls) | ~30m | ⭐⭐⭐ | Signal degradation |
| Outdoor (line-of-sight) | ~100m | ⭐⭐⭐⭐⭐ | Clear line-of-sight |
| Outdoor (built-up) | ~20m | ⭐⭐ | Interference |

### Connection Code:
```swift
import MultipeerConnectivity

class MeshClient {
    private let peerID = MCPeerID(displayName: "watch:\(Device.current.id)")
    private let serviceType = "jarvis-mesh"
    private let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
    private let assistant = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
    
    func start() {
        assistant.startAdvertisingDevice()
        browser.startBrowsingForPeers()
    }
    
    func connect(to peer: MCPeerID) {
        browser.connect(peer, with: nil)
    }
}
```

### Use Cases:
- **Watch ↔ Phone:** Mesh fallback when cellular out of range
- **Watch ↔ iPad:** Mesh for visual HUD handoff
- **Watch ↔ Mac:** Mesh for extended compute

## Connection State Machine

```
[unpaired] --[ cellular available ]--> [cellular-only]
[cellular-only] --[ phone WiFi in range ]--> [mesh-connected]
[cellular-only] --[ cellular lost ]--> [degraded]
[mesh-connected] --[ phone unreachable ]--> [cellular-only]
[mesh-connected] --[ home WiFi matched ]--> [wifi-docked]
[wifi-docked] --[ cellular better ]--> [cellular-only]
[degraded] --[ connectivity restored ]--> [previous state]
```

## Recommendations

1. **Primary:** NWConnection + TLS for WSS tunnel (lower latency)
2. **Fallback:** URLSessionWebSocketTask (better background support)
3. **Mesh:** MultipeerConnectivity for phone↔watch fallback
4. **Keepalive:** Adaptive intervals based on battery, screen state
5. **Quality of Service:** Set appropriate QoS for each message type
