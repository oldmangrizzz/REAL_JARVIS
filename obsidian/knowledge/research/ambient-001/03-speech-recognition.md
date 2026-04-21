# Speech Recognition Latency Research

## SFSpeechRecognizer on watchOS

### Current Performance (2026-Q2):

| Metric | Value | Notes |
|--------|-------|-------|
| Latency | 1000-2000 ms | From speech start to result |
| VAD Access | ❌ No | No API for voice activity detection |
| Continuous Mode | ✅ Yes | Streaming recognition supported |
| Batch Mode | ✅ Yes | Short utterances |
| Background | ⚠️ Limited | Tasks killed <30s, wakeups only |

### Streaming Speech Recognition:

```swift
let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
let request = SFSpeechAudioBufferRecognitionRequest()
request.shouldReportPartialResults = true

let audioEngine = AVAudioEngine()
let node = audioEngine.inputNode
let format = node.inputFormat(forBus: 0)

node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
    request.append(buffer)
}

speechRecognizer.recognitionTask(with: request) { result, error in
    if let text = result?.bestTranscription.formattedString {
        print("Partial: \(text)")
    }
}
```

### Latency Breakdown:
1. Audio capture: 50-100ms (watch mic quality)
2. Buffer processing: 100-200ms (1024 frame buffer)
3. Network roundtrip: 500-1000ms (watch → Jarvis backend)
4. Model inference: 200-500ms (transcription)
5. Result delivery: 50-100ms (back to watch)

**Total: 1000-2000ms** - Not barge-in capable

### AVAudioEngine for Local VAD:

**What's possible:**
- Buffer extraction with small chunks (1024 samples = ~23ms at 44kHz)
- Manual VAD via energy threshold / zero-crossing rate
- Audio processing in background (limited resources)

**Latency targets:**
- Current AVAudioEngine: 200-500ms (via manual processing)
- Target for barge-in: <200ms (requires hardware acceleration)

### Workaround Strategy:

1. **Watch mic only** - Accept 1000-2000ms latency
2. **H1/H2 mic passthrough** - Better mic quality, same latency
3. **Software pre-processing** - On-watch filtering, noise reduction
4. **Phone fallback** - When phone nearby, route to phone for lower latency

### Recommendation:

**Phase 1 (App Store):** Use watch mic, accept latency, document limitation
**Phase 2 (operator build):** Add AVAudioEngine with manual VAD for 200-500ms latency
**Future (Apple open):** LE Audio LC3 with hardware codec acceleration
