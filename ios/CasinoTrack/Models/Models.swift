import Foundation
import SwiftData
import UIKit

@Model
final class Casino {
    /// Ancien id API - non unique (CloudKit l’interdit)
    var legacyId: Int?
    var name: String
    var address: String?
    var city: String?
    var lat: Double?
    var lon: Double?
    var website: String?
    var source: String
    var isFavorite: Bool
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \Visit.casino)
    var visits: [Visit]
    @Relationship(inverse: \Machine.casinos)
    var machines: [Machine]

    init(
        legacyId: Int? = nil,
        name: String,
        address: String? = nil,
        city: String? = nil,
        lat: Double? = nil,
        lon: Double? = nil,
        website: String? = nil,
        source: String = "manual",
        isFavorite: Bool = false,
        createdAt: Date = .now
    ) {
        self.legacyId = legacyId
        self.name = name
        self.address = address
        self.city = city
        self.lat = lat
        self.lon = lon
        self.website = website
        self.source = source
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.visits = []
        self.machines = []
    }
}

@Model
final class MachineType {
    var legacyId: Int?
    var name: String
    var sortOrder: Int

    init(legacyId: Int? = nil, name: String, sortOrder: Int = 0) {
        self.legacyId = legacyId
        self.name = name
        self.sortOrder = sortOrder
    }
}

@Model
final class BonusType {
    var legacyId: Int?
    var name: String
    var sortOrder: Int
    var colorHex: String

    init(legacyId: Int? = nil, name: String, sortOrder: Int = 0, colorHex: String = "#cea658") {
        self.legacyId = legacyId
        self.name = name
        self.sortOrder = sortOrder
        self.colorHex = colorHex
    }
}

@Model
final class Machine {
    var legacyId: Int?
    var name: String
    var manufacturer: String?
    /// Chemin local legacy (seed / ancien stockage)
    var photoPath: String?
    /// Photo sync iCloud (CKAsset via external storage)
    @Attribute(.externalStorage) var photoData: Data?
    var defaultBet: Double?
    var bonusFeatures: String?
    var hasJackpot: Bool
    var isFavorite: Bool
    var notes: String?
    var createdAt: Date
    var machineType: MachineType?
    var bonusTypes: [BonusType]
    var casinos: [Casino]
    @Relationship(deleteRule: .nullify, inverse: \MachineSession.catalogMachine)
    var sessions: [MachineSession]

    init(
        legacyId: Int? = nil,
        name: String,
        manufacturer: String? = nil,
        photoPath: String? = nil,
        photoData: Data? = nil,
        defaultBet: Double? = nil,
        bonusFeatures: String? = nil,
        hasJackpot: Bool = false,
        isFavorite: Bool = false,
        notes: String? = nil,
        createdAt: Date = .now,
        machineType: MachineType? = nil
    ) {
        self.legacyId = legacyId
        self.name = name
        self.manufacturer = manufacturer
        self.photoPath = photoPath
        self.photoData = photoData
        self.defaultBet = defaultBet
        self.bonusFeatures = bonusFeatures
        self.hasJackpot = hasJackpot
        self.isFavorite = isFavorite
        self.notes = notes
        self.createdAt = createdAt
        self.machineType = machineType
        self.bonusTypes = []
        self.casinos = []
        self.sessions = []
    }

    var resolvedImage: UIImage? {
        PhotoStore.image(data: photoData, path: photoPath)
    }
}

@Model
final class Visit {
    var legacyId: Int?
    var startedAt: Date
    var endedAt: Date?
    /// Si défini, prioritaire sur le calcul startedAt/endedAt.
    var manualDurationSeconds: Int?
    var plannedBudget: Double
    var manualTotalWin: Double?
    var notes: String?
    var createdAt: Date
    var casino: Casino?
    @Relationship(deleteRule: .cascade, inverse: \BudgetEntry.visit)
    var budgets: [BudgetEntry]
    @Relationship(deleteRule: .cascade, inverse: \MachineSession.visit)
    var sessions: [MachineSession]

    init(
        legacyId: Int? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        manualDurationSeconds: Int? = nil,
        plannedBudget: Double = 0,
        manualTotalWin: Double? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        casino: Casino? = nil
    ) {
        self.legacyId = legacyId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.manualDurationSeconds = manualDurationSeconds
        self.plannedBudget = plannedBudget
        self.manualTotalWin = manualTotalWin
        self.notes = notes
        self.createdAt = createdAt
        self.casino = casino
        self.budgets = []
        self.sessions = []
    }

    var isLive: Bool { endedAt == nil }

    /// Durée affichée : override manuel, sinon endedAt − startedAt, sinon chronomètre live.
    var effectiveDuration: TimeInterval { effectiveDuration(at: .now) }

    func effectiveDuration(at date: Date) -> TimeInterval {
        if let manual = manualDurationSeconds {
            return TimeInterval(max(0, manual))
        }
        if let ended = endedAt {
            return max(0, ended.timeIntervalSince(startedAt))
        }
        return max(0, date.timeIntervalSince(startedAt))
    }

    var isTimingLive: Bool {
        endedAt == nil && manualDurationSeconds == nil
    }

    /// Édition manuelle : stocke l’override et aligne `endedAt` sur startedAt + durée si la sortie est déjà close.
    func applyManualDuration(seconds: Int) {
        let clamped = max(0, seconds)
        manualDurationSeconds = clamped
        if endedAt != nil {
            endedAt = startedAt.addingTimeInterval(TimeInterval(clamped))
        }
    }

    /// Entrées qui comptent comme coût / alimentation (hors prélèvement cagnotte→machine).
    var expenseBySource: [BudgetSource: Double] {
        var totals: [BudgetSource: Double] = [.cb: 0, .liquide: 0, .fromPrevious: 0]
        for b in budgets {
            guard b.source != MoneyMath.cagnotteSourceRaw else { continue }
            let src = BudgetSource.parse(b.source)
            totals[src, default: 0] += b.amount
        }
        return totals
    }

    var cashExpense: Double {
        let e = expenseBySource
        return MoneyMath.cashExpense(cb: e[.cb] ?? 0, liquide: e[.liquide] ?? 0)
    }

    /// Budget = imports depuis sorties précédentes (pas le rejouer interne).
    var budgetFromPrevious: Double { expenseBySource[.fromPrevious] ?? 0 }

    /// Alias historique UI / stats (`reinvested` → Budget précédent).
    var reinvested: Double { budgetFromPrevious }

    var budgetCB: Double { expenseBySource[.cb] ?? 0 }
    var budgetLiquide: Double { expenseBySource[.liquide] ?? 0 }

    /// Coût sortie pour le net : CB + Liquide + Budget.
    var costBasis: Double {
        MoneyMath.visitCostBasis(cb: budgetCB, liquide: budgetLiquide, fromPrevious: budgetFromPrevious)
    }

    /// Capital alimenté (CB + Liquide + Budget) — info UI.
    var totalBudget: Double {
        MoneyMath.totalBudget(cb: budgetCB, liquide: budgetLiquide, fromPrevious: budgetFromPrevious)
    }

    /// Alimentations cagnotte uniquement (hors topups CB/Liquide liés à une machine).
    var potFundingTotal: Double {
        budgets
            .filter { entry in
                !entry.isCagnotteWithdraw
                    && entry.linkedSession == nil
                    && BudgetSource.parse(entry.source).countsAsVisitCost
            }
            .reduce(0) { $0 + $1.amount }
    }

    /// Topups machine payés CB/Liquide (hors cagnotte).
    var machineExternalTopups: Double {
        budgets
            .filter { $0.linkedSession != nil && !$0.isCagnotteWithdraw }
            .reduce(0) { $0 + $1.amount }
    }

    /// Prélèvements cagnotte → machine : Σ amountIn − topups CB/Liquide liés.
    /// (Les entrées `source=cagnotte` sont l’audit ; `amountIn` fait foi, y compris legacy.)
    var withdrawnFromPot: Double {
        let totalIn = sessions.reduce(0.0) { $0 + $1.amountIn }
        return max(0, totalIn - machineExternalTopups)
    }

    /// Σ cash-outs des sessions (retraits enregistrés).
    var sessionCashOutSum: Double {
        sessions.compactMap(\.cashOut).reduce(0, +)
    }

    /// Σ cash-outs. `nil` si aucun retrait.
    var sessionCashOutTotal: Double? {
        MoneyMath.visitGainsFromSessions(cashOuts: sessions.map(\.cashOut))
    }

    /// Solde courant de la cagnotte de la sortie (ledger sessions).
    var cagnotteBalance: Double {
        MoneyMath.cagnotteBalance(
            potFunding: potFundingTotal,
            withdrawnFromPot: withdrawnFromPot,
            cashOuts: sessionCashOutSum
        )
    }

    /// Cagnotte affichée : si sortie close, priorise les gains effectifs (évite un ledger ~1300 vs 700).
    var displayedCagnotteBalance: Double {
        if !isLive, let gains = effectiveGains {
            return gains
        }
        return cagnotteBalance
    }

    var hasCagnotteActivity: Bool {
        !budgets.isEmpty || sessions.contains { $0.amountIn > 0 || $0.cashOut != nil }
    }

    /// Gains / argent sortie : override manuel, sinon solde cagnotte.
    var effectiveGains: Double? {
        if let manualTotalWin { return manualTotalWin }
        guard hasCagnotteActivity else { return nil }
        return cagnotteBalance
    }

    /// Net = argent_sortie − CB − Liquide − Budget. Rejouer interne exclu.
    var net: Double? {
        MoneyMath.visitNet(gains: effectiveGains, costBasis: costBasis)
    }

    /// × = net / (CB + Liquide + Budget) = net / costBasis.
    var spendMultiplier: Double? {
        MoneyMath.visitMultiplier(net: net, costBasis: costBasis)
    }

    /// Les gains suivent le solde cagnotte tant que `manualTotalWin` est nil.
    /// Un override manuel (clôture / édition Gains) est conservé.
    @discardableResult
    func syncGainsFromCagnotte() -> Bool {
        hasCagnotteActivity
    }

    /// Compat : ancien nom — sync depuis cagnotte.
    @discardableResult
    func syncGainsFromSessions() -> Bool { syncGainsFromCagnotte() }

    /// Suppression fiable : enfants d’abord (évite le double-cascade `BudgetEntry`
    /// lié à la fois à la visite et à une session).
    func deleteCascade(in context: ModelContext) {
        let sessions = Array(sessions)
        for session in sessions {
            let bonuses = Array(session.bonuses)
            for bonus in bonuses {
                context.delete(bonus)
            }
            let linked = Array(session.linkedBudgetEntries)
            for entry in linked {
                context.delete(entry)
            }
            context.delete(session)
        }
        let remainingBudgets = Array(budgets)
        for entry in remainingBudgets {
            context.delete(entry)
        }
        context.delete(self)
    }
}

@Model
final class BudgetEntry {
    var kind: String
    var amount: Double
    var source: String
    var at: Date
    var note: String?
    var visit: Visit?
    /// Session machine à l’origine de ce topup (suppression en cascade).
    var linkedSession: MachineSession?

    init(
        kind: String,
        amount: Double,
        source: String = BudgetSource.liquide.rawValue,
        at: Date = .now,
        note: String? = nil,
        visit: Visit? = nil,
        linkedSession: MachineSession? = nil
    ) {
        self.kind = kind
        self.amount = amount
        self.source = source
        self.at = at
        self.note = note
        self.visit = visit
        self.linkedSession = linkedSession
    }

    var isCagnotteWithdraw: Bool { source == MoneyMath.cagnotteSourceRaw }

    var sourceLabel: String {
        if isCagnotteWithdraw {
            return MachineFundingSource.cagnotte.label
        }
        return BudgetSource.parse(source).label
    }

    @MainActor
    var kindLabel: String {
        let t = LanguageStore.shared.t
        if isCagnotteWithdraw { return t.budgetKindReplay }
        switch kind {
        case "planned": return t.budgetKindPlanned
        case "topup": return t.budgetKindTopup
        default: return kind.capitalized
        }
    }
}

@Model
final class MachineSession {
    var legacyId: Int?
    var machineName: String
    var amountIn: Double
    var betSetting: Double?
    var cashOut: Double?
    var startedAt: Date
    /// Instant de fin (cash out / quitter la machine).
    var endedAt: Date?
    /// Si défini, prioritaire sur le calcul startedAt/endedAt.
    var manualDurationSeconds: Int?
    var notes: String?
    var visit: Visit?
    var machineType: MachineType?
    var catalogMachine: Machine?
    @Relationship(deleteRule: .cascade, inverse: \BonusEvent.session)
    var bonuses: [BonusEvent]
    /// Topups budget créés depuis « Ajouter à la machine » ; cascade à la suppression de session.
    @Relationship(deleteRule: .cascade, inverse: \BudgetEntry.linkedSession)
    var linkedBudgetEntries: [BudgetEntry]

    init(
        legacyId: Int? = nil,
        machineName: String,
        amountIn: Double = 0,
        betSetting: Double? = nil,
        cashOut: Double? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        manualDurationSeconds: Int? = nil,
        notes: String? = nil,
        visit: Visit? = nil,
        machineType: MachineType? = nil,
        catalogMachine: Machine? = nil
    ) {
        self.legacyId = legacyId
        self.machineName = machineName
        self.amountIn = amountIn
        self.betSetting = betSetting
        self.cashOut = cashOut
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.manualDurationSeconds = manualDurationSeconds
        self.notes = notes
        self.visit = visit
        self.machineType = machineType
        self.catalogMachine = catalogMachine
        self.bonuses = []
        self.linkedBudgetEntries = []
    }

    var sessionNet: Double { MoneyMath.sessionNet(amountIn: amountIn, cashOut: cashOut) }

    /// Durée affichée / utilisée : override manuel, sinon endedAt − startedAt, sinon chronomètre live.
    var effectiveDuration: TimeInterval { effectiveDuration(at: .now) }

    func effectiveDuration(at date: Date) -> TimeInterval {
        if let manual = manualDurationSeconds {
            return TimeInterval(max(0, manual))
        }
        if let ended = endedAt {
            return max(0, ended.timeIntervalSince(startedAt))
        }
        return max(0, date.timeIntervalSince(startedAt))
    }

    var isTimingLive: Bool {
        endedAt == nil && manualDurationSeconds == nil
    }

    /// Clôture chronométrée (Quitter la machine) : fixe `endedAt`, efface l’override manuel.
    func closeTiming(at date: Date = .now) {
        if endedAt == nil {
            endedAt = date
        }
        manualDurationSeconds = nil
    }

    /// Édition manuelle : stocke l’override et aligne `endedAt` sur startedAt + durée.
    func applyManualDuration(seconds: Int) {
        let clamped = max(0, seconds)
        manualDurationSeconds = clamped
        endedAt = startedAt.addingTimeInterval(TimeInterval(clamped))
    }
}

@Model
final class BonusEvent {
    var legacyId: Int?
    var winAmount: Double
    var betAmount: Double?
    var label: String?
    var photoPath: String?
    @Attribute(.externalStorage) var photoData: Data?
    var at: Date
    var session: MachineSession?
    var types: [BonusType]

    init(
        legacyId: Int? = nil,
        winAmount: Double = 0,
        betAmount: Double? = nil,
        label: String? = nil,
        photoPath: String? = nil,
        photoData: Data? = nil,
        at: Date = .now,
        session: MachineSession? = nil,
        types: [BonusType] = []
    ) {
        self.legacyId = legacyId
        self.winAmount = winAmount
        self.betAmount = betAmount
        self.label = label
        self.photoPath = photoPath
        self.photoData = photoData
        self.at = at
        self.session = session
        self.types = types
    }

    var multiplier: Double? { MoneyMath.multiplier(win: winAmount, bet: betAmount) }

    var typeLabel: String {
        let names = types.map(\.name)
        return names.isEmpty ? (label ?? "Bonus") : names.joined(separator: " + ")
    }

    var resolvedImage: UIImage? {
        PhotoStore.image(data: photoData, path: photoPath)
    }
}
