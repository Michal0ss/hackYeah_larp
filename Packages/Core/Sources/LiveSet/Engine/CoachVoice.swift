import Foundation
import AVFoundation
import Contracts

public enum VoicePriority: Sendable {
    /// The counting ("jeden, dwa, trzy"). Interrupts advice.
    case count
    /// A short correction. Dropped when something else is being said.
    case advice
}

@MainActor
public protocol CoachVoice: AnyObject {
    /// Activates the audio session (ducks other audio, routes to headphones).
    func prepare()
    func speak(_ text: String, priority: VoicePriority)
    /// A short beep (not speech) marking the start of a phase: a lower one for lowering, a higher one for lifting.
    /// Easier to follow on a beat than a spoken word. Other phases are silent.
    func playPhaseBeep(_ phase: RepPhase)
    /// Stops speaking and releases the audio session.
    func finish()
    var headphonesConnected: Bool { get }
}

/// Records what would be said. Used in tests and as a silent fallback.
@MainActor
public final class RecordingVoice: CoachVoice {
    public private(set) var spoken: [(text: String, priority: VoicePriority)] = []
    public private(set) var beeps: [RepPhase] = []
    public var headphonesConnected: Bool { true }

    public init() {}
    public func prepare() {}
    public func speak(_ text: String, priority: VoicePriority) { spoken.append((text, priority)) }
    public func playPhaseBeep(_ phase: RepPhase) { beeps.append(phase) }
    public func finish() {}
}

/// Speaks with the system voice (Polish if installed). Audio goes to headphones when connected.
@MainActor
public final class SpeechCoachVoice: NSObject, CoachVoice {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "pl-PL")
    private var currentPriority: VoicePriority?
    private var beepPlayers: [RepPhase: AVAudioPlayer] = [:]

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public var headphonesConnected: Bool {
        #if os(iOS)
        let headphoneTypes: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { headphoneTypes.contains($0.portType) }
        #else
        return false
        #endif
    }

    public func prepare() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        #endif
        // Both beeps are decoded now, so the first one does not sound late.
        for phase in [RepPhase.eccentric, .concentric] { _ = beepPlayer(for: phase) }
    }

    public func speak(_ text: String, priority: VoicePriority) {
        switch priority {
        case .count:
            if synthesizer.isSpeaking, currentPriority == .advice {
                synthesizer.stopSpeaking(at: .immediate)
            }
        case .advice:
            guard !synthesizer.isSpeaking else { return }
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        currentPriority = priority
        synthesizer.speak(utterance)
    }

    public func playPhaseBeep(_ phase: RepPhase) {
        guard let player = beepPlayer(for: phase) else { return }
        player.currentTime = 0
        player.play()
    }

    private func beepPlayer(for phase: RepPhase) -> AVAudioPlayer? {
        let frequency: Double
        switch phase {
        case .eccentric: frequency = 520
        case .concentric: frequency = 880
        case .bottomPause, .topPause: return nil
        }
        if beepPlayers[phase] == nil {
            let player = try? AVAudioPlayer(data: Self.beepWave(frequency: frequency))
            player?.prepareToPlay()
            beepPlayers[phase] = player
        }
        return beepPlayers[phase]
    }

    /// A short sine beep with a soft attack and release, as 16-bit mono WAV data.
    static func beepWave(frequency: Double, duration: Double = 0.18, sampleRate: Double = 44_100) -> Data {
        let count = Int(duration * sampleRate)
        var samples = [Int16]()
        samples.reserveCapacity(count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = min(1, t / 0.01, (duration - t) / 0.04)
            samples.append(Int16(sin(2 * .pi * frequency * t) * envelope * 0.8 * Double(Int16.max)))
        }
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        let dataSize = UInt32(count * 2)
        var wave = Data("RIFF".utf8)
        wave.append(contentsOf: le(36 + dataSize))
        wave.append(Data("WAVEfmt ".utf8))
        wave.append(contentsOf: le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1)) + le(UInt32(sampleRate)))
        wave.append(contentsOf: le(UInt32(sampleRate) * 2) + le(UInt16(2)) + le(UInt16(16)))
        wave.append(Data("data".utf8))
        wave.append(contentsOf: le(dataSize))
        for sample in samples { wave.append(contentsOf: le(sample)) }
        return wave
    }

    public func finish() {
        synthesizer.stopSpeaking(at: .immediate)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

extension SpeechCoachVoice: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !synthesizer.isSpeaking { self.currentPriority = nil }
        }
    }
}
