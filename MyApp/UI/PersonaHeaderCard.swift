import SwiftUI

struct PersonaHeaderCard: View {
    @Bindable var state: ReadingNotesUIState
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: Theme.iconMedium, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("PERSONA & FOCUS DIRECTIVE")
                    .font(.system(size: Theme.labelSize, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(state.isEditingDirective ? "Done" : "Edit") {
                    if state.isEditingDirective {
                        state.directive = state.draftDirective
                    } else {
                        state.draftDirective = state.directive
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        state.isEditingDirective.toggle()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(state.isEditingDirective ? Color.accentColor : Color.secondary.opacity(0.25))
                .foregroundStyle(state.isEditingDirective ? .white : .primary)
                .controlSize(.small)
            }

            if state.isEditingDirective {
                TextField("", text: $state.draftDirective, axis: .vertical)
                    .font(.system(size: Theme.bodySize))
                    .lineLimit(3...6)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 3)
                    )
                    .focused($fieldFocused)
                    .onAppear { fieldFocused = true }
                HStack {
                    Text("Changes apply to new notes")
                        .font(.system(size: Theme.captionSizeSmall))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(state.draftDirective.count)").font(.system(size: Theme.captionSizeSmall, design: .monospaced)).foregroundStyle(.secondary)
                }
            } else {
                Text(state.persona).font(.system(size: Theme.titleSize, weight: .semibold))
                Text(state.directive)
                    .font(.system(size: Theme.bodySize))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineLimit(3)
            }
        }
        .padding(Theme.headerCardPadding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.headerCardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.headerCardRadius).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .onSubmit {
            if state.isEditingDirective {
                state.directive = state.draftDirective
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.isEditingDirective = false }
            }
        }
    }
}

#Preview {
    PersonaHeaderCard(state: {
        let s = ReadingNotesUIState()
        s.isEditingDirective = false
        return s
    }())
}
