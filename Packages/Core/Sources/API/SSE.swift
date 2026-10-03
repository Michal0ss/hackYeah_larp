import Foundation

/// Turns the lines of a Server-Sent Events body into chat events. The server sends `event:` then one `data:` line.
struct ChatEventParser {
    private var pendingName: String?
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder) {
        self.decoder = decoder
    }

    /// Feed one line; returns an event when the line completes one.
    mutating func feed(_ line: String) throws -> ChatEvent? {
        if line.hasPrefix("event:") {
            pendingName = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard line.hasPrefix("data:"), let name = pendingName else { return nil }
        pendingName = nil
        let data = Data(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces).utf8)
        switch name {
        case "delta":
            struct Delta: Decodable { var text: String }
            return .delta(try decoder.decode(Delta.self, from: data).text)
        case "tool_use":
            return .toolUse(try decoder.decode(ToolCall.self, from: data))
        case "done":
            struct Done: Decodable { var stopReason: String?; var usage: ChatUsage }
            let done = try decoder.decode(Done.self, from: data)
            return .done(stopReason: done.stopReason, usage: done.usage)
        case "error":
            return .error(try decoder.decode(ServerError.self, from: data))
        default:
            return nil  // unknown events are ignored so the server can add new ones
        }
    }
}
