import SwiftUI

struct AmbientPill: View {
    let message: AmbientPillState
    var onView: (UUID) -> Void = { _ in }
    var onSaveAsNew: () -> Void = { }
    var onDismiss: () -> Void = { }
    @State private var hoveringPrimary = false
    @State private var hoveringSecondary = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 22, height: 22)
                .overlay(Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            primaryButton
            secondaryButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var icon: String {
        switch message.kind {
        case .noted: return "checkmark"
        case .duplicate: return "arrow.triangle.2.circlepath"
        case .askToSave: return "doc.badge.plus"
        }
    }
    private var text: String {
        switch message.kind {
        case .noted: return "Noted: \(message.title)"
        case .duplicate: return "Already noted. Updated '\(message.title)'"
        case .askToSave: return "Save note: \(message.title)?"
        }
    }
    private var primaryButton: some View {
        let label = message.kind == .askToSave ? "Accept" : "View"
        return Button(label) { onView(message.noteID); onDismiss() }
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.accentColor.opacity(hoveringPrimary ? 1.0 : 0.9), in: Capsule())
            .foregroundStyle(.white)
            .onHover { hoveringPrimary = $0 }
    }
    private var secondaryButton: some View {
        let label = message.kind == .askToSave ? "Dismiss" : (message.kind == .duplicate ? "Save as new" : "Dismiss")
        return Button(label) {
            if message.kind == .duplicate { onSaveAsNew() }
            onDismiss()
        }
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.secondary.opacity(hoveringSecondary ? 0.2 : 0.12), in: Capsule())
            .onHover { hoveringSecondary = $0 }
    }
}

struct FooterStatusBar: View {
    @Bindable var state: ReadingNotesUIState
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.separator).frame(height: 0.5)
            HStack {
                Button { state.onPauseToggle(); state.isPaused.toggle() } label: {
                    ZStack {
                        Circle().fill(state.isPaused ? Color.gray : Color.green).frame(width: 7, height: 7)
                            .shadow(color: (state.isPaused ? Color.gray : Color.green).opacity(0.6), radius: 6)
                        if !state.isPaused {
                            Circle().stroke(Color.green.opacity(0.3), lineWidth: 1).frame(width: 14, height: 14)
                                .scaleEffect(pulse ? 1.6 : 1.0)
                                .opacity(pulse ? 0.0 : 0.6)
                                .onAppear {
                                    withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                                        pulse = true
                                    }
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(width: Theme.minHit, height: Theme.minHit)
                Text(state.isPaused ? "Paused" : "Ambient reader active").font(.system(size: Theme.captionSize)).foregroundStyle(.secondary)
                Spacer()
                Button { state.showSettings = true; state.onOpenSettings() } label: { Image(systemName: "gearshape").font(.system(size: Theme.iconMedium, weight: .semibold)) }
                    .buttonStyle(.plain).frame(width: Theme.gearHit, height: Theme.gearHit)
            }
            .frame(height: 28)
            .padding(.horizontal, Theme.outerHorizontalPadding)
        }
    }
}

#Preview {
    VStack {
        AmbientPill(message: AmbientPillState(kind: .askToSave, title: "Local LLMs", noteID: UUID()), onDismiss: { })
        FooterStatusBar(state: ReadingNotesUIState())
    }
}
