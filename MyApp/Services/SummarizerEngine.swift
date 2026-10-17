import Foundation
#if os(macOS)
import AppKit
#endif

/// Manages a local `llama-server` process running a small instruct model (Qwen3.5-0.8B) for
/// on-device summarization, and talks to it over localhost HTTP using the OpenAI-compatible
/// chat completions endpoint with a JSON schema response format for reliable structured output.
actor SummarizerEngine {
    static let shared = SummarizerEngine()

    private let port: UInt16 = 51978
    private var serverProcess: Process?
    private var isReady = false

    private init() {}

    private var serverBinaryPath: String? {
        let candidatePaths = [
            Bundle.main.path(forResource: "llama-server", ofType: nil),
            ModelManager.shared.llamaServerBinaryURL.path
        ].compactMap { $0 }
        return candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "summary": ["type": "string"],
            "keyPoints": ["type": "array", "items": ["type": "string"], "minItems": 2, "maxItems": 4],
            "whyItMatters": ["type": "string"],
            "tags": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 5]
        ],
        "required": ["title", "summary", "keyPoints", "whyItMatters", "tags"],
        "additionalProperties": false
    ]

    func generateSummary(systemPrompt: String, userPrompt: String) async throws -> Data {
        guard ModelManager.shared.isSummarizerModelDownloaded else {
            throw NSError(domain: "SummarizerEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "Summarizer GGUF not found locally."])
        }
        try await ensureServerRunning()

        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            // Qwen3.5 defaults to an internal "thinking" pass that can loop and burn the whole
            // context without ever emitting the final answer; this is a quick structured-extraction
            // task, not multi-step reasoning, so thinking mode is disabled.
            "chat_template_kwargs": ["enable_thinking": false],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "summary", "strict": true, "schema": Self.jsonSchema]
            ],
            "temperature": 0.3
        ]

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else {
            throw NSError(domain: "SummarizerEngine", code: 422, userInfo: [NSLocalizedDescriptionKey: "No content returned by summarizer."])
        }
        return contentData
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    private func ensureServerRunning() async throws {
        if isReady { return }

        guard let binaryPath = serverBinaryPath else {
            throw NSError(domain: "SummarizerEngine", code: 405, userInfo: [NSLocalizedDescriptionKey: "llama-server binary not found locally."])
        }

        if serverProcess == nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = [
                "-m", ModelManager.shared.summarizerModelFileURL.path,
                "--jinja",
                "-ngl", "99",
                "-c", "4096",
                "--port", String(port),
                "--host", "127.0.0.1"
            ]
            process.environment = ["DYLD_LIBRARY_PATH": (binaryPath as NSString).deletingLastPathComponent]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            serverProcess = process

            #if os(macOS)
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [process] _ in
                if process.isRunning { process.terminate() }
            }
            #endif
        }

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if await pingServer() {
                isReady = true
                return
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        throw NSError(domain: "SummarizerEngine", code: 408, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for llama-server to become ready."])
    }

    private func pingServer() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
