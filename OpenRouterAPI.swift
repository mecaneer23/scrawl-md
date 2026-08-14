import AppKit

// MARK: - OpenRouter API

struct OpenRouterAPI {
    static let defaultModel = "dots-studio/dots-3-note-preview:free"
    static var model: String {
        UserDefaults.standard.string(forKey: "openRouterModel").flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel
    }

    static func convert(inputs: [GeminiInput], mode: ConversionMode, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }

        var content: [[String: Any]] = []
        for input in inputs {
            if case .image(let image) = input {
                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                    throw APIError.imageConversionFailed
                }
                let b64 = jpegData.base64EncodedString()
                content.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(b64)"]
                ])
            }
        }
        content.append(["type": "text", "text": mode.prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var data: Data = Data()
        var response: URLResponse = URLResponse()
        var retryDelay: UInt64 = 4_000_000_000
        for attempt in 0... {
            (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 429 && attempt < 3 {
                log("OpenRouterAPI: rate limited (429), retrying in \(retryDelay / 1_000_000_000)s")
                try await Task.sleep(nanoseconds: retryDelay)
                retryDelay *= 2
                continue
            }
            break
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw APIError.apiError(message)
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw APIError.invalidResponse
        }

        return text
    }
}
