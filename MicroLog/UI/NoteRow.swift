import SwiftUI

struct TodayRow: View {
    let count: Int
    var body: some View {
        HStack {
            Text("Today").font(.system(size: Theme.bodySize, weight: .semibold))
            Text(formattedDate).font(.system(size: Theme.captionSize)).foregroundStyle(.secondary)
            Spacer()
            Text("\(count) notes")
                .font(.system(size: Theme.monoSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 2)
    }
    private var formattedDate: String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: Date())
    }
}

struct SourceChip: View {
    let source: Source
    var body: some View {
        let (fill, fg) = colors
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fill, in: Capsule())
    }
    private var label: String {
        switch source {
        case .x: return "X"
        case .linkedin: return "in"
        case .reddit: return "Reddit"
        case .hackernews: return "HN"
        case .github: return "Git"
        case .youtube: return "YT"
        case .article: return "Web"
        }
    }
    private var colors: (Color, Color) {
        switch source {
        case .x: return (.primary.opacity(0.12), .primary)
        case .linkedin: return (.blue.opacity(0.14), .blue)
        case .reddit: return (.orange.opacity(0.16), .orange)
        case .hackernews: return (.orange.opacity(0.16), .orange)
        case .github: return (.purple.opacity(0.14), .purple)
        case .youtube: return (.red.opacity(0.14), .red)
        case .article: return (.green.opacity(0.14), .green)
        }
    }
}

struct NoteRow: View {
    let note: NoteUI
    @Bindable var state: ReadingNotesUIState
    @State private var hovering = false
    @State private var highlight = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.selectedNoteID = note.id
            }
        } label: {
            HStack(spacing: 8) {
                Text(timeString(note.capturedAt))
                    .font(.system(size: Theme.monoSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.timestampWidth, alignment: .leading)

                // Line 1: where it came from. Line 2: what it is, in one glance.
                VStack(alignment: .leading, spacing: 2) {
                    Text(truncated(note.title))
                        .font(.system(size: Theme.bodySize, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if note.isSummarizing && note.gist.isEmpty {
                        ShimmerLine()
                    } else if !note.gist.isEmpty {
                        Text(note.gist)
                            .font(.system(size: Theme.captionSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)            // a gist is only useful if you can read it
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SourceChip(source: note.source)

                if note.seenCount > 1 {
                    Text("Seen \(note.seenCount)x")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: Theme.rowHeight)
            .padding(.vertical, 6)
            .padding(.horizontal, Theme.cardHorizontalPadding - 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(.primary.opacity(hovering ? 0.16 : 0.08), lineWidth: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Color.accentColor.opacity(highlight ? 0.6 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hovering = h }
        }
        .task {
            // brief accent highlight on new insertion
            highlight = true
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.easeOut(duration: 0.3)) { highlight = false }
        }
    }

    private func truncated(_ s: String) -> String {
        s.count > 60 ? String(s.prefix(60)) + "…" : s
    }
    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}

struct ShimmerLine: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(.secondary.opacity(0.2))
            .frame(height: 10)
            .frame(maxWidth: .infinity)
            .overlay(
                LinearGradient(colors: [.clear, .white.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: phase)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 60 }
            }
    }
}

#Preview {
    NoteRow(note: NoteUI.samples(count: 1)[0], state: ReadingNotesUIState())
}
