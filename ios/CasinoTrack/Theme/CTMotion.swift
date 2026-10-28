import SwiftUI

/// Vocabulaire motion CasinoTrack — présence / hiérarchie, pas de bruit.
enum CTMotion {
    static let appear = Animation.easeOut(duration: 0.45)
    static let appearFast = Animation.easeOut(duration: 0.32)
    static let press = Animation.easeOut(duration: 0.15)
    static let snappy = Animation.snappy(duration: 0.35)
    static let tabSwitch = Animation.easeInOut(duration: 0.28)
    static let springAppear = Animation.spring(response: 0.55, dampingFraction: 0.82)
    static let chart = Animation.easeOut(duration: 0.55)
    static let content = Animation.easeInOut(duration: 0.38)

    static func stagger(_ index: Int, base: Double = 0.04, step: Double = 0.045) -> Animation {
        appear.delay(base + Double(index) * step)
    }

    static func heroDelay(_ step: Int) -> Animation {
        appear.delay(0.05 + Double(step) * 0.12)
    }
}

// MARK: - Button styles

struct CTPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(CTMotion.press, value: configuration.isPressed)
    }
}

struct CTCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(CTMotion.press, value: configuration.isPressed)
    }
}

// MARK: - View modifiers

private struct CTAppearModifier: ViewModifier {
    let appeared: Bool
    var offset: CGFloat
    var scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : offset)
            .scaleEffect(appeared ? 1 : scale)
    }
}

private struct CTStaggerAppearModifier: ViewModifier {
    let appeared: Bool
    let index: Int
    var offset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : offset)
            .animation(CTMotion.stagger(index), value: appeared)
    }
}

extension View {
    /// Fade + léger offset (empty states, sections).
    func ctAppear(_ appeared: Bool, offset: CGFloat = 14, scale: CGFloat = 1) -> some View {
        modifier(CTAppearModifier(appeared: appeared, offset: offset, scale: scale))
    }

    /// Apparition décalée pour listes / cartes.
    func ctStagger(_ appeared: Bool, index: Int, offset: CGFloat = 10) -> some View {
        modifier(CTStaggerAppearModifier(appeared: appeared, index: index, offset: offset))
    }

    /// Transition numérique pour montants qui changent.
    func ctNumericText<V: Equatable>(value: V) -> some View {
        self
            .contentTransition(.numericText())
            .animation(CTMotion.snappy, value: value)
    }

    /// Chrome sheet cohérent (detents + poignée + fond opaque).
    func ctSheetChrome(
        detents: Set<PresentationDetent> = [.medium, .large]
    ) -> some View {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(CTTheme.bg)
    }

    /// Déclenche un flag d’apparition une fois (stagger / empty).
    func ctTriggerAppear(_ appeared: Binding<Bool>) -> some View {
        onAppear {
            guard !appeared.wrappedValue else { return }
            withAnimation(CTMotion.appear) {
                appeared.wrappedValue = true
            }
        }
    }
}

// MARK: - Empty state (langage Floor)

struct CTEmptyState: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String = "suit.diamond.fill"
    var ctaTitle: String? = nil
    var ctaIcon: String? = nil
    var cta: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CTTheme.gold)
                    .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: appeared)
                    .ctAppear(appeared, offset: 12)

                Text(title)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(CTTheme.gold)
                    .multilineTextAlignment(.center)
                    .ctAppear(appeared, offset: 16)

                if let subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(CTTheme.champagne.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .ctAppear(appeared, offset: 14)
                }
            }
            .animation(CTMotion.heroDelay(0), value: appeared)

            if let ctaTitle, let cta {
                PrimaryButton(title: ctaTitle, icon: ctaIcon) { cta() }
                    .ctAppear(appeared, offset: 18, scale: 0.96)
                    .animation(CTMotion.springAppear.delay(0.18), value: appeared)
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ctTriggerAppear($appeared)
    }
}
