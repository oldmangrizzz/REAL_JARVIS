# GAP CLOSING SPEC — Jarvis Client & Spatial Platform Build

## GROUND TRUTH — What Actually Exists

### VERIFIED REAL (not vapor)

| Item | File | Lines | Status |
|------|------|-------|--------|
| iPhone client @main | `Mobile/AppiPhone/RealJarvisPhoneApp.swift` | 32 | REAL — thin shell, delegates to JarvisMobileCore |
| iPad client @main | `Mobile/AppiPad/RealJarvisPadApp.swift` | 32 | REAL — same structure as iPhone |
| watchOS client @main | `Watch/Extension/RealJarvisWatchApp.swift` | 20 | REAL — thin shell, delegates to JarvisWatchCore |
| CockpitView (iOS/iPad) | `Mobile/Sources/JarvisMobileCore/JarvisCockpitView.swift` | 365 | REAL — 8-panel SwiftUI layout, GMRI palette |
| CockpitStore (iOS/iPad) | `Mobile/Sources/JarvisMobileCore/JarvisMobileCockpitStore.swift` | 159 | REAL — tunnel client, Convex sync, voice clone |
| Watch CockpitView | `Watch/Sources/JarvisWatchCore/JarvisWatchCockpitView.swift` | 53 | REAL — vitals + host state, simplified |
| Watch CockpitStore | `Watch/Sources/JarvisWatchCore/JarvisWatchCockpitStore.swift` | 96 | REAL — same tunnel/Convex architecture |
| Tunnel Client | `MobileShared/Sources/JarvisMobileShared/JarvisTunnelClient.swift` | 128 | REAL — NWConnection, ChaCha20-Poly1305 |
| Tunnel Crypto | `Shared/Sources/JarvisShared/TunnelCrypto.swift` | 43 | REAL — CryptoKit ChaChaPoly seal/open |
| Tunnel Models | `Shared/Sources/JarvisShared/TunnelModels.swift` | 565 | REAL — full protocol stack, spatial HUD types |
| PWA | `pwa/index.html` | 1062 | REAL — WebSocket proxy, CarPlay mode, Web Speech TTS, 8-panel cockpit |
| A-Frame Workshop | `the_workshop.html` | 462 | REAL — A-Frame 1.7.1 + AR.js, 3D knowledge graph |
| IntentParser | `JarvisCore/Interface/IntentParser.swift` | 87 | REAL — display/HomeKit/skill/system intent parsing |
| CapabilityRegistry | `JarvisCore/Interface/CapabilityRegistry.swift` | 142 | REAL — DisplayEndpoint, AccessoryEndpoint, JSON config |
| DisplayCommandExecutor | `JarvisCore/Interface/DisplayCommandExecutor.swift` | 176 | REAL — authority model, DDC/AirPlay/HTTP/HomeKit routing |
| IntentTypes | `JarvisCore/Interface/IntentTypes.swift` | 23 | REAL — JarvisIntent enum, ParsedIntent struct |
| macOS CLI | `App/main.swift` | 133 | REAL — CLI, no GUI app target |
| Spatial HUD types | `TunnelModels.swift:502-545` | ~43 | REAL — JarvisSpatialHUDElement with anchors/glyphs |
| Voice Gate spatial | `VoiceApprovalGate.swift:290-360` | ~70 | REAL — snapshotForSpatialHUD + spatialHUDElement |
| Tests | 22 test files | 2033 lines total | REAL — 100/100 passing |

### VERIFIED MISSING (vapor or incomplete)

| Gap | Evidence | Severity |
|-----|----------|----------|
| macOS desktop client | No @main App struct, no SwiftUI WindowGroup, main.swift is CLI only | HIGH |
| WebXR portal | xr.grizzlymedicine.icu is a 43-line HomeKit status page (static fetch JSON). Zero WebXR API calls. the_workshop.html has A-Frame but NO tunnel connection, NO live data | HIGH |
| WiFi CSI | Zero CoreWLAN/NetworkExtension code anywhere in repo | MEDIUM |
| Mesh display control | Spatial anchors + SpatialHUDElement types exist in protocol but no hardware output — DDC executor shells out to m1ddc which IS NOT INSTALLED | HIGH |
| visionOS client | No ImmersiveSpace, no RealityKit, no visionOS target | MEDIUM |

---

## SPEC-GAP-001: macOS Desktop Cockpit App

### Problem
The macOS host runs as a CLI (`JarvisCLI.main()` in `App/main.swift`). There is no native macOS app with a cockpit UI. The operator's primary machine — the one running the host tunnel and voice interface — has no visual feedback panel.

### Required Files

**1. `Jarvis/Mac/AppMac/RealJarvisMacApp.swift` (NEW)**
```swift
import SwiftUI
import JarvisMacCore

@main
struct RealJarvisMacApp: App {
    @StateObject private var store: JarvisMacCockpitStore
    
    init() {
        _store = StateObject(wrappedValue: JarvisMacCockpitStore())
    }
    
    var body: some Scene {
        WindowGroup {
            JarvisMacCockpitView(store: store)
                .frame(minWidth: 900, minHeight: 600)
                .task { await store.start() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1280, height: 800)
        
        // Settings window for host configuration
        Settings {
            JarvisMacSettingsView(store: store)
        }
    }
}
```

**2. `Jarvis/Mac/Sources/JarvisMacCore/JarvisMacCockpitView.swift` (NEW)**
- Reuse the same 8-panel layout from `JarvisCockpitView.swift` but in macOS-adaptive layout
- Use `NavigationSplitView` for sidebar + detail (macOS native pattern)
- Sidebar: panel list (Status, Voice Gate, Spatial HUD, Authorization, HomeKit, Obsidian, Thought, Signal)
- Detail: selected panel content
- Top toolbar: connection state indicator, voice gate badge, speak button
- Bottom status bar: tunnel state, active workflow, last mutation

**3. `Jarvis/Mac/Sources/JarvisMacCore/JarvisMacCockpitStore.swift` (NEW)**
- Nearly identical to `JarvisMobileCockpitStore.swift` but:
  - Role = `.macDesktop`
  - No voice clone engine (macOS already has the host pipeline)
  - Direct access to `JarvisRuntime` for local state (not tunnel-dependent for host machine)
  - Falls back to tunnel connection for remote scenarios

**4. `Jarvis/Mac/Sources/JarvisMacCore/JarvisMacSettingsView.swift` (NEW)**
- Host address field
- Port field
- Shared secret field (masked)
- Capability registry editor (add/remove displays and accessories)
- Voice gate status (read-only, show gate file path)

**5. `Jarvis/Mac/Sources/JarvisMacCore/JarvisMacSystemHooks.swift` (NEW)**
- macOS-specific hooks: menu bar icon, dock badge on disconnect, notification center alerts for tunnel/warnings

### Implementation Notes
- The Mac cockpit can use `JarvisMobileShared` (tunnel client, host configuration, pending action store) — it's already platform-agnostic
- The Mac cockpit can use `JarvisShared` (all tunnel models, spatial HUD, palette)
- The Mac cockpit should ALSO have a "Host Mode" toggle that runs the `RealJarvisInterface` + `JarvisHostTunnelServer` in-process instead of connecting to a remote host
- Package.swift needs a new `.executableTarget` for the Mac app or a new Xcode target

### RLM REPL Build Sequence
```
1. CREATE Jar维斯/Mac/AppMac/RealJarvisMacApp.swift — @main entry, WindowGroup
2. CREATE Jarvis/Mac/Sources/JarvisMacCore/JarvisMacCockpitStore.swift — copy Mobile pattern, role=macDesktop
3. CREATE Jarvis/Mac/Sources/JarvisMacCore/JarvisMacCockpitView.swift — NavigationSplitView, 8 panels
4. CREATE Jarvis/Mac/Sources/JarvisMacCore/JarvisMacSettingsView.swift — host config form
5. CREATE Jarvis/Mac/Sources/JarvisMacCore/JarvisMacSystemHooks.swift — menu bar, notifications
6. MODIFY Package.swift — add macApp target depending on JarvisMacCore + JarvisMobileShared + JarvisShared
7. BUILD → compile check
8. ADD JarvisMacCockpitStoreTests.swift — 3 tests (init, role, tunnel lifecycle)
9. ADD JarvisMacCockpitViewTests.swift — 2 tests (render, panel selection)
10. BUILD + TEST → must pass all (102+)
```

---

## SPEC-GAP-002: WebXR Portal — xr.grizzlymedicine.icu

### Problem
The current `xr.grizzlymedicine.icu/index.html` is a 43-line static HomeKit status page that fetches a JSON file. It has:
- Zero WebXR API calls
- Zero 3D rendering
- Zero tunnel connection
- Zero spatial HUD

Meanwhile `the_workshop.html` (462 lines) has A-Frame 1.7.1 with a 3D knowledge graph renderer, lights, camera rig, and graph layout — but NO live data connection. It reads static files from fixed URLs.

### Required: Merge and Upgrade

**1. `xr.grizzlymedicine.icu/index.html` (REPLACE — full rewrite)**

This becomes the spatial cockpit. It MUST:

a) **Connect to the tunnel** via WebSocket proxy (same as PWA)
b) **Render the JarvisHostSnapshot.spatialHUD** array as A-Frame entities
c) **Use WebXR API** for immersive-ar mode on Quest 3 / Apple Vision Pro / phone AR
d) **Use AR.js** for marker-based AR on mobile (QR codes on lab hardware)
e) **Apply GMRI palette** (emerald/silver/black/crimson) from `JarvisGMRIPalette`
f) **Render JarvisSpatialHUDElement** — each element becomes a positioned glowing panel in 3D space
g) **Render JarvisVoiceGateSnapshot** — the voice gate gets a 3D holographic indicator (green/red glow)
h) **Support head-locked AND world-fixed anchors** (from JarvisSpatialAnchor enum)

### Architecture
```
index.html
├── <a-scene> with vr-mode-ui, embedded
├── <a-entity id="rig"> — camera rig with look-controls, wasd-controls
├── Spatial HUD Layer
│   ├── headLocked entities (follow camera)
│   │   ├── Voice Gate indicator (top-center, green/red glow)
│   │   ├── Connection state badge (top-right)
│   │   └── Status readout (bottom-center)
│   └── worldFixed entities (anchor in room space)
│       ├── HomeKit bridge status panel (workshop_bench anchor)
│       ├── Obsidian vault panel (workshop_bench anchor, offset)
│       ├── Node registry (orbiter anchor, slowly rotating)
│       └── Signal flow visualization (orbiter anchor)
├── Knowledge Graph Layer (from the_workshop.html)
│   ├── Node spheres (entity/skill/memory colors per GMRI palette)
│   └── Edge lines (relation colors)
├── AR Marker Layer (AR.js)
│   └── <a-marker> for each physical device in lab
└── Data Connection
    ├── WebSocket proxy connection (same ws:// pattern as PWA)
    ├── TunnelCrypto (JS ChaCha20-Poly1305 via libsodium.js or tweetnacl)
    ├── Registration message on connect
    ├── Heartbeat every 15 seconds
    └── Snapshot consumer → renders spatialHUD array
```

### Key Functions

```javascript
// Connect to tunnel (reuse PWA pattern)
function connectTunnel(wsProxyURL) {
    socket = new WebSocket(wsProxyURL);
    socket.onmessage = (event) => {
        const packet = JSON.parse(event.data);
        const decrypted = tunnelCrypto.open(packet.payload);
        const message = JSON.parse(decrypted);
        if (message.kind === 'snapshot') renderSpatialHUD(message.snapshot);
    };
}

// Render spatial HUD elements into A-Frame scene
function renderSpatialHUD(snapshot) {
    // Voice gate indicator
    const gateState = snapshot.voiceGate?.state || 'grey';
    const gateColor = gmriPalette(gateState);
    document.getElementById('voice-gate-indicator')
        .setAttribute('material', 'color', gateColor);
    
    // Spatial HUD elements
    (snapshot.spatialHUD || []).forEach(element => {
        renderHUDElement(element);
    });
    
    // Knowledge graph (if present)
    if (snapshot.recentThoughts) renderThoughts(snapshot.recentThoughts);
    if (snapshot.recentSignals) renderSignals(snapshot.recentSignals);
}

// Anchor mapping
const anchorPositions = {
    head_locked: null,  // parent to camera rig
    world_fixed: { x: 0, y: 1.5, z: -2.5 },
    workshop_bench: { x: -0.72, y: 1.52, z: -1.8 },
    orbiter: null  // slowly rotating around origin
};

function renderHUDElement(element) {
    const pos = anchorPositions[element.anchor];
    const color = gmriPalette(element.state);
    // Create/update a-entity with text + glow
}
```

### WebXR Entry Mode

```javascript
// Immersive AR entry (Quest 3, AVP)
async function enterXR() {
    if (!navigator.xr) return;
    const supported = await navigator.xr.isSessionSupported('immersive-ar');
    if (!supported) return;
    const session = await navigator.xr.requestSession('immersive-ar', {
        requiredFeatures: ['hit-test'],
        optionalFeatures: ['dom-overlay', 'light-estimation']
    });
    // A-Frame handles the rest when scene is embedded
    document.querySelector('a-scene').enterVR();
}
```

### Build Sequence
```
1. REPLACE xr.grizzlymedicine.icu/index.html with full spatial cockpit
2. ADD tunnel-crypto.js — ChaCha20-Poly1305 in JS (tweetnacl or libsodium-wrappers)
3. ADD spatial-hud-renderer.js — A-Frame component for JarvisSpatialHUDElement
4. ADD knowledge-graph-renderer.js — port from the_workshop.html
5. ADD ar-markers.js — AR.js device marker mapping
6. TEST manually: open in browser, verify tunnel connects, HUD renders
7. TEST: enter immersive-ar mode on Quest/AVP
8. DEPLOY: rsync xr.grizzlymedicine.icu/ to charlie:/var/www/xr/
```

---

## SPEC-GAP-003: WiFi CSI (Channel State Information)

### Problem
Zero code. No CoreWLAN, no NetworkExtension, no signal analysis. This is a research-grade capability — WiFi CSI enables through-wall presence detection, gesture recognition, and room-level spatial awareness.

### Reality Check
- Apple does NOT expose CSI (Channel State Information) through any public API on iOS/macOS
- CoreWLAN gives RSSI, BSSID, channel, PHY mode — NOT subcarrier-level CSI
- NetworkExtension gives VPN/NET tunneling — NOT physical layer data
- True CSI requires: Linux with Intel AX200/AX210 + `nexmon_cli`, or Atheros + `atheros-csi`, or ESP32 with custom firmware

### What IS Possible on Apple Silicon

**1. `Jarvis/Sources/JarvisCore/Network/WiFiEnvironmentScanner.swift` (NEW)**
```swift
import CoreWLAN
import Foundation

public final class WiFiEnvironmentScanner {
    private let client = CWWiFiClient.shared()
    
    public struct WiFiSnapshot: Sendable {
        public let ssid: String?
        public let bssid: String?
        public let rssi: Int          // dBm
        public let channel: Int
        public let channelWidth: Int   // MHz
        public let phyMode: String     // 802.11ax, ac, n
        public let noise: Int?         // dBm (if available)
        public let timestamp: String
    }
    
    public func currentSnapshot() -> WiFiSnapshot {
        let iface = client.interface()
        return WiFiSnapshot(
            ssid: iface?.ssid(),
            bssid: iface?.bssid(),
            rssi: iface?.rssiValue() ?? 0,
            channel: iface?.wlanChannel().channelNumber ?? 0,
            channelWidth: iface?.wlanChannel().channelWidth.rawValue ?? 0,
            phyMode: phyModeString(iface?.activePHYMode()),
            noise: nil,  // CoreWLAN doesn't expose noise
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    public func scanForNetworks() -> [CWWiFiScanResult] {
        // Requires Location permission on macOS
        let iface = client.interface()
        return (try? iface?.scanForNetworks(withSSID: nil)) ?? []
    }
}
```

**2. `Jarvis/Sources/JarvisCore/Network/PresenceDetecor.swift` (NEW)**
- Uses WiFi RSSI fingerprinting (NOT true CSI) for room-level presence detection
- Record baseline RSSI fingerprints per room (walking calibration)
- Compare live RSSI against baselines to estimate room occupancy
- Feed into MyceliumControlPlane as a presence signal

**3. Telemetry Integration**
- Log `wifi_environment` telemetry every 30 seconds
- Feed RSSI drift into PheromoneEngine as a spatial signal
- Publish presence state in JarvisHostSnapshot

### Build Sequence
```
1. CREATE Jarvis/Sources/JarvisCore/Network/WiFiEnvironmentScanner.swift
2. CREATE Jarvis/Sources/JarvisCore/Network/PresenceDetector.swift
3. ADD wifi_environment telemetry table to TelemetryStore
4. ADD WiFiSnapshot to JarvisHostSnapshot
5. MODIFY JarvisRuntime — add wifiScanner property
6. ADD WiFiEnvironmentScannerTests.swift — 3 tests (snapshot, scan, telemetry)
7. BUILD + TEST
```

### IMPORTANT CAVEAT
This is RSSI-based proximity, NOT true CSI. For actual subcarrier-level CSI, you need a Linux box with nexmon-patched Intel WiFi. That's a separate hardware project. This spec delivers what's possible on the Apple platform.

---

## SPEC-GAP-004: Mesh Display Control — The Hardware Output Layer

### Problem
`DisplayCommandExecutor` shells out to `/usr/local/bin/m1ddc` but **m1ddc is not installed**. The AirPlay route just queues a GUI intent (no actual AirPlay connection code). The HTTP route returns a stub. HDMI-CEC throws. This is all scaffolding with no plumbing.

### Fix 1: DDC/CI — Install and Wire m1ddc

```bash
# Install m1ddc
brew install waydab/tap/m1ddc
# OR build from source: https://github.com/waydab/m1ddc
```

Then harden the DDC executor:
```swift
private func executeDDCCommand(display: DisplayEndpoint, action: String, parameters: [String: String]) throws -> ExecutionResult {
    let displayIndex = registry.displayIndex(for: display.id) ?? 1
    let m1ddcPath = "/usr/local/bin/m1ddc"
    
    // Verify binary exists
    guard FileManager.default.fileExists(atPath: m1ddcPath) else {
        throw JarvisError.processFailure("m1ddc not found at \(m1ddcPath). Install: brew install waydab/tap/m1ddc")
    }
    
    // DDC/CI input source codes
    let inputSource: String
    switch action {
    case "display-telemetry", "display-hud", "display-dashboard":
        inputSource = "17"  // USB-C/DisplayPort
    case "display-camera":
        inputSource = "15"  // HDMI (typical)
    default:
        inputSource = "17"
    }
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: m1ddcPath)
    process.arguments = ["display", "\(displayIndex)", "set", "input", inputSource]
    
    let pipe = Pipe()
    process.standardError = pipe
    
    try process.run()
    process.waitUntilExit()
    
    guard process.terminationStatus == 0 else {
        let errorData = try pipe.fileHandleForReading.readToEnd() ?? Data()
        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown DDC error"
        throw JarvisError.processFailure("m1ddc failed: \(errorMessage)")
    }
    
    return ExecutionResult(
        success: true,
        spokenText: "Switched \(display.displayName) to Mac input.",
        details: ["display": display.id, "action": action, "inputSource": inputSource]
    )
}
```

### Fix 2: AirPlay — Use pyatv for Real AirPlay 2 Control

**`Jarvis/Sources/JarvisCore/Interface/AirPlayBridge.swift` (NEW)**
```swift
import Foundation

public final class AirPlayBridge {
    private let pythonPath = "/usr/bin/python3"
    private let pyatvScriptPath: String
    
    public init(paths: WorkspacePaths) {
        self.pyatvScriptPath = paths.storageRoot.appendingPathComponent("scripts/airplay_switch.py").path
    }
    
    public func switchInput(deviceAddress: String, appName: String) async throws -> ExecutionResult {
        guard FileManager.default.fileExists(atPath: pyatvScriptPath) else {
            throw JarvisError.processFailure("AirPlay script not found at \(pyatvScriptPath)")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [pyatvScriptPath, deviceAddress, appName]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw JarvisError.processFailure("AirPlay switch failed for \(deviceAddress)")
        }
        
        return ExecutionResult(
            success: true,
            spokenText: "Switched to \(appName) on AirPlay device.",
            details: ["address": deviceAddress, "app": appName]
        )
    }
}
```

**`scripts/airplay_switch.py` (NEW)**
```python
#!/usr/bin/env python3
"""Switch AirPlay 2 input using pyatv Library."""
import sys
import asyncio
from pyatv import scan, connect

async def switch_app(host, app_name):
    devices = await scan(hosts=[host])
    if not devices:
        print(f"No AirPlay device found at {host}", file=sys.stderr)
        sys.exit(1)
    
    atv = devices[0]
    async with connect(atv) as app:
        # Launch specific app if available
        if hasattr(app, 'launch_app'):
            await app.launch_app(app_name)
        print(f"Switched to {app_name} on {atv.name}")

if __name__ == '__main__':
    asyncio.run(switch_app(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "Jarvis"))
```

### Fix 3: HTTP Display Route — Real HTTP Commands

For smart TVs with HTTP control APIs (LG WebOS, Samsung Tizen):

**`Jarvis/Sources/JarvisCore/Interface/HTTPDisplayBridge.swift` (NEW)**
```swift
public final class HTTPDisplayBridge {
    public func launchApp(address: String, appId: String) async throws -> ExecutionResult {
        // WebOS: POST http://<tv>:3000/apps/{appId}
        // Samsung: POST http://<tv>:8001/api/v2/apps/{appId}
        guard let url = URL(string: "http://\(address):3000/apps/\(appId)") else {
            throw JarvisError.invalidInput("Invalid display address: \(address)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        
        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        
        guard httpResponse?.statusCode == 200 else {
            throw JarvisError.processFailure("Display at \(address) returned status \(httpResponse?.statusCode ?? 0)")
        }
        
        return ExecutionResult(
            success: true,
            spokenText: "Launched app on HTTP display at \(address).",
            details: ["address": address, "appId": appId]
        )
    }
}
```

### Fix 4: HDMI-CEC — Shell Out to cec-client

**`Jarvis/Sources/JarvisCore/Interface/HDMICECBridge.swift` (NEW)**
```swift
public final class HDMICECBridge {
    private let cecClientPath = "/usr/local/bin/cec-client"
    
    public func switchInput(outputPort: Int) throws -> ExecutionResult {
        guard FileManager.default.fileExists(atPath: cecClientPath) else {
            throw JarvisError.processFailure("cec-client not found. Install: brew install cec-client")
        }
        // echo "tx 1f:82:\(String(outputPort, radix: 16))" | cec-client -s
        // 1f = recorder address, 82 = active source command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "echo 'tx 1f:82:\(String(outputPort, radix: 16).uppercased())' | \(cecClientPath) -s -p 1"]
        try process.run()
        process.waitUntilExit()
        
        return ExecutionResult(
            success: process.terminationStatus == 0,
            spokenText: process.terminationStatus == 0 ? "Switched HDMI input." : "HDMI-CEC switch failed.",
            details: ["port": outputPort]
        )
    }
}
```

### Build Sequence
```
1. brew install waydab/tap/m1ddc  (or build from source)
2. MODIFY DisplayCommandExecutor.swift — harden DDC path with binary existence check
3. CREATE AirPlayBridge.swift — pyatv subprocess
4. CREATE scripts/airplay_switch.py — pyatv AirPlay 2 control
5. CREATE HTTPDisplayBridge.swift — WebOS/Tizen HTTP control
6. CREATE HDMICECBridge.swift — cec-client subprocess
7. MODIFY DisplayCommandExecutor.routeToDisplay() — wire real bridges
8. ADD DisplayBridgeTests.swift — test all 4 transports with mocked processes
9. BUILD + TEST
```

---

## SPEC-GAP-005: visionOS Client

### Problem
Zero ImmersiveSpace, zero RealityKit code. The protocol stack supports spatial anchors (headLocked, worldFixed, workshopBench, orbiter) but there's no renderer.

### Required Files

**1. `Jarvis/Vision/AppVision/RealJarvisVisionApp.swift` (NEW)**
```swift
import SwiftUI
import JarvisVisionCore

@main
struct RealJarvisVisionApp: App {
    @StateObject private var store: JarvisVisionCockpitStore
    
    init() {
        _store = StateObject(wrappedValue: JarvisVisionCockpitStore())
    }
    
    var body: some Scene {
        WindowGroup {
            JarvisVisionCockpitView(store: store)
                .task { await store.start() }
        }
        
        ImmersiveSpace(id: "jarvis-workshop") {
            JarvisWorkshopImmersiveView(store: store)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
```

**2. `Jarvis/Vision/Sources/JarvisVisionCore/JarvisWorkshopImmersiveView.swift` (NEW)**
- This IS the spatial cockpit for Apple Vision Pro
- Uses RealityKit to render `JarvisSpatialHUDElement` as 3D panels floating in the workshop space
- Voice gate indicator = glowing emerald/crimson sphere at head-locked position top-center
- HomeKit/Obsidian panels = translucent glass panels on workshop_bench anchor
- Node registry = slowly rotating ring of entity nodes (orbiter anchor)
- Signal flow = particle trails between connections

```swift
import RealityKit
import SwiftUI

struct JarvisWorkshopImmersiveView: View {
    @ObservedObject var store: JarvisVisionCockpitStore
    
    var body: some View {
        RealityView { content in
            // Root anchor entity
            let root = Entity()
            
            // Voice gate indicator (head-locked)
            let voiceGate = makeVoiceGateEntity(snapshot: store.state.snapshot?.voiceGate)
            root.addChild(voiceGate)
            
            // World-fixed panels
            let homeKitPanel = makePanelEntity(
                title: "HomeKit Bridge",
                content: store.state.snapshot?.homeKitBridge?.bridgeState ?? "—",
                position: SIMD3<Float>(-0.72, 1.52, -1.8),
                color: .green
            )
            root.addChild(homeKitPanel)
            
            // ... more panels
            
            content.add(root)
        }
        .onAppear { store.enterImmersiveSpace() }
    }
    
    func makeVoiceGateEntity(snapshot: JarvisVoiceGateSnapshot?) -> Entity {
        let entity = Entity()
        let mesh = MeshResource.generateSphere(radius: 0.05)
        let stateColor: UIColor = switch snapshot?.state {
        case .green: .systemGreen
        case .red: .systemRed
        case .yellow, .orange: .systemYellow
        default: .systemGray
        }
        let material = SimpleMaterial(color: stateColor, isMetallic: true)
        let model = ModelEntity(mesh: mesh, materials: [material])
        entity.addChild(model)
        entity.position = SIMD3<Float>(0, 0.3, -0.5) // head-locked offset
        return entity
    }
}
```

**3. `Jarvis/Vision/Sources/JarvisVisionCore/JarvisVisionCockpitView.swift` (NEW)**
- 2D flat cockpit view for the non-immersive window (same panel structure as iOS)
- "Enter Workshop" button that opens the ImmersiveSpace

**4. `Jarvis/Vision/Sources/JarvisVisionCore/JarvisVisionCockpitStore.swift` (NEW)**
- Same pattern as MobileCockpitStore but role = `.visionPro`
- `enterImmersiveSpace()` / `exitImmersiveSpace()` functions
- Anchor tracking state

### Build Sequence
```
1. CREATE Jarvis/Vision/AppVision/RealJarvisVisionApp.swift
2. CREATE Jarvis/Vision/Sources/JarvisVisionCore/JarvisVisionCockpitView.swift
3. CREATE Jarvis/Vision/Sources/JarvisVisionCore/JarvisWorkshopImmersiveView.swift
4. CREATE Jarvis/Vision/Sources/JarvisVisionCore/JarvisVisionCockpitStore.swift
5. ADD visionOS target to Package.swift or Xcode project
6. NOTE: Requires Xcode with visionOS SDK to compile — may need conditional compilation
7. ADD JarvisVisionCockpitStoreTests.swift (can test store logic without visionOS SDK)
```

### CRITICAL NOTE
visionOS compilation requires the visionOS SDK in Xcode. The store and protocol code can be tested on macOS with `#if os(visionOS)` guards. The RealityKit views can only be compiled with the visionOS target. This gap may require a dedicated Xcode build step.

---

## IMPLEMENTATION ORDER (Priority-Driven)

### PHASE 1 — Fix What's Broken (1-2 hours)
```
GAP-004 Fix 1 — Install m1ddc, harden DDC executor (HIGH: existing code is useless without binary)
GAP-004 Fix 2 — AirPlay bridge (HIGH: lab TV control is a core voice command)
GAP-004 Fix 3 — HTTP display bridge (MEDIUM: useful for smart TVs)
```

### PHASE 2 — macOS Desktop (2-3 hours)
```
GAP-001 — macOS Cockpit App (HIGH: operator's primary machine needs visual feedback)
```

### PHASE 3 — WebXR Spatial Portal (3-4 hours)
```
GAP-002 — xr.grizzlymedicine.icu rewrite (HIGH: this is the spatial web presence)
```

### PHASE 4 — WiFi Environment (1-2 hours)
```
GAP-003 — WiFiEnvironmentScanner + PresenceDetector (MEDIUM: useful but RSSI-only)
```

### PHASE 5 — visionOS Client (2-3 hours)
```
GAP-005 — visionOS ImmersiveSpace cockpit (MEDIUM: requires visionOS SDK)
```

### TOTAL: ~10-14 hours of implementation

---

## RALPH WIGGUM LOOP — Execution Protocol for Qwen

**READ this file completely before starting.**

**LOOP:**
```
1. READ the current spec item (GAP-001 through GAP-005, in order)
2. EVALUATE what files exist vs what's needed
3. CREATE or MODIFY the required files
4. BUILD: xcodebuild build -scheme Jarvis -destination 'platform=macOS' -quiet
5. If BUILD FAILS → READ the error → FIX the error → BUILD again (max 3 retries per item)
6. If BUILD PASSES after 3 retries → SKIP to next item, log the failure
7. TEST: xcodebuild test -scheme Jarvis -destination 'platform=macOS' -quiet
8. If TESTS FAIL → READ the failure → FIX → RETEST (max 3 retries)
9. WRITE a brief status to /Users/grizzmed/REAL_JARVIS/GAP_CLOSING_STATUS.md
10. NEXT item → GOTO 1
```

**ANTI-IDLE RULES:**
- If you write "I'll analyze..." more than once without producing a file change, MOVE ON
- If you spend >5 minutes on one item without a BUILD attempt, MOVE ON
- If you get stuck on visionOS SDK availability, SKIP GAP-005 and note it
- If m1ddc install fails (brew not available or Apple Silicon issue), write the code anyway with the existence check and MOVE ON

**STOP CONDITION:** All 5 GAPs processed (each either DONE or SKIPPED with reason logged)

**STATUS FILE FORMAT** (`GAP_CLOSING_STATUS.md`):
```markdown
# Gap Closing Status

## GAP-001: macOS Desktop — [DONE/SKIPPED/PARTIAL]
## GAP-002: WebXR Portal — [DONE/SKIPPED/PARTIAL]
## GAP-003: WiFi CSI — [DONE/SKIPPED/PARTIAL]
## GAP-004: Mesh Display — [DONE/SKIPPED/PARTIAL]
## GAP-005: visionOS — [DONE/SKIPPED/PARTIAL]

## Final Test Count: [N] tests, [N] failures
## Build Status: [GREEN/RED]
```

---

## AGENT-SKILLS REFERENCE

The `~/agent-skills/` directory contains OpenCode/Claude Code skill definitions. The relevant skills for this build are:

- `spec-driven-development` — Follow spec before coding
- `incremental-implementation` — Build one file at a time, compile between each
- `test-driven-development` — Write test, then implementation
- `frontend-ui-engineering` — For SwiftUI and A-Frame work
- `api-and-interface-design` — For tunnel protocol additions
- `debugging-and-error-recovery` — When builds fail

Read each skill's `SKILL.md` before starting the corresponding phase.