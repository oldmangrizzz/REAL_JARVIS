import Foundation
import AVFoundation

/// Represents a barge‑in detection event emitted by a VAD gate.
public struct BargeInEvent {
    /// The time (in seconds) since the system boot when the event was generated.
    public let timestamp: TimeInterval
    /// Indicates whether speech was detected (`true`) or not (`false`).
    public let isSpeech: Bool
    /// An optional audio buffer containing the speech segment that triggered the event.
    public let audioBuffer: AVAudioPCMBuffer?

    /// Creates a new ``BargeInEvent``.
    /// - Parameters:
    ///   - timestamp: The event timestamp.
    ///   - isSpeech: Speech detection flag.
    ///   - audioBuffer: The raw audio that caused the detection, if any.
    public init(timestamp: TimeInterval, isSpeech: Bool, audioBuffer: AVAudioPCMBuffer? = nil) {
        self.timestamp = timestamp
        self.isSpeech = isSpeech
        self.audioBuffer = audioBuffer
    }
}

/// Protocol defining the contract for a duplex (full‑duplex) voice‑activity‑detection gate.
public protocol DuplexVADGate: AnyObject {
    /// Starts the VAD processing pipeline.
    func start()
    /// Stops the VAD processing pipeline.
    func stop()
    /// Feeds an audio buffer into the VAD for analysis.
    /// - Parameter buffer: An ``AVAudioPCMBuffer`` containing PCM samples.
    func process(buffer: AVAudioPCMBuffer)

    /// Callback invoked whenever a barge‑in event is detected.
    var onBargeIn: ((BargeInEvent) -> Void)? { get set }
}

/// A very lightweight on‑device VAD implementation used as a stub for the
/// ambient audio gateway. It simply measures the peak amplitude of each
/// incoming buffer and compares it against a configurable threshold.
public final class SimpleVADGate: DuplexVADGate {
    // MARK: - Public API

    public var onBargeIn: ((BargeInEvent) -> Void)?

    /// Creates a new ``SimpleVADGate``.
    /// - Parameters:
    ///   - threshold: The amplitude threshold above which speech is considered detected.
    ///   - sampleRate: Expected sample rate of incoming audio (used for future extensions).
    public init(threshold: Float = 0.02, sampleRate: Double = 16_000) {
        self.threshold = threshold
        self.sampleRate = sampleRate
    }

    public func start() {
        isRunning = true
    }

    public func stop() {
        isRunning = false
    }

    public func process(buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        guard let channelData = buffer.floatChannelData?.pointee else { return }

        let frameCount = Int(buffer.frameLength)
        var maxAmplitude: Float = 0

        for i in 0..<frameCount {
            let sample = fabsf(channelData[i])
            if sample > maxAmplitude {
                maxAmplitude = sample
            }
        }

        let speechDetected = maxAmplitude > threshold
        let event = BargeInEvent(
            timestamp: CACurrentMediaTime(),
            isSpeech: speechDetected,
            audioBuffer: speechDetected ? buffer : nil
        )
        onBargeIn?(event)
    }

    // MARK: - Private State

    private var isRunning = false
    private let threshold: Float
    private let sampleRate: Double
}