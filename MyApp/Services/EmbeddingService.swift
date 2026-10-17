import Foundation

/// Abstraction over the on-device EmbeddingGemma 2 engine (text + image, via its vision encoder).
protocol EmbeddingService: Sendable {
    func embed(text: String) async throws -> [Double]
    func embed(imageData: Data) async throws -> [Double]
}

/// Placeholder implementation producing a deterministic 768-d L2-normalized vector.
/// Replace with real Core ML / ONNX Runtime inference when the model bundle ships.
struct PlaceholderEmbeddingService: EmbeddingService {
    let dimension: Int = 768

    func embed(text: String) async throws -> [Double] {
        hashVector(text.unicodeScalars.map { $0.value })
    }

    func embed(imageData: Data) async throws -> [Double] {
        hashVector(imageData.map { UInt32($0) })
    }

    private func hashVector(_ scalars: [UInt32]) -> [Double] {
        var vector = [Double](repeating: 0, count: dimension)
        for (index, scalar) in scalars.enumerated() {
            vector[index % dimension] += Double(scalar) / 1000.0
        }
        let norm = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
        if norm > 0 {
            vector = vector.map { $0 / norm }
        }
        return vector
    }
}
