import Foundation

/// Picks out newly-completed sentences from text that grows over time (`CoachViewModel.streamingText`
/// as a reply streams in), so the coach's voice can read each sentence as soon as it lands instead of
/// waiting for the whole answer. Stateful but pure: no AVFoundation, no UI, so it's unit-testable.
public struct SentenceStream {
    private var emittedCount = 0

    public init() {}

    /// Call with the full text accumulated so far. Returns sentences that just became complete and
    /// weren't returned by an earlier call. A sentence counts as complete only when its terminator
    /// (`.`, `!`, `?`) is followed by whitespace that has already arrived — otherwise "3." could be
    /// read aloud a beat before the rest of "3.5 kg" shows up.
    public mutating func newSentences(in fullText: String) -> [String] {
        let sentences = Self.sentences(in: fullText, includeTrailingPartial: false)
        guard sentences.count > emittedCount else { return [] }
        defer { emittedCount = sentences.count }
        return Array(sentences[emittedCount...])
    }

    /// Call once the stream has finished, to collect any trailing partial sentence (no terminator
    /// reached) that `newSentences` was withholding.
    public mutating func remainder(in fullText: String) -> String? {
        let sentences = Self.sentences(in: fullText, includeTrailingPartial: true)
        guard sentences.count > emittedCount else { return nil }
        defer { emittedCount = sentences.count }
        let fresh = sentences[emittedCount...].joined(separator: " ")
        return fresh.isEmpty ? nil : fresh
    }

    static func sentences(in text: String, includeTrailingPartial: Bool) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            guard ".!?".contains(character) else { continue }
            let hasArrivedWhitespaceAfter = index + 1 < characters.count && characters[index + 1].isWhitespace
            guard hasArrivedWhitespaceAfter else { continue }
            let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            current = ""
        }
        if includeTrailingPartial {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(trimmed) }
        }
        return result
    }
}
