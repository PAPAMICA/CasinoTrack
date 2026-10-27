import Foundation

enum BudgetSource: String, Codable, CaseIterable, Identifiable {
    case cb, liquide, gain

    var id: String { rawValue }

    var label: String {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.fr.rawValue
        let t = L10n(AppLanguage(rawValue: raw) ?? .fr)
        switch self {
        case .cb: return t.sourceCB
        case .liquide: return t.sourceCash
        case .gain: return t.sourceReinvested
        }
    }

    var isCash: Bool { self == .cb || self == .liquide }
}

enum MoneyMath {
    static func toNumber(_ value: Any?) -> Double {
        switch value {
        case let d as Double: return d.isFinite ? d : 0
        case let i as Int: return Double(i)
        case let s as String:
            let cleaned = s.replacingOccurrences(of: ",", with: ".")
            return Double(cleaned) ?? 0
        case let n as NSNumber: return n.doubleValue
        default: return 0
        }
    }

    static func formatEUR(_ value: Double, withSign: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = CTDates.locale
        formatter.maximumFractionDigits = 2
        let absText = formatter.string(from: NSNumber(value: abs(value))) ?? "€0"
        if withSign {
            if value > 0 { return "+\(absText)" }
            if value < 0 { return "−\(absText)" }
            return absText
        }
        return value < 0 ? "−\(absText)" : absText
    }

    static func cashExpense(cb: Double, liquide: Double) -> Double { cb + liquide }

    /// Capital engagé = CB + Liquide + Réinvesti
    static func totalBudget(cb: Double, liquide: Double, gain: Double) -> Double {
        cb + liquide + gain
    }

    static func visitNet(gains: Double?, expense: Double, reinvested: Double) -> Double? {
        guard let gains else { return nil }
        return gains - expense - reinvested
    }

    static func multiplier(win: Double, bet: Double?) -> Double? {
        guard let bet, bet > 0, win.isFinite else { return nil }
        return win / bet
    }

    /// × home / stats = gain net / dépensé (CB + Liquide, hors réinvesti)
    static func pocketMultiplier(net: Double, spent: Double) -> Double? {
        guard spent > 0, net.isFinite else { return nil }
        return net / spent
    }

    /// × sortie (détail / historique) = gains / capital engagé (CB + Liquide + Réinvesti)
    static func visitMultiplier(gains: Double?, cb: Double, liquide: Double, reinvested: Double) -> Double? {
        guard let gains else { return nil }
        let capital = totalBudget(cb: cb, liquide: liquide, gain: reinvested)
        return multiplier(win: gains, bet: capital > 0 ? capital : nil)
    }

    static func formatMultiplier(_ m: Double?) -> String {
        guard let m, m.isFinite else { return "-" }
        let magnitude = Swift.abs(m)
        let rounded: Double
        if magnitude >= 100 { rounded = m.rounded() }
        else { rounded = (m * 10).rounded() / 10 }
        if Swift.abs(rounded - rounded.rounded()) < 1e-9 {
            return "×\(Int(rounded.rounded()))"
        }
        return String(format: "×%.1f", rounded)
    }

    static func sessionNet(amountIn: Double, cashOut: Double?) -> Double {
        (cashOut ?? 0) - amountIn
    }

    /// Σ cash-outs non nuls (encaissements machines d’une visite).
    static func visitGainsFromSessions(cashOuts: [Double?]) -> Double? {
        let outs = cashOuts.compactMap { $0 }
        guard !outs.isEmpty else { return nil }
        return outs.reduce(0, +)
    }
}
