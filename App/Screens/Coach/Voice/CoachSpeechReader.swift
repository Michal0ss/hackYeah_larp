import AVFoundation

/// Reads the coach's reply aloud, one sentence at a time, as `VoiceChatController` feeds them in
/// via `CoachVoice.SentenceStream`. `AVSpeechSynthesizer` queues utterances on its own, so repeated
/// `speak(_:)` calls are read in order without overlap. Doesn't touch the audio session itself — the
/// controller owns `.playAndRecord` for the whole voice conversation, not per utterance.
@MainActor
final class CoachSpeechReader: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    // Same voice selection as the tempo coach (LiveSet/Engine/CoachVoice.swift's SpeechCoachVoice),
    // so the trainer sounds like the same person whether it's counting reps or chatting.
    private let voice = AVSpeechSynthesisVoice(language: "pl-PL")
    private var onIdle: (() -> Void)?

    var isSpeaking: Bool { synthesizer.isSpeaking }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    /// Barge-in: the user tapped the mic (or stop) while the coach was still talking.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Called when the synthesizer has nothing left queued (not after every single sentence).
    func setOnIdle(_ callback: (() -> Void)?) {
        onIdle = callback
    }
}

extension CoachSpeechReader: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if !synthesizer.isSpeaking { self.onIdle?() } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in if !synthesizer.isSpeaking { self.onIdle?() } }
    }
}
