import Foundation

/// Embedding service that uses a local EmbeddingGemma 2 GGUF via llama.cpp when available.
/// Falls back to the placeholder implementation when the model, mmproj projector (for images),
/// or binary is unavailable.
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
            return normalized(values)
        } catch {
            return try await placeholder.embed(text: text)
        }
    }

    func embed(imageData: Data) async throws -> [Double] {
        guard ModelManager.shared.isEmbeddingModelDownloaded,
              ModelManager.shared.isMultimodalProjectorDownloaded else {
            return try await placeholder.embed(imageData: imageData)
        }

        do {
            let values = try await EmbeddingEngine.shared.generateEmbedding(forImage: imageData)
            print("[Embedding] llama.cpp image values=\(values.count)")
            guard !values.isEmpty else {
                return try await placeholder.embed(imageData: imageData)
            }
            return normalized(values)
        } catch {
            return try await placeholder.embed(imageData: imageData)
        }
    }

    private func normalized(_ values: [Float]) -> [Double] {
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
    }
}
