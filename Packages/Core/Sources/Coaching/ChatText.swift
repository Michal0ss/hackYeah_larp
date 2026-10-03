import Foundation

/// How the coach's text is shown in a chat bubble.
///
/// The instructions ask the model for plain text, but it still sometimes writes `**bold**`, a list with dashes or a
/// heading. Showing the asterisks looks broken, so the simple markup is rendered (bold, italic, bullets) and the rest
/// stays as written. The text comes from a model, so it is treated as untrusted: links are never tappable (only their
/// label is shown), nothing but inline formatting is interpreted, and a broken marker just stays as typed.
public enum ChatText {
    /// The text of an answer, formatted. With `streaming` an unfinished `**` at the end is hidden until its pair
    /// arrives, so the bubble does not flash asterisks while the answer is being written.
    public static func attributed(_ text: String, streaming: Bool = false) -> AttributedString {
        let prepared = prepare(streaming ? withoutDanglingBold(text) : text)
        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: false,
                                                              interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        guard var result = try? AttributedString(markdown: prepared, options: options) else {
            return AttributedString(prepared)
        }
        // A link in a model's answer must not be tappable: keep the words, drop the address.
        for run in result.runs where run.link != nil {
            result[run.range].link = nil
        }
        return result
    }

    /// The same text without any markup, for VoiceOver.
    public static func plain(_ text: String) -> String {
        String(attributed(text).characters)
    }

    // MARK: preparation

    /// Dashes, stars and bullets at the start of a line become one bullet (inline parsing has no lists, and a `* ` at
    /// the start of a line would otherwise open italics); a `#` heading becomes a bold line.
    static func prepare(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            for marker in ["- ", "* ", "• "] where trimmed.hasPrefix(marker) {
                return "• " + trimmed.dropFirst(marker.count)
            }
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop(while: { $0 == "#" }).drop(while: { $0 == " " })
                if !title.isEmpty, trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
                    return "**" + title.replacingOccurrences(of: "**", with: "") + "**"
                }
            }
            return String(line)
        }.joined(separator: "\n")
    }

    /// An odd number of `**` means the last one is still waiting for its pair: leave it out for now.
    static func withoutDanglingBold(_ text: String) -> String {
        let marker = "**"
        guard text.components(separatedBy: marker).count % 2 == 0,
              let last = text.range(of: marker, options: .backwards) else { return text }
        var shown = text
        shown.removeSubrange(last)
        return shown
    }
}
