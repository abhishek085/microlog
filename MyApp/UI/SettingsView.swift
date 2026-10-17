import SwiftUI

struct SettingsView: View {
    @Binding var isPaused: Bool
    @AppStorage("minReadTime") private var minReadTime: Double = 20
    @AppStorage("askBeforeSaving") private var askBeforeSaving = false
    @Environment(\.dismiss) private var dismiss

    @State private var allowedApps = "Safari, Chrome"
    @State private var allowedDomains = "x.com, linkedin.com, news sites, blogs"
    @State private var deniedDomains = "banking, email, password managers, private windows"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.system(size: Theme.titleSize, weight: .semibold))
            Toggle("Paused", isOn: $isPaused)
            Toggle("Ask before saving", isOn: $askBeforeSaving)
            Stepper("Minimum read time: \(Int(minReadTime))s", value: $minReadTime, in: 5...120, step: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow apps (comma separated)").font(.system(size: Theme.captionSize)).foregroundStyle(.secondary)
                TextField("e.g. Safari, Chrome", text: $allowedApps).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow domains (comma separated)").font(.system(size: Theme.captionSize)).foregroundStyle(.secondary)
                TextField("e.g. x.com, linkedin.com", text: $allowedDomains).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Deny domains (comma separated)").font(.system(size: Theme.captionSize)).foregroundStyle(.secondary)
                TextField("e.g. banking, email", text: $deniedDomains).textFieldStyle(.roundedBorder)
            }
            ModelDownloadRow(
                label: "llama.cpp runtime",
                sizeLabel: "~12 MB",
                isDownloaded: ModelManager.shared.isRuntimeDownloaded,
                startDownload: { progressHandler, completion in
                    ModelManager.shared.downloadRuntime(progressHandler: progressHandler, completion: completion)
                }
            )
            ModelDownloadRow(
                label: "EmbeddingGemma 2 model",
                sizeLabel: "~170 MB",
                isDownloaded: ModelManager.shared.isEmbeddingModelDownloaded,
                startDownload: { progressHandler, completion in
                    ModelManager.shared.downloadEmbeddingModel(progressHandler: progressHandler, completion: completion)
                }
            )
            ModelDownloadRow(
                label: "Summarizer model (Qwen3.5-0.8B)",
                sizeLabel: "~530 MB",
                isDownloaded: ModelManager.shared.isSummarizerModelDownloaded,
                startDownload: { progressHandler, completion in
                    ModelManager.shared.downloadSummarizerModel(progressHandler: progressHandler, completion: completion)
                }
            )
            Button("Clear today") { }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(.accentColor)
        }
        .padding()
        .frame(width: 300)
    }
}

private struct ModelDownloadRow: View {
    let label: String
    let sizeLabel: String
    let startDownload: (@escaping @Sendable (Double) -> Void, @escaping @Sendable (Result<URL, Error>) -> Void) -> Void

    @State private var isDownloaded: Bool
    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var error: String?

    init(label: String, sizeLabel: String, isDownloaded: Bool, startDownload: @escaping (@escaping @Sendable (Double) -> Void, @escaping @Sendable (Result<URL, Error>) -> Void) -> Void) {
        self.label = label
        self.sizeLabel = sizeLabel
        self.startDownload = startDownload
        _isDownloaded = State(initialValue: isDownloaded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: Theme.captionSize)).foregroundStyle(.secondary)
                Spacer()
                if isDownloaded {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .font(.system(size: Theme.captionSizeSmall))
                        .foregroundStyle(.green)
                }
            }
            if isDownloading {
                ProgressView(value: progress)
                Text("Downloading… \(Int(progress * 100))%")
                    .font(.system(size: Theme.captionSizeSmall))
                    .foregroundStyle(.secondary)
            } else if !isDownloaded {
                Button("Download model (\(sizeLabel))") { start() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            if let error {
                Text(error)
                    .font(.system(size: Theme.captionSizeSmall))
                    .foregroundStyle(.red)
            }
        }
    }

    private func start() {
        isDownloading = true
        error = nil
        startDownload(
            { p in Task { @MainActor in progress = p } },
            { result in
                Task { @MainActor in
                    isDownloading = false
                    switch result {
                    case .success:
                        isDownloaded = true
                    case .failure(let e):
                        error = e.localizedDescription
                    }
                }
            }
        )
    }
}

#Preview {
    SettingsView(isPaused: .constant(false))
}
