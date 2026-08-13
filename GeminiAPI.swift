import AppKit

// MARK: - Gemini API

struct GeminiAPI {
    static func convert(inputs: [GeminiInput], mode: ConversionMode, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }

        var imageParts: [[String: Any]] = []
        for input in inputs {
            if case .image(let image) = input {
                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                    throw APIError.imageConversionFailed
                }
                imageParts.append(["inline_data": ["mime_type": "image/jpeg", "data": jpegData.base64EncodedString()]])
            }
        }

        let prompt: String
        switch mode {
        case .verbatim:
            prompt = """
            Transcribe this handwritten note or document into markdown as verbatim as possible. \
            Preserve the exact words, phrasing, and layout. Only use markdown formatting (headings, \
            bullets, bold) where clear visual structure exists in the original — don't add structure \
            that isn't there. Output only the markdown, no preamble or commentary.
            """
        case .cleaned:
            prompt = """
            Convert this handwritten note or document into clean, well-structured markdown. \
            Fix spelling and grammar errors, improve clarity and flow, organize content logically, \
            and use appropriate markdown formatting. Output only the polished markdown, no preamble \
            or commentary.
            """
        }

        let body: [String: Any] = [
            "contents": [[
                "parts": imageParts + [["text": prompt]]
            ]],
            "generationConfig": ["maxOutputTokens": 65536]
        ]

        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlStr)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var data: Data = Data()
        var response: URLResponse = URLResponse()
        var retryDelay: UInt64 = 4_000_000_000 // 4s
        for attempt in 0... {
            (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 429 && attempt < 3 {
                log("GeminiAPI: rate limited (429), retrying in \(retryDelay / 1_000_000_000)s")
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

        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw APIError.invalidResponse
        }
        return text
    }
}
