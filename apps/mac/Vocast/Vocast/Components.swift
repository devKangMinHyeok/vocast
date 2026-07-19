import SwiftUI

// MARK: - Waveform bar strip
//
// Vertical rounded bars from a peaks array. Optional playhead progress colors bars
// up to the playhead with the accent and the rest with stone (inactive).

struct WaveBars: View {
    var peaks: [Double]
    var color: Color = Palette.stone
    var activeColor: Color = Palette.accent
    var progress: Double? = nil        // 0...1 playhead; nil = single color
    var height: CGFloat = 30
    var barWidth: CGFloat = 3
    var gap: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let count = peaks.count
            let totalGap = gap * CGFloat(max(0, count - 1))
            let w = max(1.5, (geo.size.width - totalGap) / CGFloat(max(1, count)))
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    let active = progress.map { Double(i) / Double(max(1, count - 1)) <= $0 } ?? false
                    Capsule(style: .continuous)
                        .fill(progress == nil ? color : (active ? activeColor : Palette.stone))
                        .frame(width: w, height: max(2, CGFloat(peaks[i]) * height))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(height: height)
    }
}

// Dot-style strip (used on the similarity result): small circles that grow toward the end.
struct WaveDots: View {
    var count: Int = 56
    var height: CGFloat = 22
    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let d = max(3, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    let t = Double(i) / Double(count)
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: d, height: max(d, d + CGFloat(t) * (height - d)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(height: height)
    }
}

// MARK: - Live animated waveform (recording)

struct LiveWave: View {
    var active: Bool
    var color: Color = Palette.accent
    var height: CGFloat = 46
    var bars = 44

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let gap: CGFloat = 3
                let w = max(2, (geo.size.width - gap * CGFloat(bars - 1)) / CGFloat(bars))
                HStack(alignment: .center, spacing: gap) {
                    ForEach(0..<bars, id: \.self) { i in
                        let base = active
                            ? (0.25 + 0.75 * abs(sin(t * 6 + Double(i) * 0.5)) * (0.4 + 0.6 * abs(sin(Double(i)))))
                            : 0.12
                        Capsule(style: .continuous)
                            .fill(active ? color : Palette.stone)
                            .frame(width: w, height: max(2, CGFloat(base) * height))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Level meter (green -> orange gradient)

struct LevelBar: View {
    var level: Double            // 0...1
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceElevated)
                Capsule()
                    .fill(LinearGradient(colors: [Palette.good, Palette.accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, level)))))
            }
        }
        .frame(height: height)
    }
}

// Vertical segmented level meter (studio-style), green safe with orange clip zone.
struct LevelMeter: View {
    var level: Double
    var clipping: Bool = false
    var height: CGFloat = 10
    var body: some View { LevelBar(level: level, height: height) }
}

// MARK: - Thin progress bar

struct ThinProgress: View {
    var value: Double
    var height: CGFloat = 5
    var gradient: Bool = false
    var track: Color = Palette.surfaceElevated
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(gradient ? AnyShapeStyle(Palette.brandGradient) : AnyShapeStyle(Palette.accent))
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, value)))))
                    .animation(Motion.progress, value: value)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Avatar & logo

struct Avatar: View {
    var initials: String
    var size: CGFloat = 44
    var elevated: Bool = false   // non-default profiles use a flat elevated tile
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(elevated ? AnyShapeStyle(Palette.surfaceElevated) : AnyShapeStyle(Palette.brandGradient))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.ui(size * 0.34, .semibold))
                    .foregroundStyle(elevated ? Palette.mute : Palette.onWhite)
            )
            .hairline(size * 0.28, color: elevated ? Palette.hairline : .clear)
    }
}

struct LogoMark: View {
    var size: CGFloat = 60
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Palette.brandGradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(Palette.onWhite)
            )
    }
}

// MARK: - Pills & status dots

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 7
    var blink: Bool = false
    @State private var on = true
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .opacity(blink ? (on ? 1 : 0.25) : 1)
            .onAppear {
                guard blink else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = false }
            }
    }
}

struct DotLabel: View {
    var text: String
    var color: Color
    var mono: Bool = false
    var blink: Bool = false
    var body: some View {
        HStack(spacing: 7) {
            StatusDot(color: color, blink: blink)
            Text(text)
                .font(mono ? .mono(12) : .ui(12.5, .medium))
                .foregroundStyle(Palette.body)
        }
    }
}

struct TagPill: View {
    var text: String
    var color: Color = Palette.accent
    var body: some View {
        Text(text.uppercased())
            .font(.mono(10))
            .tracking(0.5)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var enabled: Bool = true
    var action: () -> Void
    @State private var pressed = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let s = systemImage { Image(systemName: s).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.ui(13.5, .semibold))
            }
            .foregroundStyle(Palette.onWhite)
            .padding(.horizontal, 18).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(enabled ? (pressed ? Palette.primaryPressed : Palette.white) : Palette.stone))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        ._onPressChange { pressed = $0 }
    }
}

struct SecondaryButton: View {
    var title: String
    var systemImage: String? = nil
    var tint: Color = Palette.body
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let s = systemImage { Image(systemName: s).font(.system(size: 13, weight: .medium)) }
                Text(title).font(.ui(13.5, .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.surfaceElevated))
            .hairline(Radius.control, color: Palette.hairline)
        }
        .buttonStyle(.plain)
    }
}

// Small bordered square icon button (regenerate / scorecard on a block).
struct IconButton: View {
    var systemImage: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.mute)
                .frame(width: 32, height: 30)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surfaceElevated))
                .hairline(Radius.control, color: Palette.hairline)
        }
        .buttonStyle(.plain)
    }
}

// Round play/pause button (transport + A/B).
struct PlayCircle: View {
    var playing: Bool
    var size: CGFloat = 34
    var filled: Bool = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(filled ? Palette.onWhite : Palette.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? Palette.white : Palette.surfaceElevated))
                .overlay(filled ? nil : Circle().strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Eyebrow / meta text

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.mono(11)).tracking(0.4).foregroundStyle(Palette.ash)
    }
}

// MARK: - Press-change helper

private struct PressChange: ViewModifier {
    var onChange: (Bool) -> Void
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onChange(true) }
                .onEnded { _ in onChange(false) }
        )
    }
}
extension View {
    func _onPressChange(_ onChange: @escaping (Bool) -> Void) -> some View {
        modifier(PressChange(onChange: onChange))
    }
}
