import AVFoundation
import Foundation

/// Speaks with pre-recorded ElevenLabs clips (`scripts/generate_voice_bank.py`) when one exists for
/// the phrase, so the live-set coach sounds like a real voice instead of the system TTS. Falls back
/// to `SpeechCoachVoice` for anything unrecorded, so a phrase without a clip is never silence.
@MainActor
public final class BankedCoachVoice: NSObject, CoachVoice {
    private let bank: CoachPhraseBank
    private let bundle: Bundle
    private let fallback: SpeechCoachVoice
    private var player: AVAudioPlayer?
    private var currentPriority: VoicePriority?
    /// Last clip played per phrase, so the same variant isn't repeated back-to-back.
    private var lastFileByPhrase: [String: String] = [:]

    public convenience override init() {
        self.init(bundle: .module, fallback: SpeechCoachVoice())
    }

    /// Not public: `bundle`/`fallback` are injected by tests (via `@testable import`), production
    /// code always uses the zero-argument `init()`.
    init(bundle: Bundle, fallback: SpeechCoachVoice) {
        self.bank = .loadBundled(from: bundle)
        self.bundle = bundle
        self.fallback = fallback
        super.init()
    }

    public var headphonesConnected: Bool { fallback.headphonesConnected }

    public func prepare() { fallback.prepare() }

    public func speak(_ text: String, priority: VoicePriority) {
        guard let variant = bank.pickVariant(for: text, excluding: lastFileByPhrase[text], exists: hasClip(_:)),
            let url = clipURL(variant.file)
        else {
            fallback.speak(text, priority: priority)
            return
        }
        switch priority {
        case .count:
            // Unlike AVSpeechSynthesizer, AVAudioPlayer instances don't queue: always cut off
            // whatever is currently playing so two clips never overlap.
            if let player, player.isPlaying { player.stop() }
        case .advice:
            guard !(player?.isPlaying ?? false) else { return }
        }
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else {
            fallback.speak(text, priority: priority)
            return
        }
        lastFileByPhrase[text] = variant.file
        newPlayer.delegate = self
        currentPriority = priority
        player = newPlayer
        newPlayer.play()
    }

    public func signalSetStart() {
        fallback.signalSetStart()
    }

    public func finish() {
        player?.stop()
        player = nil
        fallback.finish()
    }

    private func clipURL(_ file: String) -> URL? {
        bundle.url(forResource: file, withExtension: "mp3")
    }

    private func hasClip(_ file: String) -> Bool { clipURL(file) != nil }
}

extension BankedCoachVoice: AVAudioPlayerDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.currentPriority = nil }
        }
    }
}
