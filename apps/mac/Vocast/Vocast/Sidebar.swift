import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 0) {
            // Wordmark row (traffic lights sit over its left edge)
            HStack(spacing: 8) {
                Text("Vocast").font(.ui(15, .semibold)).foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.leading, 78)
            .frame(height: kBarHeight)
            .overlay(alignment: .bottom) { Hairline() }

            VStack(alignment: .leading, spacing: 14) {
                SearchField(text: $app.search)

                VStack(alignment: .leading, spacing: 2) {
                    Text("LIBRARY").font(.mono(11)).tracking(0.4)
                        .foregroundStyle(Palette.ash)
                        .padding(.leading, 12).padding(.bottom, 6)

                    SidebarRow(area: .studio)
                    SidebarRow(area: .voices, count: app.voices.profiles.count)
                    SidebarRow(area: .denoise)
                    SidebarRow(area: .tasks, count: max(app.tasks.runningCount, 0) > 0 ? app.tasks.runningCount : nil)
                }

                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 8)

                SidebarRow(area: .settings)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            Spacer(minLength: 0)

            OfflineChip().padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface)
        .scrollContentBackground(.hidden)
    }
}

struct SidebarRow: View {
    @Environment(AppModel.self) private var app
    var area: Area
    var count: Int? = nil

    private var selected: Bool { app.area == area }

    var body: some View {
        Button {
            app.area = area
        } label: {
            HStack(spacing: 12) {
                Image(systemName: area.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(selected ? Palette.accent : Palette.mute)
                    .frame(width: 18)
                Text(area.title)
                    .font(.ui(14, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.ink : Palette.body)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.mono(11)).foregroundStyle(Palette.mute)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.surfaceElevated))
                        .hairline(Radius.row, color: Palette.hairline)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? Palette.surfaceElevated : .clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Palette.accent).frame(width: 3, height: 18).offset(x: -6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Palette.ash)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.ui(13.5))
                .foregroundStyle(Palette.body)
            Keycap("⌘K")
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
        .hairline(Radius.control, color: Palette.hairline)
    }
}

struct Keycap: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.mono(11)).foregroundStyle(Palette.ash)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).fill(Palette.surface))
            .hairline(Radius.keycap, color: Palette.hairline)
    }
}

struct OfflineChip: View {
    var body: some View {
        HStack(spacing: 10) {
            StatusDot(color: Palette.good, size: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("On this Mac, offline").font(.ui(13, .medium)).foregroundStyle(Palette.body)
                Text("Nothing leaves your device").font(.mono(11)).foregroundStyle(Palette.ash)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Palette.surface, radius: 10)
    }
}
