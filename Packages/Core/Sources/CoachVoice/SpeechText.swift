import Foundation

/// Strips the light markdown the coach prompt still allows (`**bold**`, a `-`/`*` bullet list,
/// `[label](url)` links, stray `#` headings) so a spoken reply doesn't say the punctuation aloud.
/// `ChatMessage.sources` is a separate field from `text` already, so there is nothing to strip for
/// sources here — they're never spoken, only shown under the bubble.
public func cleanForSpeech(_ text: String) -> String {
    var withoutLinks = stripMarkdownLinks(text)
    withoutLinks = withoutLinks.replacingOccurrences(of: "**", with: "")
    withoutLinks = withoutLinks.replacingOccurrences(of: "__", with: "")

    let lines = withoutLinks.components(separatedBy: .newlines).compactMap { line -> String? in
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        while trimmed.hasPrefix("#") { trimmed.removeFirst() }
        trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { trimmed = String(trimmed.dropFirst(2)) }
        return trimmed.isEmpty ? nil : trimmed
    }
    return lines.joined(separator: ". ")
}

/// Replaces `[label](url)` with just `label`. Hand-rolled instead of a regex: the pattern is simple
/// and this avoids pulling in NSRegularExpression edge cases for something this small.
private func stripMarkdownLinks(_ text: String) -> String {
    var result = ""
    var index = text.startIndex
    while index < text.endIndex {
        guard text[index] == "[", let closeBracket = text[index...].firstIndex(of: "]") else {
            result.append(text[index])
            index = text.index(after: index)
            continue
        }
        let label = text[text.index(after: index)..<closeBracket]
        let afterBracket = text.index(after: closeBracket)
        guard afterBracket < text.endIndex, text[afterBracket] == "(",
            let closeParen = text[afterBracket...].firstIndex(of: ")")
        else {
            result.append(text[index])
            index = text.index(after: index)
            continue
        }
        result.append(contentsOf: label)
        index = text.index(after: closeParen)
    }
    return result
}
