import Foundation

/// Abstraction over the on-device EmbeddingGemma 2 engine (Core ML / ONNX).
protocol EmbeddingService: Sendable {
    func embed(text: String) async throws -> [Double]
}

/// Placeholder implementation producing a deterministic 768-d L2-normalized vector.
/// Replace with real Core ML / ONNX Runtime inference when the model bundle ships.
struct PlaceholderEmbeddingService: EmbeddingService {
    let dimension: Int = 768

    func embed(text: String) async throws -> [Double] {
        var vector = [Double](repeating: 0, count: dimension)
        for (index, scalar) in text.unicodeScalars.enumerated() {
            vector[index % dimension] += Double(scalar.value) / 1000.0
        }
        let norm = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
        if norm > 0 {
            vector = vector.map { $0 / norm }
        }
        return vector
    }
}
