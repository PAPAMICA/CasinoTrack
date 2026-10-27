import SwiftUI

/// Segment pour une barre de répartition horizontale.
struct DistBarSegment: Identifiable, Equatable {
    var id: String { key }
    var key: String
    var label: String
    var value: Double
    var color: Color
}

/// Barre horizontale segmentée + légende (remplace les donuts).
struct DistributionBar: View {
    let title: String
    let segments: [DistBarSegment]
    var totalText: String? = nil
    var valueFormatter: (Double) -> String = { "\(Int($0.rounded()))" }
    var percentFormatter: (Int) -> String = { "\($0) %" }
    var barHeight: CGFloat = 12

    private var total: Double {
        segments.reduce(0) { $0 + $1.value }
    }

    private var visible: [DistBarSegment] {
        segments.filter { $0.value > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CTTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let totalText {
                    Text(totalText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CTTheme.champagne)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            stackedBar

            VStack(alignment: .leading, spacing: 6) {
                ForEach(visible) { seg in
                    let pct = total > 0 ? Int(((seg.value / total) * 100).rounded()) : 0
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(seg.color)
                            .frame(width: 10, height: 10)
                        Text(seg.label)
                            .font(.caption)
                            .foregroundStyle(CTTheme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(valueFormatter(seg.value))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CTTheme.ink)
                            .monospacedDigit()
                        Text(percentFormatter(pct))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CTTheme.muted)
                            .monospacedDigit()
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CTTheme.bgElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(CTMotion.chart, value: visible.map(\.value))
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            let gap: CGFloat = 1.5
            Group {
                if total <= 0 || visible.isEmpty {
                    Capsule()
                        .fill(CTTheme.felt.opacity(0.45))
                } else {
                    let gaps = CGFloat(max(visible.count - 1, 0)) * gap
                    let usable = max(geo.size.width - gaps, 0)
                    let raw = visible.map { max(usable * CGFloat($0.value / total), 2) }
                    let sum = raw.reduce(0, +)
                    let scale = sum > usable && sum > 0 ? usable / sum : 1

                    HStack(spacing: gap) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { i, seg in
                            Capsule()
                                .fill(seg.color)
                                .frame(width: raw[i] * scale, height: barHeight)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: barHeight, alignment: .leading)
        }
        .frame(height: barHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        visible.map { seg in
            let pct = total > 0 ? Int(((seg.value / total) * 100).rounded()) : 0
            return "\(seg.label) \(valueFormatter(seg.value)) \(percentFormatter(pct))"
        }
        .joined(separator: ", ")
    }
}
