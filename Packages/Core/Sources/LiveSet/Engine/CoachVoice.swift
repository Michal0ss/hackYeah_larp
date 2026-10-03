import Foundation
import AVFoundation
import AudioToolbox

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
    /// A short, distinct sound (not speech) marking the exact moment a set starts being tracked —
    /// easier to react to on a half-second beat than a spoken word, and unambiguous in any language.
    func signalSetStart()
    /// Stops speaking and releases the audio session.
    func finish()
    var headphonesConnected: Bool { get }
}

/// Records what would be said. Used in tests and as a silent fallback.
@MainActor
public final class RecordingVoice: CoachVoice {
    public private(set) var spoken: [(text: String, priority: VoicePriority)] = []
    public private(set) var signalsSent = 0
    public var headphonesConnected: Bool { true }

    public init() {}
    public func prepare() {}
    public func speak(_ text: String, priority: VoicePriority) { spoken.append((text, priority)) }
    public func signalSetStart() { signalsSent += 1 }
    public func finish() {}
}

/// Speaks with the system voice (Polish if installed). Audio goes to headphones when connected.
@MainActor
public final class SpeechCoachVoice: NSObject, CoachVoice {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "pl-PL")
    private var currentPriority: VoicePriority?

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

    public func signalSetStart() {
        #if os(iOS)
        AudioServicesPlaySystemSound(SystemSoundID(1117))
        #endif
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
