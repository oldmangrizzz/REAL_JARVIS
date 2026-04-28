import Foundation
import AVFoundation
import Speech
import SoundAnalysis
import Combine

/// Audio biome — AVAudioEngine, SFSpeechRecognizer, ambient analysis
///
/// Biological analogue: auditory system — cochlea (input), brainstem
/// reflex arc (ambient detection), cortex (speech parsing).
///
/// Monitors ambient sound level for JarvisAmbientState, performs
/// speech recognition for voice commands, and analyzes audio quality
/// for conversation clarity.
@MainActor
public final class JarvisAudioBiome: ObservableObject {

    // MARK: Published State

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var ambientLevel: AudioLevel = .unknown
    @Published public private(set) var isListening: Bool = false

    // MARK: Private State

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let analyzer: SNAudioStreamAnalyzer?

    private let soundLevelThreshold: Float = 0.05

    // MARK: Init

    public init() {
        self.analyzer = nil  // SoundAnalysis requires real-time input
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: Public API

    public func start() {
        Task { @MainActor in
            await requestAuthorization()
            guard isAuthorized else { return }
            startAudioAnalysis()
        }
    }

    public func stop() {
        stopAudioAnalysis()
        stopSpeechRecognition()
    }

    public func requestAuthorization() async {
        let micStatus = AVAudioApplication.shared.recordPermission
        switch micStatus {
        case .granted:
            isAuthorized = true
        case .denied:
            isAuthorized = false
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            isAuthorized = granted
        @unknown default:
            isAuthorized = false
        }
    }

    /// Start continuous speech recognition (voice command pipeline).
    public func startListening() {
        guard isAuthorized, let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        stopSpeechRecognition()

        let request = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = request
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            self?.analyzeBuffer(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("[JarvisAudioBiome] audio engine error: \(error)")
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] _, error in
            if error != nil { self?.stopSpeechRecognition() }
        }
    }

    public func stopListening() {
        stopSpeechRecognition()
    }

    // MARK: Private

    private func startAudioAnalysis() {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.analyzeBuffer(buffer)
        }
        audioEngine.prepare()
        do { try audioEngine.start() } catch { print("[JarvisAudioBiome] start error: \(error)") }
    }

    private func stopAudioAnalysis() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func stopSpeechRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    private func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelDataValue = channelData.pointee
        let channelDataCount = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<channelDataCount {
            sum += abs(channelDataValue[i])
        }
        let avgPower = sum / Float(channelDataCount)

        let level: AudioLevel
        if avgPower < 0.001 { level = .silent }
        else if avgPower < soundLevelThreshold { level = .ambient }
        else { level = .loud }

        Task { @MainActor [weak self] in
            if self?.ambientLevel != level {
                self?.ambientLevel = level
            }
        }
    }
}
