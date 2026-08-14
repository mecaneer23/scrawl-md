import AppKit

// MARK: - Groq API

struct GroqAPI {
    static let defaultModel = "qwen/qwen3.6-27b"
    static var model: String {
        UserDefaults.standard.string(forKey: "groqModel").flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel
    }

    private static let maxImagesPerRequest = 3

    static func convert(inputs: [GeminiInput], mode: ConversionMode, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }

        let chunks = stride(from: 0, to: inputs.count, by: maxImagesPerRequest).map {
            Array(inputs[$0..<min($0 + maxImagesPerRequest, inputs.count)])
        }

        var results: [String] = []
        for chunk in chunks {
            let text = try await convertChunk(chunk, mode: mode, apiKey: apiKey)
            results.append(text)
        }
        return results.joined(separator: "\n\n")
    }

    private static func resized(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        guard scale < 1.0 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: newSize)
        result.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: newSize))
        result.unlockFocus()
        return result
    }

    private static func convertChunk(_ inputs: [GeminiInput], mode: ConversionMode, apiKey: String) async throws -> String {
        var content: [[String: Any]] = []
        for input in inputs {
            if case .image(let rawImage) = input {
                let image = resized(rawImage, maxDimension: 800)
                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else {
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
            "messages": [["role": "user", "content": content]],
            "max_tokens": 16384
        ]

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
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
                log("GroqAPI: rate limited (429), retrying in \(retryDelay / 1_000_000_000)s")
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
