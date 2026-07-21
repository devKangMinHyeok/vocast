import SwiftUI

// MARK: - Voice picker
//
// The Studio sub-toolbar's voice selector, built to the product handoff spec:
// a rich trigger (avatar + name + language pill + chevron) that opens a real
// dropdown listbox of profiles, rather than cycling to the next one on click.
//
// The Timbre `--rc-*` tokens map onto Palette:
//   surface / surface-elevated / surface-card, hairline / hairline-strong,
//   ray -> accent, ink, mute/ash, mono font. No shadows (surface ladder for
//   depth); rounding follows 5/6/7/8/10.
//
// The panel is presented by StudioView (see `voiceMenu(...)`) so it can float
// over the content below and sit above a full-pane click-catcher that, with the
// Esc key, dismisses it. Arrow keys move the highlight, Return selects.

/// The trigger chip. Toggles the dropdown; reflects its open state.
struct VoiceTrigger: View {
    @Environment(AppModel.self) private var app

    private var open: Bool { app.studio.voiceMenuOpen }

    var body: some View {
        Button {
            app.studio.voiceMenuOpen.toggle()
        } label: {
            HStack(spacing: 10) {
                Avatar(initials: app.currentProfileInitials, size: 26)
                Text(app.currentProfileName)
                    .font(.ui(13.5, .medium)).foregroundStyle(Palette.ink).fixedSize()
                LangPill(language: app.currentVoiceLanguage)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.mute)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.leading, 6).padding(.trailing, 10).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(open ? Palette.surfaceElevated : Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(open ? Palette.hairlineStrong : Palette.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.calm, value: open)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Voice profile")
        .accessibilityValue(app.currentProfileName)
        .accessibilityHint("Opens the list of voice profiles")
    }
}

/// The dropdown listbox of profiles. Presented at the pane level so it can float
/// over content; owns keyboard navigation. Outside-click dismissal is handled by
/// the click-catcher StudioView places beneath it.
struct VoiceMenuPanel: View {
    @Environment(AppModel.self) private var app

    private var profiles: [EngineProfile] { app.backendProfiles }
    private var highlight: Int { app.studio.voiceMenuHighlight }
    private var activeIndex: Int {
        profiles.firstIndex { $0.id == app.selectedProfileID } ?? 0
    }

    var body: some View {
        VStack(spacing: 2) {
            if profiles.isEmpty {
                Text("No voice profiles yet")
                    .font(.ui(13)).foregroundStyle(Palette.mute)
                    .frame(height: 40).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            ForEach(Array(profiles.enumerated()), id: \.element.id) { i, p in
                row(p, index: i)
            }
        }
        .padding(5)
        .frame(minWidth: 260, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Palette.hairlineStrong, lineWidth: 1))
        .fixedSize()
        // Keyboard nav (Esc / up / down / return) is handled by StudioView, which
        // owns a key monitor and drives voiceMenuHighlight. The panel just starts
        // the highlight on the current selection when it opens.
        .onAppear { app.studio.voiceMenuHighlight = activeIndex }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice profiles")
    }

    private func row(_ p: EngineProfile, index: Int) -> some View {
        let selected = p.id == app.selectedProfileID
        let active = index == highlight
        return Button {
            select(p.id)
        } label: {
            HStack(spacing: 10) {
                Avatar(initials: p.initials, size: 24, elevated: !selected)
                Text(p.name).font(.ui(13.5, .medium)).foregroundStyle(Palette.ink)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 12)
                LangPill(language: VoiceLanguage(profileCode: p.lang))
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 12)
            }
            .padding(.horizontal, 8).frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected || active ? Palette.surfaceCard : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { app.studio.voiceMenuHighlight = index } }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ id: String) {
        app.selectedProfileID = id
        app.studio.voiceMenuOpen = false
    }
}

/// Small language tag used in the trigger and each row (mono, 5px radius).
struct LangPill: View {
    @Environment(AppModel.self) private var app
    var language: VoiceLanguage
    var body: some View {
        Text(app.s.nameOf(language))
            .font(.mono(11)).foregroundStyle(Palette.ash)
            .padding(.horizontal, 8).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1))
    }
}
