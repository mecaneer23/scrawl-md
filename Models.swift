import AppKit

// MARK: - Enums

enum LLMProvider: String {
    case gemini, groq, openRouter
}

enum GeminiInput {
    case image(NSImage)
}

extension ConversionMode {
    var prompt: String {
        switch self {
        case .verbatim:
            return """
            Transcribe this handwritten note or document into markdown as verbatim as possible. \
            Preserve the exact words, phrasing, and layout. Only use markdown formatting (headings, \
            bullets, bold) where clear visual structure exists in the original — don't add structure \
            that isn't there. Output only the markdown, no preamble or commentary.
            """
        case .cleaned:
            return """
            Convert this handwritten note or document into clean, well-structured markdown. \
            Fix spelling and grammar errors, improve clarity and flow, organize content logically, \
            and use appropriate markdown formatting. Output only the polished markdown, no preamble \
            or commentary.
            """
        }
    }
}

struct InputGroup {
    let name: String
    let inputs: [GeminiInput]
}

enum ConversionMode {
    case verbatim, cleaned
}

enum APIError: Error, LocalizedError {
    case noAPIKey
    case imageConversionFailed
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key set. Click the ⚙ button to enter your Gemini API key."
        case .imageConversionFailed:
            return "Failed to process the image."
        case .invalidResponse:
            return "Unexpected response from Gemini API."
        case .apiError(let msg):
            return "API error: \(msg)"
        }
    }
}
