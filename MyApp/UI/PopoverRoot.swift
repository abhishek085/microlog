import SwiftUI

struct PopoverRoot: View {
    @Bindable var state: ReadingNotesUIState

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VStack(spacing: Theme.cardGap) {
                    PersonaHeaderCard(state: state)
                    HStack {
                        TodayRow(count: state.notes.count)
                        Spacer()
                        Button { state.takeNote() } label: { Label("Take note", systemImage: "plus.circle.fill") }
                            .buttonStyle(.borderedProminent).tint(.accentColor).controlSize(.small)
                    }
                    timeline
                    FooterStatusBar(state: state)
                }
                .padding(.horizontal, Theme.outerHorizontalPadding)
                .padding(.top, Theme.cardGap)
                .padding(.bottom, 28 + Theme.cardGap)

                if let ambient = state.ambient {
                    AmbientPill(
                        message: ambient,
                        onView: { id in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                state.selectedNoteID = id
                            }
                        },
                        onSaveAsNew: { state.onSaveAsNew() },
                        onDismiss: { state.ambient = nil }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                    .padding(.horizontal, 10)
                }
            }
            .sheet(isPresented: $state.showSettings) { SettingsView(isPaused: $state.isPaused) }
            .frame(width: Theme.containerWidth, height: Theme.containerHeight)
            .background(
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(Theme.backgroundOpacity)
                    Rectangle().fill(.ultraThinMaterial)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.containerRadius))
            .navigationDestination(item: $state.selectedNoteID) { id in
                if let note = state.notes.first(where: { $0.id == id }) {
                    NoteDetailView(note: note, state: state)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.ambient?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.isEditingDirective)
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: Theme.cardGap) {
                ForEach(state.displayedNotes) { note in
                    NoteRow(note: note, state: state)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if state.notes.count > state.visibleCount {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            state.visibleCount += 15
                        }
                    } label: {
                        HStack {
                            Text("Show \(min(15, state.notes.count - state.visibleCount)) more")
                                .font(.system(size: Theme.bodySize))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Theme.cardVerticalPadding + 2)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                if state.notes.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "book.pages").font(.system(size: 22))
                        Text(Theme.emptyTitle).font(.system(size: Theme.bodySize, weight: .semibold))
                        Text(Theme.emptyCaption).font(.system(size: Theme.captionSize)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 2)
            .scrollIndicators(.hidden)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 8 / 420),
                    .init(color: .black, location: 1 - (30 / 420)),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .safeAreaInset(edge: .bottom) {
            if state.isPaused {
                HStack {
                    Text("Reading is paused").font(.system(size: Theme.captionSize)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Resume") { state.onPauseToggle() }
                        .buttonStyle(.bordered).controlSize(.mini).tint(.accentColor)
                }
                .padding(6)
                .background(.ultraThinMaterial)
            }
        }
    }
}

#Preview("List") {
    PopoverRoot(state: .init()).frame(width: 340, height: 420)
}
#Preview("Dark", traits: .fixedLayout(width: 340, height: 420)) {
    PopoverRoot(state: .init()).preferredColorScheme(.dark)
}
