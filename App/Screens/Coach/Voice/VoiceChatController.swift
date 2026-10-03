import AVFoundation
import CoachVoice
import Foundation
import Observation

/// Drives "ask by voice, hear the answer" on top of the existing text chat: recognizes speech
/// on-device and sends it through `CoachViewModel.send` exactly like typed text (same consent, same
/// tools, same history — `CoachViewModel`/`CoachChat` are untouched), and reads a streamed reply
/// aloud sentence by sentence as it arrives. `CoachView` only adds a mic button; everything else
/// lives here.
@MainActor
@Observable
final class VoiceChatController {
    enum State: Equatable {
        case idle
        case listening(partial: String)
        case speaking
        /// On-device recognition isn't supported, or the user declined mic/speech permission.
        case unavailable
    }

    private(set) var state: State = .idle

    private let viewModel: CoachViewModel
    private let recognizer: SpeechRecognizer
    private let reader: CoachSpeechReader
    private var sentenceStream = SentenceStream()
    private var silenceTask: Task<Void, Never>?
    private var sessionActive = false

    private static let silenceDelay = Duration.milliseconds(1200)
    private static let readAloudDefaultsKey = "coachVoice.readRepliesAloud"

    /// "Czytaj odpowiedzi" — persisted so it survives leaving and reopening the Trener tab. A
    /// stored property (not computed) so `@Observable`/`Bindable` can actually track it in the UI.
    var readRepliesAloud: Bool {
        didSet { UserDefaults.standard.set(readRepliesAloud, forKey: Self.readAloudDefaultsKey) }
    }

    /// Whether the mic button should be shown at all — checked once up front, not just on tap, so
    /// a device without the on-device Polish model never shows a button that can't work.
    var isAvailable: Bool { recognizer.isAvailable }

    init(viewModel: CoachViewModel, recognizer: SpeechRecognizer? = nil, reader: CoachSpeechReader? = nil) {
        let reader = reader ?? CoachSpeechReader()
        self.viewModel = viewModel
        self.recognizer = recognizer ?? SpeechRecognizer()
        self.reader = reader
        self.readRepliesAloud = (UserDefaults.standard.object(forKey: Self.readAloudDefaultsKey) as? Bool) ?? true
        reader.setOnIdle { [weak self] in self?.handleReaderIdle() }
        observeViewModel()
    }

    // MARK: mic button

    func tapMic() {
        switch state {
        case .speaking:
            // Barge-in: stop the coach talking and start listening right away.
            reader.stop()
            Task { await startListening() }
        case .listening:
            finishListening()
        case .idle:
            Task { await startListening() }
        case .unavailable:
            break
        }
    }

    private func startListening() async {
        guard recognizer.isAvailable else { state = .unavailable; return }
        guard await recognizer.requestAuthorization() else { state = .unavailable; return }
        activateSessionIfNeeded()
        state = .listening(partial: "")
        do {
            try recognizer.start(
                onPartial: { [weak self] text in self?.handlePartial(text) },
                onError: { [weak self] _ in self?.finishListening() }
            )
        } catch {
            state = .unavailable
        }
    }

    private func handlePartial(_ text: String) {
        guard case .listening = state else { return }
        state = .listening(partial: text)
        resetSilenceTimer(for: text)
    }

    private func resetSilenceTimer(for text: String) {
        silenceTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.silenceDelay)
            guard !Task.isCancelled else { return }
            self?.finishListening()
        }
    }

    /// Ends listening and sends whatever was recognized — manual stop, silence timeout, or a
    /// recognition error all end up here. Sending goes through the normal `CoachViewModel.send`.
    private func finishListening() {
        silenceTask?.cancel()
        silenceTask = nil
        guard case .listening(let partial) = state else { return }
        recognizer.stop()
        state = .idle
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sentenceStream = SentenceStream()
        viewModel.send(text)
    }

    /// Cancels listening without sending — the user wants to redo it (e.g. editing the draft).
    func cancelListening() {
        silenceTask?.cancel()
        silenceTask = nil
        recognizer.stop()
        state = .idle
    }

    // MARK: reading the reply aloud

    private func observeViewModel() {
        withObservationTracking {
            _ = viewModel.streamingText
            _ = viewModel.isResponding
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleViewModelChange()
                self?.observeViewModel()
            }
        }
    }

    private func handleViewModelChange() {
        if viewModel.isResponding {
            guard readRepliesAloud else { return }
            for sentence in sentenceStream.newSentences(in: viewModel.streamingText) { speak(sentence) }
        } else {
            // The reply is finished and the view model has already cleared `streamingText`, so the last sentence (it
            // ends the text with nothing after it, which is why `newSentences` held it back) comes from the finished
            // message. Without this the last sentence of every answer would stay unspoken.
            if readRepliesAloud, let last = viewModel.messages.last, last.role == .coach,
               let rest = sentenceStream.remainder(in: last.text) {
                speak(rest)
            }
            // The next reply starts from its first sentence, whether the question was spoken or typed.
            sentenceStream = SentenceStream()
        }
    }

    private func speak(_ sentence: String) {
        let cleaned = cleanForSpeech(sentence)
        guard !cleaned.isEmpty else { return }
        activateSessionIfNeeded()
        state = .speaking
        reader.speak(cleaned)
    }

    private func handleReaderIdle() {
        guard case .speaking = state else { return }
        state = .idle
    }

    // MARK: audio session

    private func activateSessionIfNeeded() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        sessionActive = true
    }

    /// Call when leaving the coach screen: stops everything and gives the audio session back.
    func endSession() {
        silenceTask?.cancel()
        recognizer.stop()
        reader.stop()
        state = .idle
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }
}
