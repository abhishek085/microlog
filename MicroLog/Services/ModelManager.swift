import Foundation

/// Manages on-disk storage and downloading of local GGUF models and the llama.cpp runtime
/// (embedding + summarizer models, and the `llama-server` binary + dylibs it needs).
///
/// App Sandbox confines this process to its own container, so none of this can be seeded by
/// placing files on disk from outside the app (not even via `~`, which resolves to the
/// container itself) — every asset has to be fetched by the app's own URLSession.
final class ModelManager: NSObject, @unchecked Sendable {
    static let shared = ModelManager()

    private override init() {}

    private var progressHandler: (@Sendable (Double) -> Void)?
    private var completionHandler: (@Sendable (Result<URL, Error>) -> Void)?
    private var activeSession: URLSession?
    private var activeDestination: URL?
    private var postProcess: ((URL) throws -> Void)?

    /// ~/Library/Application Support/AmbientTrace/models/
    var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("AmbientTrace/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// ~/Library/Application Support/AmbientTrace/bin/
    var binDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("AmbientTrace/bin", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    var embeddingModelFileURL: URL {
        modelDirectory.appendingPathComponent("embeddinggemma-2-UD-Q4_K_XL.gguf")
    }

    var isEmbeddingModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: embeddingModelFileURL.path)
    }

    /// The mmproj vision/audio projector that, alongside the base GGUF, lets EmbeddingGemma 2
    /// embed images (and audio/video) into the same 768-d space as text.
    var mmprojModelFileURL: URL {
        modelDirectory.appendingPathComponent("mmproj-embeddinggemma-2-F16.gguf")
    }

    var isMultimodalProjectorDownloaded: Bool {
        FileManager.default.fileExists(atPath: mmprojModelFileURL.path)
    }

    var summarizerModelFileURL: URL {
        modelDirectory.appendingPathComponent("Qwen3.5-0.8B-Q4_K_M.gguf")
    }

    var isSummarizerModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: summarizerModelFileURL.path)
    }

    var llamaServerBinaryURL: URL {
        binDirectory.appendingPathComponent("llama-server")
    }

    var isRuntimeDownloaded: Bool {
        FileManager.default.isExecutableFile(atPath: llamaServerBinaryURL.path)
    }

    func downloadEmbeddingModel(
        progressHandler: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        download(
            from: "https://huggingface.co/unsloth/embeddinggemma-2-GGUF/resolve/main/embeddinggemma-2-UD-Q4_K_XL.gguf",
            to: embeddingModelFileURL,
            progressHandler: progressHandler,
            completion: completion
        )
    }

    func downloadMultimodalProjector(
        progressHandler: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        download(
            from: "https://huggingface.co/unsloth/embeddinggemma-2-GGUF/resolve/main/mmproj-F16.gguf",
            to: mmprojModelFileURL,
            progressHandler: progressHandler,
            completion: completion
        )
    }

    func downloadSummarizerModel(
        progressHandler: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        download(
            from: "https://huggingface.co/lmstudio-community/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf",
            to: summarizerModelFileURL,
            progressHandler: progressHandler,
            completion: completion
        )
    }

    /// Downloads the official llama.cpp macOS arm64 release (contains `llama-server` and the
    /// dylibs it links against) and extracts it into `binDirectory`.
    func downloadRuntime(
        progressHandler: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        let archiveURL = binDirectory.appendingPathComponent("llama-runtime.tar.gz")
        download(
            from: "https://github.com/ggml-org/llama.cpp/releases/download/b11632/llama-b11632-bin-macos-arm64.tar.gz",
            to: archiveURL,
            progressHandler: progressHandler,
            completion: completion,
            postProcess: { [binDirectory] downloadedArchive in
                try ModelManager.extractRuntime(archiveURL: downloadedArchive, into: binDirectory)
            }
        )
    }

    private static func extractRuntime(archiveURL: URL, into binDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", binDirectory.path]
        try process.run()
        process.waitUntilExit()

        // The tarball extracts into a subfolder (e.g. "llama-b11632/"); hoist its contents up
        // into binDirectory directly and clean up.
        let entries = try FileManager.default.contentsOfDirectory(at: binDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  entry.lastPathComponent.hasPrefix("llama-b") else { continue }
            let contents = try FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
            for item in contents {
                let dest = binDirectory.appendingPathComponent(item.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: item, to: dest)
            }
            try FileManager.default.removeItem(at: entry)
        }
        try? FileManager.default.removeItem(at: archiveURL)
    }

    /// Downloads whatever the app needs to run (runtime, embedding model, summarizer, and the vision projector that lets screenshots be embedded) that isn't on
    /// disk yet, one at a time (the downloader holds a single in-flight handler). The optional
    /// `status` receives a short progress
    /// string, or nil when finished.
    func ensureCoreAssets(status: @escaping @Sendable (String?) -> Void) async {
        typealias Starter = (@escaping @Sendable (Double) -> Void, @escaping @Sendable (Result<URL, Error>) -> Void) -> Void
        let steps: [(label: String, present: Bool, start: Starter)] = [
            ("llama.cpp runtime", isRuntimeDownloaded, { self.downloadRuntime(progressHandler: $0, completion: $1) }),
            ("embedding model", isEmbeddingModelDownloaded, { self.downloadEmbeddingModel(progressHandler: $0, completion: $1) }),
            ("summarizer model", isSummarizerModelDownloaded, { self.downloadSummarizerModel(progressHandler: $0, completion: $1) }),
            ("vision projector", isMultimodalProjectorDownloaded, { self.downloadMultimodalProjector(progressHandler: $0, completion: $1) })
        ]
        for step in steps where !step.present {
            status("Downloading \(step.label)…")
            let ok: Bool = await withCheckedContinuation { continuation in
                step.start({ p in status("Downloading \(step.label)… \(Int(p * 100))%") }, { result in
                    if case .failure(let error) = result { print("[ModelManager] \(step.label) failed: \(error.localizedDescription)") }
                    if case .success = result { continuation.resume(returning: true) } else { continuation.resume(returning: false) }
                })
            }
            if !ok { status("Couldn't download \(step.label) — retry from Settings"); return }
        }
        status(nil)
    }

    private func download(
        from urlString: String,
        to destination: URL,
        progressHandler: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void,
        postProcess: ((URL) throws -> Void)? = nil
    ) {
        guard let remoteURL = URL(string: urlString) else {
            completion(.failure(NSError(domain: "ModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid model URL."])))
            return
        }

        self.progressHandler = progressHandler
        self.completionHandler = completion
        self.activeDestination = destination
        self.postProcess = postProcess

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        activeSession = session
        progressHandler(0)
        session.downloadTask(with: remoteURL).resume()
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destination = activeDestination else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            try postProcess?(destination)
            completionHandler?(.success(destination))
        } catch {
            completionHandler?(.failure(error))
        }
        activeSession = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completionHandler?(.failure(error))
            activeSession = nil
        }
    }
}
