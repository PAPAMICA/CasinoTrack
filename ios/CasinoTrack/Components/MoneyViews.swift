import SwiftUI

struct MoneyText: View {
    let value: Double?
    var withSign: Bool = false
    var placeholder: String = "-"

    var body: some View {
        if let value {
            Text(MoneyMath.formatEUR(value, withSign: withSign))
                .foregroundStyle(color(for: value))
                .monospacedDigit()
                .ctNumericText(value: value)
        } else {
            Text(placeholder)
                .foregroundStyle(CTTheme.muted)
        }
    }

    private func color(for value: Double) -> Color {
        if value > 0 { return CTTheme.win }
        if value < 0 { return CTTheme.lose }
        return CTTheme.ink
    }
}

struct NetHero: View {
    @Environment(LanguageStore.self) private var language
    let net: Double?
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.t.net)
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(CTTheme.gold)
            if let net {
                Text(MoneyMath.formatEUR(net, withSign: true))
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                    .foregroundStyle(net >= 0 ? CTTheme.win : CTTheme.lose)
                    .monospacedDigit()
                    .ctNumericText(value: net)
            } else {
                Text("-")
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                    .foregroundStyle(CTTheme.muted)
            }
            Text(subtitle ?? language.t.netFormula)
                .font(.footnote)
                .foregroundStyle(CTTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusPill: View {
    enum Kind { case live, done }
    let kind: Kind
    @Environment(LanguageStore.self) private var language

    var body: some View {
        HStack(spacing: 6) {
            if kind == .live {
                TimelineView(.animation(minimumInterval: 1 / 20, paused: false)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let pulse = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * (.pi * 2 / 1.6)))
                    Circle()
                        .fill(CTTheme.win)
                        .frame(width: 7, height: 7)
                        .opacity(pulse)
                }
            } else {
                Circle()
                    .fill(CTTheme.muted)
                    .frame(width: 7, height: 7)
                    .opacity(0.7)
            }
            Text(kind == .live ? language.t.statusLive : language.t.statusDone)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(kind == .live ? CTTheme.win.opacity(0.15) : CTTheme.felt.opacity(0.55))
        )
        .foregroundStyle(kind == .live ? CTTheme.win : CTTheme.champagne)
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: CTTheme.minTap)
            .background(
                LinearGradient(colors: [CTTheme.goldBright, CTTheme.gold], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .foregroundStyle(CTTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CTPressButtonStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: CTTheme.minTap)
            .background(CTTheme.felt.opacity(0.7))
            .foregroundStyle(CTTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CTPressButtonStyle(pressedScale: 0.975))
    }
}

struct BudgetBreakdownRow: View {
    @Environment(LanguageStore.self) private var language
    let cb: Double
    let liquide: Double
    let reinvested: Double
    var compact: Bool = true

    private var parts: [(String, Double, Color)] {
        let t = language.t
        return [
            (t.sourceCB, cb, CTTheme.champagne),
            (t.sourceCash, liquide, CTTheme.goldBright),
            (t.sourceReinvestedShort, reinvested, CTTheme.feltSoft),
        ].filter { $0.1 > 0 }
    }

    var body: some View {
        if parts.isEmpty {
            Text(language.t.budgetDash)
                .font(.caption2)
                .foregroundStyle(CTTheme.muted)
        } else {
            HStack(spacing: compact ? 6 : 10) {
                ForEach(parts, id: \.0) { part in
                    HStack(spacing: 3) {
                        Text(part.0)
                            .foregroundStyle(CTTheme.muted)
                        Text(MoneyMath.formatEUR(part.1))
                            .foregroundStyle(part.2)
                            .fontWeight(.semibold)
                            .ctNumericText(value: part.1)
                    }
                    .font(.caption2)
                    .monospacedDigit()
                }
            }
        }
    }
}

struct RankRow: View {
    let title: String
    var subtitle: String? = nil
    let trailing: String
    var trailingColor: Color = CTTheme.ink
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.body.weight(.semibold))
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CTTheme.gold.opacity(0.2))
                            .foregroundStyle(CTTheme.gold)
                            .clipShape(Capsule())
                    }
                }
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(CTTheme.muted)
                }
            }
            Spacer()
            Text(trailing)
                .font(.body.weight(.semibold))
                .foregroundStyle(trailingColor)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.vertical, 10)
    }
}

struct BonusChip: View {
    let type: BonusType
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(type.name)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hexString: type.colorHex).opacity(selected ? 0.35 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(hexString: type.colorHex).opacity(selected ? 1 : 0.35), lineWidth: selected ? 2 : 1)
                )
                .foregroundStyle(CTTheme.ink)
        }
        .buttonStyle(CTPressButtonStyle(pressedScale: 0.96))
    }
}

struct MachineThumb: View {
    var path: String? = nil
    var data: Data? = nil
    var image: UIImage? = nil
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let img = PhotoStore.image(data: data, path: path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    CTTheme.felt
                    Image(systemName: "rectangle.grid.3x2.fill")
                        .foregroundStyle(CTTheme.gold.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
