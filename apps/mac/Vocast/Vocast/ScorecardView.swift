import SwiftUI

// Signature component: the quality scorecard. Reused in Studio (per block) and Denoise.

struct ScorecardView: View {
    var card: Scorecard
    var footnote: String = Scorecard.footnote

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                gateBanner
                grid
                if !card.sub.isEmpty { subMetrics }
                Text(footnote)
                    .font(.ui(12.5))
                    .foregroundStyle(Palette.ash)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            .padding(Space.lg)
        }
    }

    private var gateBanner: some View {
        HStack(spacing: 10) {
            StatusDot(color: card.gatePassed ? Palette.good : Palette.attention, size: 8)
            Text(card.gatePassed ? "Passed quality gate"
                 : "Needs attention: \(card.attentionReason ?? "")")
                .font(.ui(13.5, .semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill((card.gatePassed ? Palette.good : Palette.attention).opacity(0.08)))
        .hairline(10, color: (card.gatePassed ? Palette.good : Palette.attention).opacity(0.45))
    }

    private var grid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(card.headline) { m in tile(m) }
        }
    }

    private func tile(_ m: HeadlineMetric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(m.key).font(.mono(11)).tracking(0.4).foregroundStyle(Palette.ash)
                Spacer()
                StatusDot(color: m.pass ? Palette.good : Palette.attention, size: 7)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(m.value).font(.mono(26, .semibold)).foregroundStyle(Palette.ink)
                if !m.unit.isEmpty { Text(m.unit).font(.mono(11)).foregroundStyle(Palette.mute) }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceElevated)
                    Capsule().fill(m.pass ? Palette.good : Palette.attention)
                        .frame(width: geo.size.width * CGFloat(m.progress))
                }
            }.frame(height: 3)
            Text(m.name).font(.ui(12.5)).foregroundStyle(Palette.mute)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Palette.surface, radius: 10)
    }

    private var subMetrics: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Sub-metrics").padding(.bottom, 12)
            VStack(spacing: 0) {
                ForEach(Array(card.sub.enumerated()), id: \.element.id) { i, s in
                    HStack {
                        StatusDot(color: s.pass ? Palette.good : Palette.attention, size: 7)
                        Text(s.name).font(.ui(13.5)).foregroundStyle(Palette.body)
                        Spacer()
                        Text(s.value).font(.mono(13)).foregroundStyle(Palette.ink)
                    }
                    .padding(.vertical, 13).padding(.horizontal, 14)
                    if i < card.sub.count - 1 {
                        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 14)
                    }
                }
            }
            .card(Palette.surface, radius: 10)
        }
    }
}
