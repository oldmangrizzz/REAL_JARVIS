# Failure Mode Analysis and Recovery Strategies

## Critical Failure Modes (High Severity)

### 1. Watch Battery Dies Mid-Shift

**Scenario:** EMT watch battery drains during shift, phone in truck, headphones still paired.

**Impact:** 
- Complete loss of audio gateway
- No voice communication capability
- No connection to Jarvis
- Emergency responder isolated

**Recovery Strategy:**
```
Battery Level Action
----------- -------------------------------------------
0-5%        Emergency protocol: Send "battery-critical" ping to Jarvis + phone
5-10%       Critical: Enable ultra-low power mode (keepalive only, 120s interval)
10-20%      Warning: Signal "low-battery" with recommended actions
20-50%      Normal: Monitor, suggest charging
50%+        Normal operation
```

**Implementation:**
```swift
class BatteryManager {
    static let shared = BatteryManager()
    
    func batteryDidUpdate(_ level: Int) {
        switch level {
        case 0...5:
            // Critical - emergency protocol
            sendEmergencyPing(reason: "battery-critical")
            enableUltraLowPowerMode()
            
        case 6...10:
            // Critical warning
            sendWarningPing(reason: "low-battery")
            enableLowPowerMode()
            
        case 11...20:
            // Warning
            logTelemetry("battery-low")
            suggestCharging()
            
        case 21...50:
            // Monitor
            logTelemetry("battery-medium")
            
        case 51...100:
            // Normal
            disablePowerSaving()
        }
    }
    
    func enableUltraLowPowerMode() {
        // Reduce keepalive to 120s (from 30s)
        keepaliveInterval = .deepSleep
        // Disable non-critical features
        watchOrientation.updateFrequency = 0.5 // 2Hz (from 30Hz)
        audioProcessingQuality = .low
    }
}
```

### 2. Headphones Only Expose A2DP (No Mic)

**Scenario:** Generic headphones connected, no H1/H2 mic passthrough available.

**Impact:**
- Audio playback works (watch → headphones)
- Voice capture only via watch mic (lower quality)
- Noise sensitivity higher (no BT mic noise cancellation)

**Recovery Strategy:**
```swift
class AudioRouteManager {
    func reportMicAvailability() {
        if let route = session.currentRoute,
           let port = route.outputs.first(where: { $0.portType == .bluetoothHFP }) {
            if port.micAvailable {
                currentSource = .watchH1H2
            } else {
                currentSource = .watchMicOnly
            }
        } else {
            currentSource = .watchMicOnly
        }
    }
    
    /// Operator notification when mic unavailable
    func notifyMicAvailable() {
        let message: String
        switch currentSource {
        case .watchH1H2:
            message = "Mic available via headphones"
        case .watchMicOnly:
            message = "Mic available via watch (no headphones mic)"
        }
        
        watchHaptic.vibrate(.warning)
        speak(message: message)
        
        // Suggest headphones replacement
        suggestHeadphonesMicSupport()
    }
}
```

### 3. BT Connection Lost, Phone Out of Range

**Scenario:** Watch loses BT connection to headphones, phone not in mesh/WiFi range.

**Impact:**
- Audio playback stops
- Voice capture still works (watch mic)
- No notification to user unless we build UI

**Recovery Strategy:**
```swift
class BTConnectionManager {
    private var connectionState: ConnectionState = .disconnected
    
    enum ConnectionState {
        case connected
        case reconnecting(timeout: Date)
        case disconnected(pendingReconnect: Date)
    }
    
    func btDidDisconnect() {
        connectionState = .disconnected(pendingReconnect: Date().add(minutes: 2))
        
        // Notify user via haptic
        watchHaptic.vibrate(.error)
        speak(message: "Headphones disconnected")
        
        // Log telemetry
        logTelemetry(.btDisconnection)
    }
    
    func btDidReconnect() {
        connectionState = .connected
        
        // Notify user via haptic
        watchHaptic.vibrate(.success)
        speak(message: "Headphones reconnected")
        
        // Restore audio
        restoreAudioRoute()
    }
}
```

### 4. Off-Wrist → Session Freeze

**Scenario:** Watch removed from wrist, session frozen, biometric vault locked.

**Impact:**
- All voice communication paused
- Audio routing suspended
- No tunnel keepalive (to save battery)
- Biometric vault secured

**Recovery Strategy:**
```swift
class SessionManager {
    var currentState: SessionState = .active
    
    enum SessionState {
        case active
        case frozen(reason: OffWristReason, duration: TimeInterval)
        case suspended(reason: LowPowerReason)
    }
    
    func wristDetectDidChange(_ detected: Bool) {
        if !detected {
            // Off-wrist
            currentState = .frozen(reason: .offWrist, duration: 0)
            freezeSession()
            batteryManager.suggestCharging()
        } else {
            // On-wrist
            switch currentState {
            case .frozen:
                requestBiometricUnlock()
            case .suspended:
                // Check if battery/power sufficient to resume
                if BatteryManager.currentLevel > 20 {
                    resumeSession()
                }
            default:
                break
            }
        }
    }
    
    func freezeSession() {
        // Pause all active connections
        networkManager.suspend()
        audioManager.suspend()
        speechRecognizer.stop()
        
        // Save state
        sessionStatePersist.save(currentState)
        
        // Telemetry
        logTelemetry(.sessionFrozen(duration: 0))
    }
    
    func requestBiometricUnlock() {
        // Wrist-detect is available, so use it
        let wristDetected = WKInterfaceDevice.current().isWristDetected
        let passcodeSet = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        
        guard wristDetected || passcodeSet else {
            // Cannot unlock without biometric/passcode
            currentState = .frozen(reason: .biometricUnavailable, duration: 0)
            return
        }
        
        // Biometric check passed, unlock
        vault.unlock()
        resumeSession()
    }
    
    func resumeSession() {
        // Resume all connections
        networkManager.resume()
        audioManager.resume()
        speechRecognizer.start()
        
        // Restore state
        sessionStatePersist.restore()
        
        // Telemetry
        logTelemetry(.sessionResumed)
    }
}
```

### 5. Cellular Signal Lost

**Scenario:** Watch moves out of cellular coverage, phone not in mesh/WiFi range.

**Impact:**
- Tunnel to Jarvis lost
- No voice communication to Jarvis
- Local operations still work (watch mic, audio playback)

**Recovery Strategy:**
```swift
class NetworkManager {
    var currentPath: NWPath?
    
    func pathDidChange(_ path: NWPath) {
        currentPath = path
        
        switch path.status {
        case .satisfied:
            // Internet available
            connectToJarvis()
            startKeepalive()
            
        case .requiresConnection:
            // Need to establish connection
            suggestWiFiOrCellular()
            
        case .unsatisfied:
            // No internet
            disconnectFromJarvis()
            enableLocalMode()
        }
    }
    
    func suggestWiFiOrCellular() {
        // Check available networks
        let wifiAvailable = WiFiManager.isAvailable()
        let cellularAvailable = CellularManager.isAvailable()
        
        if wifiAvailable && !cellularAvailable {
            speak(message: "Connect to WiFi for Jarvis")
            showNotification(title: "WiFi Required", body: "Connect to Jarvis")
        } else if !wifiAvailable && cellularAvailable {
            speak(message: "Cellular available for Jarvis")
        } else if !wifiAvailable && !cellularAvailable {
            speak(message: "No network available for Jarvis")
            showNotification(title: "No Network", body: "Jarvis unavailable")
        }
    }
    
    func connectToJarvis() {
        tunnelClient.connect(host: "xr.grizzlymedicine.icu", port: 443)
    }
    
    func disconnectFromJarvis() {
        tunnelClient.disconnect()
    }
}
```

## Medium Severity Failure Modes

### 1. Watch Paired to Multiple Headphones

**Scenario:** User pairs multiple headphones to watch (AirPods, Bose, etc.)

**Resolution:** Operator can specify via voice: "Use AirPods", "Use Bose", "Use headphones"

### 2. Watch Enters Airplane Mode

**Recovery:** When airplane mode ends, auto-reconnect to previously paired headphones

### 3. Voice Recognition Timeout

**Recovery:** Fallback to simpler commands, or route to phone for better processing

## Failure Mode Priority Matrix

| Failure | Severity | Recovery Time | User Impact | Priority |
|---------|----------|--------------|-------------|----------|
| Battery dies | Critical | 5s (emergency) | High | P0 |
| BT disconnected | High | 2-3s | Medium | P1 |
| Off-wrist freeze | High | 30s (wait for wrist) | Medium | P1 |
| Cellular lost | Medium | Adaptive | Medium | P2 |
| Multiple headphones | Low | 5s (voice command) | Low | P3 |
| Airplane mode | Low | Auto-recover | Low | P3 |
| Voice timeout | Low | 10s (fallback) | Low | P3 |

## Recovery Time Targets

| Scenario | Target Recovery | Acceptable Max |
|----------|----------------|----------------|
| BT reconnection | <1s | 3s |
| Audio route restore | <500ms | 1s |
| Session resume | <10s | 30s |
| Cellular fallback | <15s | 30s |
| Biometric unlock | <5s | 10s |

## Operator-Facing Error Messages

```
P0 - Battery Critical
  "Warning: Watch battery critically low (X%). Immediately connect to charger or phone."
  
P1 - BT Disconnected  
  "Headphones disconnected. Tap to reconnect or say 'reconnect headphones'."
  
P1 - Off-Wrist
  "Session suspended. Return watch to wrist to resume."
  
P2 - No Cellular
  "Cellular signal lost. Connect to WiFi or keep phone nearby for Jarvis."
  
P3 - Headphones Selection
  "Multiple headphones detected. Say 'use AirPods' or 'use Bose' to select."
```

## Telemetry for Failure Analysis

| Event | Telemetry Keys | Purpose |
|-------|---------------|---------|
| batteryCritical | batteryLevel, durationSinceLastCharge, actionsTaken | Predictive maintenance |
| btDisconnected | duration, reconnectAttempts, successRate | BT stack health |
| offWrist | wristDetect.duration, sessionDuration, freezeReason | User behavior |
| cellularLost | duration, signalStrength, lastCellularStatus | Network health |
| voiceTimeout | utteranceLength, recognitionTime, fallbackUsed | Speech quality |

## Summary

**Critical failures (P0-P1) require <10s recovery** to maintain professional operator trust.
**Recovery strategies should be proactive** (suggest charging before battery critical).
**User notifications should be multi-modal** (haptic + audio + notification).
**Telemetry should capture every failure** for root cause analysis and improvement.
