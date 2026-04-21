# AMBIENT-001 Audio Architecture Research

## AVAudioSession on watchOS 7+ (Series 6+)

### Core Capabilities:
- ✅ Audio session management
- ✅ Input/output device routing  
- ✅ Category configuration (.playAndRecord, .playback, .record)
- ❌ A2DP source (publish audio stream)
- ❌ SCO voice channel access
- ❌ LE Audio/LC3 support

### Connection Flow:
1. User pairs headphones to watch (Settings > Bluetooth)
2. Watch becomes BT CLIENT, headphones become BT SERVER (A2DP sink)
3. Watch主动 initiates BT connections
4. Headphones accept (A2DP sink mode)
5. Audio path: Watch → Headphones (direct, no phone)

### Key APIs:
```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, options: [.mixWithOthers])
try session.setActive(true)
let route = session.currentRoute
for port in route.outputs {
    print("Port: \(port.portName), Type: \(port.portType)")
}
```

### Supported portTypes:
- .builtInSpeaker (watch speaker)
- .builtInMic (watch mic)
- .bluetoothHFP (voice calls, H1/H2 headphones only)
- .bluetoothA2DP (music playback)
- .headphone (wired headphones)
- .airplay (AirPlay devices)
