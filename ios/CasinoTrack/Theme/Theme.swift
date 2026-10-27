import SwiftUI

enum CTTheme {
    static let bg = Color(hex: 0x0A1612)
    static let bgElevated = Color(hex: 0x12241E)
    static let felt = Color(hex: 0x1F4A3E)
    static let feltSoft = Color(hex: 0x2A5F50)
    static let gold = Color(hex: 0xD4AF6A)
    static let goldBright = Color(hex: 0xE8C878)
    static let champagne = Color(hex: 0xEAD9AE)
    static let ink = Color(hex: 0xF5EDD7)
    static let muted = Color(hex: 0x8FA89E)
    static let win = Color(hex: 0x34D399)
    static let lose = Color(hex: 0xF43F5E)

    static let minTap: CGFloat = 52
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        self.init(hex: UInt(value))
    }
}

struct FeltBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Soft breathe: gold wash + felt depth, very subtle (~6s cycle).
            let goldPulse = 0.10 + 0.04 * (0.5 + 0.5 * sin(t * (.pi * 2 / 6.0)))
            let feltPulse = 0.30 + 0.08 * (0.5 + 0.5 * sin(t * (.pi * 2 / 7.5) + 1.2))

            ZStack {
                CTTheme.bg
                RadialGradient(
                    colors: [CTTheme.gold.opacity(goldPulse), .clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [CTTheme.felt.opacity(feltPulse), .clear],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: 360
                )
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func ctScreen() -> some View {
        self
            .background(FeltBackground())
            .foregroundStyle(CTTheme.ink)
    }
}
