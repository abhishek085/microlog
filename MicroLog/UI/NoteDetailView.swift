import SwiftUI

struct NoteDetailView: View {
    let note: NoteUI
    @Bindable var state: ReadingNotesUIState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(note.title).font(.system(size: Theme.detailTitleSize, weight: .semibold)).lineLimit(3)
                    if !note.gist.isEmpty {
                        Text(note.gist).font(.system(size: Theme.bodySize)).foregroundStyle(.secondary)
                    }
                    metaRow
                    section("SUMMARY") {
                        if note.isSummarizing {
                            Label("Summarizing...", systemImage: "hourglass").font(.system(size: Theme.bodySize)).foregroundStyle(.secondary)
                        } else {
                            Text(note.summary).font(.system(size: Theme.bodySize)).lineSpacing(2)
                        }
                    }
                    section("KEY POINTS") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(note.keyPoints, id: \.self) { kp in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle().fill(Color.accentColor).frame(width: 4, height: 4).padding(.top, 6)
                                    Text(kp).font(.system(size: Theme.bodySize))
                                }
                            }
                        }
                    }
                    whyBlock
                    tagRow
                    actionBar
                }
                .padding(Theme.detailPadding)
            }
        }
        .frame(width: Theme.containerWidth, height: Theme.containerHeight)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(Theme.backgroundOpacity)
                Rectangle().fill(.ultraThinMaterial)
            }
        )
        .onExitCommand { state.selectedNoteID = nil }
    }

    private var topBar: some View {
        HStack {
            Button { state.selectedNoteID = nil } label: { Label("Today", systemImage: "chevron.left").foregroundStyle(Color.accentColor) }
                .buttonStyle(.plain)
            Spacer()
            Button { copySummary() } label: { Image(systemName: "doc.on.doc").font(.system(size: Theme.iconMedium, weight: .semibold)) }
                .buttonStyle(.plain).frame(width: Theme.minHit, height: Theme.minHit)
            Button { state.onOpenURL(note) } label: { Image(systemName: "arrow.up.right.square").font(.system(size: Theme.iconMedium, weight: .semibold)) }
                .buttonStyle(.plain).frame(width: Theme.minHit, height: Theme.minHit)
        }
        .padding(.horizontal, Theme.outerHorizontalPadding)
        .padding(.vertical, 6)
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            SourceChip(source: note.source)
            Text(note.author ?? "").font(.system(size: Theme.captionSize)).foregroundStyle(.secondary)
            Text(note.domain).font(.system(size: Theme.captionSize)).foregroundStyle(.secondary)
            Text(timeStr(note.capturedAt)).font(.system(size: Theme.monoSize, design: .monospaced)).foregroundStyle(.secondary)
            if note.seenCount > 1 { Text("Seen \(note.seenCount)x today").font(.system(size: Theme.captionSizeSmall, design: .monospaced)).foregroundStyle(.secondary) }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: Theme.labelSize, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            content()
        }
    }

    private var whyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WHY THIS MATTERS").font(.system(size: Theme.labelSize, weight: .semibold)).tracking(0.6).foregroundStyle(Color.accentColor)
            Text(note.whyItMatters).font(.system(size: Theme.bodySize))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
    }

    private var tagRow: some View {
        HStack(spacing: 4) {
            ForEach(note.tags, id: \.self) { tag in
                Text("#\(tag)").font(.system(size: Theme.captionSizeSmall)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Button { regenerateNote() } label: { Text("Regenerate summary") }
                .buttonStyle(.bordered).controlSize(.small)
            Button(role: .destructive) { deleteNote(); state.onDelete(note) } label: { Text("Delete") }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func copySummary() {
        let text = note.summary + "\n" + note.keyPoints.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func regenerateNote() {
        guard let idx = state.notes.firstIndex(where: { $0.id == note.id }) else { return }
        state.notes[idx].isSummarizing = true
        state.onRegenerate(note)   // the capture service re-summarizes and pushes the update back
    }

    private func deleteNote() {
        state.notes.removeAll { $0.id == note.id }
        state.selectedNoteID = nil
    }

    private func timeStr(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d) }
}

#Preview {
    let s = ReadingNotesUIState()
    let note = NoteUI.samples(count: 1)[0]
    s.notes = [note]
    s.selectedNoteID = note.id
    return NoteDetailView(note: note, state: s)
}
