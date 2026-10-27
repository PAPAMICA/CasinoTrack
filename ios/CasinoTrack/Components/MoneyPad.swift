import SwiftUI

struct MoneyPad: View {
    @Binding var valueText: String
    var presets: [Int] = [10, 20, 50, 100, 200]
    var onConfirm: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Text(display)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(CTTheme.champagne)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { p in
                    Button("\(p)") { appendPreset(p) }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(CTTheme.felt.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(["1","2","3","4","5","6","7","8","9",".","0","⌫"], id: \.self) { key in
                    Button {
                        tap(key)
                    } label: {
                        Text(key)
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: CTTheme.minTap)
                            .background(CTTheme.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let onConfirm {
                PrimaryButton(title: LanguageStore.shared.t.validate, icon: "checkmark") { onConfirm() }
            }
        }
    }

    private var display: String {
        let n = MoneyMath.toNumber(valueText)
        return MoneyMath.formatEUR(n)
    }

    private func tap(_ key: String) {
        if key == "⌫" {
            if !valueText.isEmpty { valueText.removeLast() }
            return
        }
        if key == "." {
            if valueText.contains(".") { return }
            valueText = valueText.isEmpty ? "0." : valueText + "."
            return
        }
        if valueText == "0" { valueText = key; return }
        if let dot = valueText.firstIndex(of: ".") {
            let decimals = valueText[valueText.index(after: dot)...]
            if decimals.count >= 2 { return }
        }
        valueText += key
    }

    private func appendPreset(_ p: Int) {
        let current = MoneyMath.toNumber(valueText)
        valueText = String(format: "%.2f", current + Double(p))
    }
}

struct MoneyPadSheet: View {
    let title: String
    @Binding var amount: Double
    var sources: [BudgetSource]? = nil
    @Binding var source: BudgetSource
    var confirmTitle: String = "Valider"
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let sources {
                    HStack(spacing: 8) {
                        ForEach(sources) { s in
                            Button {
                                source = s
                            } label: {
                                Text(s.label)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(source == s ? CTTheme.gold : CTTheme.felt.opacity(0.7))
                                    .foregroundStyle(source == s ? CTTheme.bg : CTTheme.ink)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                MoneyPad(valueText: $text)
                PrimaryButton(title: confirmTitle) {
                    amount = MoneyMath.toNumber(text)
                    onConfirm()
                    dismiss()
                }
            }
            .padding()
            .ctScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .onAppear {
            text = amount > 0 ? String(format: "%.2f", amount) : ""
        }
    }
}

// MARK: - Bet / Mise pad

enum BetUnit: Double, CaseIterable, Identifiable {
    case u001 = 0.01
    case u002 = 0.02
    case u005 = 0.05
    case u010 = 0.10
    case u020 = 0.20
    case u050 = 0.50
    case u100 = 1.00

    var id: Double { rawValue }

    var label: String {
        if rawValue >= 1 { return "1 €" }
        return MoneyMath.formatEUR(rawValue)
    }

    static func matching(_ value: Double?) -> BetUnit {
        guard let value, value > 0 else { return .u001 }
        return allCases.first { abs($0.rawValue - value) < 0.000_05 } ?? .u001
    }
}

struct BetPad: View {
    @Binding var valueText: String
    /// Prefer machine.defaultBet when it matches a chip unit.
    var preferredUnit: Double? = nil
    var onConfirm: (() -> Void)? = nil

    @State private var unit: BetUnit = .u001
    @FocusState private var amountFocused: Bool

    private let standardMultiples = [50, 100, 150, 200, 250]
    private let x88Multiples = [88, 176, 264, 352, 440]

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(MoneyMath.formatEUR(MoneyMath.toNumber(valueText)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CTTheme.champagne)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                TextField("Saisie libre", text: $valueText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(.body.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CTTheme.ink)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: CTTheme.minTap)
                    .background(CTTheme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            unitSelector

            multipleRow(title: "Multiples", multiples: standardMultiples)
            multipleRow(title: "×88", multiples: x88Multiples)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { key in
                    Button { tap(key) } label: {
                        Text(key)
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: CTTheme.minTap)
                            .background(CTTheme.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let onConfirm {
                PrimaryButton(title: LanguageStore.shared.t.validate, icon: "checkmark") { onConfirm() }
            }
        }
        .onAppear {
            unit = BetUnit.matching(preferredUnit)
            amountFocused = false
        }
    }

    private var unitSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unité")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CTTheme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BetUnit.allCases) { u in
                        Button {
                            unit = u
                        } label: {
                            Text(u.label)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: CTTheme.minTap)
                                .background(unit == u ? CTTheme.gold : CTTheme.felt.opacity(0.8))
                                .foregroundStyle(unit == u ? CTTheme.bg : CTTheme.ink)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func multipleRow(title: String, multiples: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CTTheme.muted)
            HStack(spacing: 6) {
                ForEach(multiples, id: \.self) { m in
                    Button {
                        applyMultiple(m)
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(m)×")
                                .font(.caption.weight(.bold))
                            Text(compactEUR(unit.rawValue * Double(m)))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(CTTheme.champagne)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: CTTheme.minTap)
                        .background(CTTheme.felt.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func applyMultiple(_ multiplier: Int) {
        let amount = unit.rawValue * Double(multiplier)
        valueText = String(format: "%.2f", amount)
        amountFocused = false
    }

    private func compactEUR(_ value: Double) -> String {
        MoneyMath.formatEUR(value)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func tap(_ key: String) {
        amountFocused = false
        if key == "⌫" {
            if !valueText.isEmpty { valueText.removeLast() }
            return
        }
        if key == "." {
            if valueText.contains(".") || valueText.contains(",") { return }
            valueText = valueText.isEmpty ? "0." : valueText + "."
            return
        }
        if valueText == "0" { valueText = key; return }
        let sep = valueText.firstIndex(of: ".") ?? valueText.firstIndex(of: ",")
        if let sep {
            let decimals = valueText[valueText.index(after: sep)...]
            if decimals.count >= 2 { return }
        }
        valueText += key
    }
}

struct BetMoneyPadSheet: View {
    let title: String
    @Binding var amount: Double
    var preferredUnit: Double? = nil
    var confirmTitle: String = "Valider"
    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                BetPad(valueText: $text, preferredUnit: preferredUnit)
                    .padding()
            }
            .ctScreen()
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: confirmTitle) {
                    amount = MoneyMath.toNumber(text)
                    onConfirm()
                    dismiss()
                }
                .padding()
                .background(CTTheme.bg.opacity(0.95))
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            text = amount > 0 ? String(format: "%.2f", amount) : ""
        }
    }
}
