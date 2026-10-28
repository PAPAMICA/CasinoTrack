import Foundation

/// Sources d’alimentation de la **cagnotte** (et coûts de la sortie).
/// - `cb` / `liquide` : argent de poche
/// - `fromPrevious` : Budget importé des gains des sorties précédentes
///
/// Legacy rawValue `"gain"` → `fromPrevious` (ancien « Rejouer » visite).
enum BudgetSource: String, Codable, CaseIterable, Identifiable {
    case cb
    case liquide
    case fromPrevious

    var id: String { rawValue }

    /// Cases affichées pour alimenter la cagnotte.
    static var potFundingCases: [BudgetSource] { allCases }

    static func parse(_ raw: String?) -> BudgetSource {
        guard let raw else { return .liquide }
        if raw == "gain" { return .fromPrevious }
        return BudgetSource(rawValue: raw) ?? .liquide
    }

    var label: String {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.fr.rawValue
        let t = L10n(AppLanguage(rawValue: raw) ?? .fr)
        switch self {
        case .cb: return t.sourceCB
        case .liquide: return t.sourceCash
        case .fromPrevious: return t.sourceBudget
        }
    }

    var isCash: Bool { self == .cb || self == .liquide }

    /// Compte dans CB / Liquide / Budget (coût de la sortie).
    var countsAsVisitCost: Bool { true }
}

/// Source d’un topup machine.
/// - `cb` / `liquide` : nouvel argent de poche (compte dans les coûts + alimente le jeu)
/// - `cagnotte` : prélèvement interne (« Rejouer ») — hors CB/Liquide/Budget
enum MachineFundingSource: String, CaseIterable, Identifiable {
    case cb
    case liquide
    case cagnotte

    var id: String { rawValue }

    var label: String {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.fr.rawValue
        let t = L10n(AppLanguage(rawValue: raw) ?? .fr)
        switch self {
        case .cb: return t.sourceCB
        case .liquide: return t.sourceCash
        case .cagnotte: return t.sourcePot
        }
    }

    /// RawValue stocké dans `BudgetEntry.source`.
    var budgetRawValue: String { rawValue }

    var asBudgetSource: BudgetSource? {
        switch self {
        case .cb: return .cb
        case .liquide: return .liquide
        case .cagnotte: return nil
        }
    }
}

enum MoneyMath {
    static let cagnotteSourceRaw = MachineFundingSource.cagnotte.rawValue

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

    /// Coût sortie = CB + Liquide + Budget (précédent). Hors rejouer cagnotte→machine.
    static func visitCostBasis(cb: Double, liquide: Double, fromPrevious: Double) -> Double {
        cb + liquide + fromPrevious
    }

    /// Capital / cagnotte alimentée = CB + Liquide + Budget.
    static func totalBudget(cb: Double, liquide: Double, fromPrevious: Double) -> Double {
        cb + liquide + fromPrevious
    }

    /// Solde cagnotte = alimentations hors machine − prélèvements cagnotte + cash-outs
    /// (+ topups CB/Liquide directs machine n’entrent pas dans la cagnotte tant qu’ils sont en jeu ;
    ///   leurs cash-outs y reviennent).
    static func cagnotteBalance(
        potFunding: Double,
        withdrawnFromPot: Double,
        cashOuts: Double
    ) -> Double {
        potFunding - withdrawnFromPot + cashOuts
    }

    /// Net = Gains (solde / argent sortie) − CB − Liquide − Budget.
    static func visitNet(gains: Double?, costBasis: Double) -> Double? {
        guard let gains else { return nil }
        return gains - costBasis
    }

    static func multiplier(win: Double, bet: Double?) -> Double? {
        guard let bet, bet > 0, win.isFinite else { return nil }
        return win / bet
    }

    /// × générique = net / spent (guard div/0).
    static func pocketMultiplier(net: Double, spent: Double) -> Double? {
        guard spent > 0, net.isFinite else { return nil }
        return net / spent
    }

    /// × agrégé (home / stats) = net_total / (Σ CB + Σ Liquide). Budget exclu.
    static func aggregatePocketMultiplier(net: Double, cashSpent: Double) -> Double? {
        pocketMultiplier(net: net, spent: cashSpent)
    }

    /// × visite = net / (CB + Liquide + Budget) = net / costBasis.
    static func visitMultiplier(net: Double?, costBasis: Double) -> Double? {
        guard let net else { return nil }
        return pocketMultiplier(net: net, spent: costBasis)
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

    static func visitGainsFromSessions(cashOuts: [Double?]) -> Double? {
        let outs = cashOuts.compactMap { $0 }
        guard !outs.isEmpty else { return nil }
        return outs.reduce(0, +)
    }
}
