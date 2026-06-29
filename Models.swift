import Foundation

// MARK: - Enums

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
