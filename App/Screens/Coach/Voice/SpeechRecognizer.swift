import AVFoundation
import Speech

/// On-device speech recognition only (`requiresOnDeviceRecognition = true`): the recorded voice
/// never leaves the phone, only the recognized text goes anywhere further (through the normal
/// `CoachViewModel.send` path, same as typing). `isAvailable` is false when on-device recognition
/// isn't supported (e.g. the Polish on-device model isn't installed) — the mic button hides itself
/// rather than silently falling back to server-side recognition.
@MainActor
final class SpeechRecognizer {
    enum RecognizerError: Error { case notAuthorized, notAvailable }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pl-PL"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isAvailable: Bool {
        recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true
    }

    /// Asks for microphone + speech recognition permission. Call only right before the first
    /// recording (on mic tap), never at launch, so declining doesn't affect the rest of the app.
    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Starts listening. `onPartial` fires repeatedly with the best transcript so far (including the
    /// final one, right before recognition naturally ends); `onError` fires on a recognition failure.
    /// Caller owns the audio session (`.playAndRecord`) — this only taps the input node.
    func start(onPartial: @escaping (String) -> Void, onError: @escaping (Error) -> Void) throws {
        stop()
        guard let recognizer, isAvailable else { throw RecognizerError.notAvailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                if let result { onPartial(result.bestTranscription.formattedString) }
                if let error { onError(error) }
            }
        }
    }

    func stop() {
        guard request != nil || task != nil else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }
}
