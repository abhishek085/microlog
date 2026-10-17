import Foundation
#if os(macOS)
import AppKit
#endif

/// Manages a local `llama-server` process running the EmbeddingGemma 2 GGUF with Metal acceleration (-ngl 99),
/// and talks to it over localhost HTTP. The dedicated `llama-embedding` CLI no longer exists upstream for
/// builds that support the `gemma-embedding2` architecture, so embeddings now go through the server's
/// `/embedding` endpoint instead of a one-shot subprocess per call.
actor EmbeddingEngine {
    static let shared = EmbeddingEngine()

    private let port: UInt16 = 51977
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

    func generateEmbedding(for text: String) async throws -> [Float] {
        guard ModelManager.shared.isEmbeddingModelDownloaded else {
            throw NSError(domain: "EmbeddingEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model GGUF not found locally."])
        }
        try await ensureServerRunning()

        let formattedText = "title: None | text: \(text)"
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/embedding")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["content": formattedText])
        request.timeoutInterval = 30

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode([EmbeddingResponseItem].self, from: data)
        return decoded.first?.embedding.first ?? []
    }

    private struct EmbeddingResponseItem: Decodable {
        let index: Int
        let embedding: [[Float]]
    }

    private func ensureServerRunning() async throws {
        if isReady { return }

        guard let binaryPath = serverBinaryPath else {
            throw NSError(domain: "EmbeddingEngine", code: 405, userInfo: [NSLocalizedDescriptionKey: "llama-server binary not found locally."])
        }

        if serverProcess == nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = [
                "-m", ModelManager.shared.embeddingModelFileURL.path,
                "--embeddings",
                "--pooling", "mean",
                "-ngl", "99",
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

        // Poll until the server accepts connections (model load can take a few seconds).
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if await pingServer() {
                isReady = true
                return
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        throw NSError(domain: "EmbeddingEngine", code: 408, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for llama-server to become ready."])
    }

    private func pingServer() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/embedding") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["content": "ping"])
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
