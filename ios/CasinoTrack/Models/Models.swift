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

    var expenseBySource: [BudgetSource: Double] {
        var totals: [BudgetSource: Double] = [.cb: 0, .liquide: 0, .gain: 0]
        for b in budgets {
            let src = BudgetSource(rawValue: b.source) ?? .liquide
            totals[src, default: 0] += b.amount
        }
        return totals
    }

    var cashExpense: Double {
        let e = expenseBySource
        return MoneyMath.cashExpense(cb: e[.cb] ?? 0, liquide: e[.liquide] ?? 0)
    }

    var reinvested: Double { expenseBySource[.gain] ?? 0 }

    var budgetCB: Double { expenseBySource[.cb] ?? 0 }
    var budgetLiquide: Double { expenseBySource[.liquide] ?? 0 }

    /// Capital engagé = CB + Liquide + Réinvesti
    var totalBudget: Double {
        MoneyMath.totalBudget(cb: budgetCB, liquide: budgetLiquide, gain: reinvested)
    }

    /// Σ cash-outs des sessions (retraits enregistrés). `nil` si aucun retrait.
    var sessionCashOutTotal: Double? {
        MoneyMath.visitGainsFromSessions(cashOuts: sessions.map(\.cashOut))
    }

    /// Gains pour net / × : saisie / sync session (`manualTotalWin`), sinon somme des cash-outs.
    var effectiveGains: Double? {
        manualTotalWin ?? sessionCashOutTotal
    }

    var net: Double? {
        MoneyMath.visitNet(gains: effectiveGains, expense: cashExpense, reinvested: reinvested)
    }

    /// × = gains / capital engagé (prend CB, Liquide et Réinvesti)
    var spendMultiplier: Double? {
        MoneyMath.visitMultiplier(
            gains: effectiveGains,
            cb: budgetCB,
            liquide: budgetLiquide,
            reinvested: reinvested
        )
    }

    /// Aligne `manualTotalWin` sur la somme des cash-outs (persistance, stats, sheet Gains).
    @discardableResult
    func syncGainsFromSessions() -> Bool {
        guard let total = sessionCashOutTotal else { return false }
        if manualTotalWin != total {
            manualTotalWin = total
            return true
        }
        return false
    }

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

    var sourceLabel: String {
        (BudgetSource(rawValue: source) ?? .liquide).label
    }

    @MainActor
    var kindLabel: String {
        let t = LanguageStore.shared.t
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
