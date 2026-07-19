import SwiftUI

// Segmented pill control: selected = white bg + black text, rest transparent + body.
struct Segmented<T: Hashable>: View {
    var options: [(value: T, label: String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { opt in
                let sel = selection == opt.value
                Button { selection = opt.value } label: {
                    Text(opt.label)
                        .font(.ui(13, sel ? .semibold : .medium))
                        .foregroundStyle(sel ? Palette.onWhite : Palette.body)
                        .fixedSize()
                        .padding(.horizontal, 14).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                            .fill(sel ? Palette.white : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
        .hairline(Radius.control, color: Palette.hairline)
    }
}

// Simple flow layout that wraps subviews onto multiple lines (used by karaoke words).
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 6
    var vSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + vSpacing; lineHeight = 0
            }
            x += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x - bounds.minX + size.width > maxWidth, x > bounds.minX {
                x = bounds.minX; y += lineHeight + vSpacing; lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// Version pill: "v2"
struct VersionPill: View {
    var text: String
    var body: some View {
        Text(text).font(.mono(11)).foregroundStyle(Palette.mute)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).fill(Palette.surfaceElevated))
            .hairline(Radius.keycap, color: Palette.hairline)
    }
}
