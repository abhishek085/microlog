import Foundation

/// Embedding service that uses a local EmbeddingGemma GGUF via llama.cpp when available.
/// Falls back to the placeholder implementation when the model or binary is unavailable.
struct LlamaCppEmbeddingService: EmbeddingService {
    private let placeholder = PlaceholderEmbeddingService()
    private let dimension: Int = 768

    func embed(text: String) async throws -> [Double] {
        guard ModelManager.shared.isEmbeddingModelDownloaded else {
            return try await placeholder.embed(text: text)
        }

        do {
            let values = try await EmbeddingEngine.shared.generateEmbedding(for: text)
            print("[Embedding] llama.cpp values=\(values.count)")
            guard !values.isEmpty else {
                return try await placeholder.embed(text: text)
            }

            var vector = values.map(Double.init)
            if vector.count < dimension {
                vector.append(contentsOf: Array(repeating: 0, count: dimension - vector.count))
            } else if vector.count > dimension {
                vector = Array(vector.prefix(dimension))
            }

            let norm = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
            if norm > 0 {
                vector = vector.map { $0 / norm }
            }
            return vector
        } catch {
            return try await placeholder.embed(text: text)
        }
    }
}
