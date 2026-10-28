import Foundation
import SwiftData

struct StatsFilter: Equatable {
    enum Period: String, CaseIterable, Identifiable {
        case all, days30, month, year, visit
        var id: String { rawValue }
        @MainActor
        var label: String {
            let t = LanguageStore.shared.t
            switch self {
            case .all: return t.statsPeriodAll
            case .days30: return t.statsPeriod30d
            case .month: return t.statsPeriodMonth
            case .year: return t.statsPeriodYear
            case .visit: return t.statsPeriodVisit
            }
        }
    }

    var period: Period = .all
    var casinoLegacyId: Int? = nil
    var machineTypeName: String? = nil
}

struct BankrollStats {
    var visitsCount: Int
    var net: Double
    var pocket: Double
    var cb: Double
    var liquide: Double
    var reinvested: Double
    var gains: Double
    var pocketROI: Double?
    var reinvestRate: Double?
    var bestNet: Double?
    var worstNet: Double?
    var previousNet: Double?
}

struct TimeStats {
    /// Σ effectiveDuration des sorties (secondes).
    var totalVisitSeconds: Int
    /// Σ effectiveDuration des sessions (secondes).
    var totalSessionSeconds: Int
    var visitCount: Int
    var sessionCount: Int
    /// Net cumulé ÷ heures de sorties (si temps > 0).
    var netPerHour: Double?

    var avgVisitSeconds: Int? {
        guard visitCount > 0 else { return nil }
        return totalVisitSeconds / visitCount
    }

    var avgSessionSeconds: Int? {
        guard sessionCount > 0 else { return nil }
        return totalSessionSeconds / sessionCount
    }
}

struct MachineRank: Identifiable {
    var id: String { name }
    var name: String
    var sessions: Int
    /// Σ (cashOut − amountIn) sur les sessions.
    var net: Double
    /// Σ amountIn (mis dans la machine).
    var amountIn: Double
    var bonusCount: Int
    /// Σ win bonus / Σ bet bonus si mises, sinon net / amountIn.
    var multiplier: Double?
    var hot: Bool
    /// Σ durées effectives des sessions (secondes).
    var durationSeconds: Int
    /// Net ÷ heures de machine (si temps > 0).
    var euroPerHour: Double?
    /// Machine catalogue liée (via sessions), pour navigation détail.
    var machine: Machine?
}

struct BonusRank: Identifiable {
    var id: String { name }
    var name: String
    var colorHex: String
    var count: Int
    var winTotal: Double
    var betTotal: Double
    var avgMult: Double?
    var winShare: Double
}

struct ComboRank: Identifiable {
    var id: String { key }
    var key: String
    var label: String
    var count: Int
    var winTotal: Double
    var avgMult: Double?
}

struct CasinoRank: Identifiable {
    var id: String { name }
    var name: String
    var visits: Int
    var net: Double
    var pocket: Double
    var reinvested: Double
    /// Σ durées effectives des sorties (secondes).
    var durationSeconds: Int
}

struct CumulativeNetPoint: Identifiable {
    var id: Date { date }
    var date: Date
    var net: Double
    var index: Int
}

struct MonthlyBarPoint: Identifiable {
    var id: String { monthKey }
    var monthKey: String
    var label: String
    var spent: Double
    var gains: Double
    var net: Double
}

/// Tranche pour barres de répartition (parts).
struct DistSlice: Identifiable, Equatable {
    var id: String { key }
    /// Clé stable : `cb`, `liquide`, `pocket`, `reinvested`, `wins`, `losses`, `autres`, ou nom métier.
    var key: String
    var value: Double
    /// Couleur catalogue (types de bonus), sinon palette UI.
    var colorHex: String?
}

/// Unité d’affichage du total / légende d’une répartition.
enum DistValueKind: Equatable {
    case money
    case count
    case durationSeconds
}

struct DistributionStats {
    /// Dépensé : CB vs Liquide.
    var spendBySource: [DistSlice]
    /// Capital : Dépensé (poche) vs Budget (précédent).
    var capitalFlow: [DistSlice]
    /// Résultat sorties (€) : Σ nets positifs vs |Σ nets négatifs|.
    var visitResults: [DistSlice]
    /// Sessions gagnantes vs perdantes (nombre) — niveau machine, distinct des sorties.
    var sessionResultsCount: [DistSlice]
    /// Bonus : gains par type (top + Autres).
    var bonusByType: [DistSlice]
    /// Casinos : dépensé (poche) top + Autres.
    var spendByCasino: [DistSlice]
    /// Mis (amountIn) par machine (top + Autres).
    var amountInByMachine: [DistSlice]
}

struct StatsSnapshot {
    var bankroll: BankrollStats
    var time: TimeStats
    var machines: [MachineRank]
    var bonuses: [BonusRank]
    var combos: [ComboRank]
    var casinos: [CasinoRank]
    var cumulativeNets: [CumulativeNetPoint]
    var monthlyBars: [MonthlyBarPoint]
    var distributions: DistributionStats
    var winStreak: Int
    var loseStreak: Int
    var byMachineType: [(String, Int, Double)]
    var avgBonusMult: Double?
    var bestBonus: (win: Double, mult: Double?, machine: String, date: Date)?
}

/// Stats catalogue pour une machine (sessions liées + homonymes non liés).
struct MachineCatalogStats {
    var sessionCount: Int
    var amountIn: Double
    var bonusGains: Double
    var bonusBetTotal: Double
    var sessionNet: Double
    /// Σ durées effectives (secondes).
    var totalDurationSeconds: Int
    var bonuses: [BonusEvent]

    var bonusCount: Int { bonuses.count }

    /// × bonus = Σ win / Σ bet si mises connues, sinon sessionNet / amountIn.
    var multiplier: Double? {
        if bonusBetTotal > 0 {
            return MoneyMath.multiplier(win: bonusGains, bet: bonusBetTotal)
        }
        return MoneyMath.multiplier(win: sessionNet, bet: amountIn > 0 ? amountIn : nil)
    }
}

enum StatsEngine {
    static func catalogStats(for machine: Machine, sessions: [MachineSession]) -> MachineCatalogStats {
        var seen = Set<PersistentIdentifier>()
        let related = sessions.filter { session in
            let linked = session.catalogMachine?.persistentModelID == machine.persistentModelID
            let byName = session.machineName.localizedCaseInsensitiveCompare(machine.name) == .orderedSame
            guard linked || byName else { return false }
            return seen.insert(session.persistentModelID).inserted
        }

        var amountIn = 0.0
        var bonusGains = 0.0
        var bonusBet = 0.0
        var sessionNet = 0.0
        var totalDuration = 0
        var bonuses: [BonusEvent] = []

        for session in related {
            amountIn += session.amountIn
            sessionNet += session.sessionNet
            totalDuration += Int(session.effectiveDuration.rounded())
            for bonus in session.bonuses {
                bonuses.append(bonus)
                bonusGains += bonus.winAmount
                if let bet = bonus.betAmount, bet > 0 {
                    bonusBet += bet
                }
            }
        }

        bonuses.sort { $0.at > $1.at }

        return MachineCatalogStats(
            sessionCount: related.count,
            amountIn: amountIn,
            bonusGains: bonusGains,
            bonusBetTotal: bonusBet,
            sessionNet: sessionNet,
            totalDurationSeconds: totalDuration,
            bonuses: bonuses
        )
    }

    static func build(visits: [Visit], filter: StatsFilter) -> StatsSnapshot {
        let filtered = visits.filter { matches($0, filter) }.sorted { $0.startedAt < $1.startedAt }
        let bankroll = bankrollStats(filtered, filter: filter)
        let time = timeStats(filtered, net: bankroll.net)
        let machines = machineRanks(filtered)
        let bonuses = bonusRanks(filtered)
        let casinos = casinoRanks(filtered)
        return StatsSnapshot(
            bankroll: bankroll,
            time: time,
            machines: machines,
            bonuses: bonuses,
            combos: comboRanks(filtered),
            casinos: casinos,
            cumulativeNets: cumulative(filtered),
            monthlyBars: monthlyBars(filtered),
            distributions: distributions(
                bankroll: bankroll,
                visits: filtered,
                bonuses: bonuses,
                casinos: casinos,
                machines: machines
            ),
            winStreak: streak(filtered, winning: true),
            loseStreak: streak(filtered, winning: false),
            byMachineType: typeBreakdown(filtered),
            avgBonusMult: globalBonusMult(filtered),
            bestBonus: bestBonus(filtered)
        )
    }

    private static func matches(_ visit: Visit, _ filter: StatsFilter) -> Bool {
        if let casinoId = filter.casinoLegacyId {
            guard visit.casino?.legacyId == casinoId else { return false }
        }
        let cal = CTDates.calendar
        let now = Date()
        switch filter.period {
        case .all: break
        case .days30:
            guard let from = cal.date(byAdding: .day, value: -30, to: now), visit.startedAt >= from else { return false }
        case .month:
            guard cal.isDate(visit.startedAt, equalTo: now, toGranularity: .month) else { return false }
        case .year:
            guard cal.isDate(visit.startedAt, equalTo: now, toGranularity: .year) else { return false }
        case .visit:
            break
        }
        if let typeName = filter.machineTypeName {
            let has = visit.sessions.contains { $0.machineType?.name == typeName || $0.catalogMachine?.machineType?.name == typeName }
            if !has { return false }
        }
        return true
    }

    private static func bankrollStats(_ visits: [Visit], filter: StatsFilter) -> BankrollStats {
        var pocket = 0.0, cb = 0.0, liquide = 0.0, reinvested = 0.0, gains = 0.0, netSum = 0.0
        var best: Double?, worst: Double?
        for v in visits {
            pocket += v.cashExpense
            cb += v.budgetCB
            liquide += v.budgetLiquide
            reinvested += v.reinvested
            if let g = v.effectiveGains { gains += g }
            if let n = v.net {
                netSum += n
                best = best.map { max($0, n) } ?? n
                worst = worst.map { min($0, n) } ?? n
            }
        }
        let denom = pocket + reinvested
        let previous: Double? = {
            guard filter.period == .days30 || filter.period == .month else { return nil }
            return nil
        }()
        return BankrollStats(
            visitsCount: visits.count,
            net: netSum,
            pocket: pocket,
            cb: cb,
            liquide: liquide,
            reinvested: reinvested,
            gains: gains,
            // × global = net / (CB + Liquide) — Budget exclu
            pocketROI: MoneyMath.aggregatePocketMultiplier(net: netSum, cashSpent: pocket),
            reinvestRate: denom > 0 ? reinvested / denom : nil,
            bestNet: best,
            worstNet: worst,
            previousNet: previous
        )
    }

    private static func timeStats(_ visits: [Visit], net: Double) -> TimeStats {
        var visitSeconds = 0
        var sessionSeconds = 0
        var sessionCount = 0
        for v in visits {
            visitSeconds += Int(v.effectiveDuration.rounded())
            for s in v.sessions {
                sessionSeconds += Int(s.effectiveDuration.rounded())
                sessionCount += 1
            }
        }
        let hours = Double(visitSeconds) / 3600.0
        let netPerHour: Double? = hours > 0 ? net / hours : nil
        return TimeStats(
            totalVisitSeconds: visitSeconds,
            totalSessionSeconds: sessionSeconds,
            visitCount: visits.count,
            sessionCount: sessionCount,
            netPerHour: netPerHour
        )
    }

    private static func machineRanks(_ visits: [Visit]) -> [MachineRank] {
        struct Acc {
            var sessions = 0
            var net = 0.0
            var amountIn = 0.0
            var bonusCount = 0
            var bonusWin = 0.0
            var bonusBet = 0.0
            var durationSeconds = 0
            var recentNets: [Double] = []
            var machine: Machine?
        }
        var map: [String: Acc] = [:]
        let sessions = visits.flatMap(\.sessions).sorted { $0.startedAt < $1.startedAt }
        for s in sessions {
            var a = map[s.machineName] ?? Acc()
            a.sessions += 1
            a.net += s.sessionNet
            a.amountIn += s.amountIn
            a.bonusCount += s.bonuses.count
            a.durationSeconds += Int(s.effectiveDuration.rounded())
            for b in s.bonuses {
                a.bonusWin += b.winAmount
                if let bet = b.betAmount, bet > 0 { a.bonusBet += bet }
            }
            a.recentNets.append(s.sessionNet)
            if a.recentNets.count > 3 { a.recentNets.removeFirst(a.recentNets.count - 3) }
            if a.machine == nil {
                a.machine = s.catalogMachine
            }
            map[s.machineName] = a
        }
        return map.map { name, a in
            let hot = a.recentNets.count == 3 && a.recentNets.allSatisfy { $0 > 0 }
            let mult: Double? = {
                if a.bonusBet > 0 {
                    return MoneyMath.multiplier(win: a.bonusWin, bet: a.bonusBet)
                }
                return MoneyMath.multiplier(win: a.net, bet: a.amountIn > 0 ? a.amountIn : nil)
            }()
            let hours = Double(a.durationSeconds) / 3600.0
            let eph: Double? = hours > 0 ? a.net / hours : nil
            return MachineRank(
                name: name,
                sessions: a.sessions,
                net: a.net,
                amountIn: a.amountIn,
                bonusCount: a.bonusCount,
                multiplier: mult,
                hot: hot,
                durationSeconds: a.durationSeconds,
                euroPerHour: eph,
                machine: a.machine
            )
        }
        .sorted { $0.net > $1.net }
    }

    private static func bonusRanks(_ visits: [Visit]) -> [BonusRank] {
        struct Acc { var count = 0; var win = 0.0; var bet = 0.0; var color = "#cea658" }
        var map: [String: Acc] = [:]
        var totalWin = 0.0
        for v in visits {
            for s in v.sessions {
                for b in s.bonuses {
                    totalWin += b.winAmount
                    let label = b.types.map(\.name).sorted().joined(separator: " + ")
                    let key = label.isEmpty ? "Autre" : label
                    var a = map[key] ?? Acc()
                    a.count += 1
                    a.win += b.winAmount
                    if let bet = b.betAmount, bet > 0 { a.bet += bet }
                    if let c = b.types.first?.colorHex { a.color = c }
                    map[key] = a
                }
            }
        }
        return map.map { name, a in
            BonusRank(
                name: name,
                colorHex: a.color,
                count: a.count,
                winTotal: a.win,
                betTotal: a.bet,
                avgMult: a.bet > 0 ? a.win / a.bet : nil,
                winShare: totalWin > 0 ? a.win / totalWin : 0
            )
        }
        .sorted { $0.winTotal > $1.winTotal }
    }

    private static func comboRanks(_ visits: [Visit]) -> [ComboRank] {
        var simple = (0, 0.0, 0.0)
        var double = (0, 0.0, 0.0)
        var triple = (0, 0.0, 0.0)
        for v in visits {
            for s in v.sessions {
                for b in s.bonuses {
                    let n = max(b.types.count, 1)
                    let bet = (b.betAmount ?? 0) > 0 ? (b.betAmount ?? 0) : 0
                    if n <= 1 {
                        simple.0 += 1; simple.1 += b.winAmount; simple.2 += bet
                    } else if n == 2 {
                        double.0 += 1; double.1 += b.winAmount; double.2 += bet
                    } else {
                        triple.0 += 1; triple.1 += b.winAmount; triple.2 += bet
                    }
                }
            }
        }
        func row(_ key: String, _ label: String, _ t: (Int, Double, Double)) -> ComboRank {
            ComboRank(key: key, label: label, count: t.0, winTotal: t.1, avgMult: t.2 > 0 ? t.1 / t.2 : nil)
        }
        return [
            row("simple", "Simple", simple),
            row("double", "Double", double),
            row("triple", "Triple", triple),
        ]
    }

    private static func casinoRanks(_ visits: [Visit]) -> [CasinoRank] {
        var map: [String: (Int, Double, Double, Double, Int)] = [:]
        for v in visits {
            let name = v.casino?.name ?? "-"
            var t = map[name] ?? (0, 0, 0, 0, 0)
            t.0 += 1
            t.1 += v.net ?? 0
            t.2 += v.cashExpense
            t.3 += v.reinvested
            t.4 += Int(v.effectiveDuration.rounded())
            map[name] = t
        }
        return map.map {
            CasinoRank(
                name: $0.key,
                visits: $0.value.0,
                net: $0.value.1,
                pocket: $0.value.2,
                reinvested: $0.value.3,
                durationSeconds: $0.value.4
            )
        }
        .sorted { $0.net > $1.net }
    }

    private static func distributions(
        bankroll: BankrollStats,
        visits: [Visit],
        bonuses: [BonusRank],
        casinos: [CasinoRank],
        machines: [MachineRank]
    ) -> DistributionStats {
        let spendBySource: [DistSlice] = [
            DistSlice(key: "cb", value: bankroll.cb, colorHex: nil),
            DistSlice(key: "liquide", value: bankroll.liquide, colorHex: nil),
        ].filter { $0.value > 0 }

        let capitalFlow: [DistSlice] = [
            DistSlice(key: "pocket", value: bankroll.pocket, colorHex: nil),
            DistSlice(key: "reinvested", value: bankroll.reinvested, colorHex: nil),
        ].filter { $0.value > 0 }

        var winSum = 0.0
        var lossSum = 0.0
        for v in visits {
            guard let n = v.net else { continue }
            if n > 0 {
                winSum += n
            } else if n < 0 {
                lossSum += abs(n)
            }
        }
        let visitResults: [DistSlice] = [
            DistSlice(key: "wins", value: winSum, colorHex: nil),
            DistSlice(key: "losses", value: lossSum, colorHex: nil),
        ].filter { $0.value > 0 }

        var winSessions = 0.0
        var lossSessions = 0.0
        for v in visits {
            for s in v.sessions {
                let n = s.sessionNet
                if n > 0 { winSessions += 1 }
                else if n < 0 { lossSessions += 1 }
            }
        }
        let sessionResultsCount: [DistSlice] = [
            DistSlice(key: "wins", value: winSessions, colorHex: nil),
            DistSlice(key: "losses", value: lossSessions, colorHex: nil),
        ].filter { $0.value > 0 }

        let bonusItems = bonuses.map { ($0.name, $0.winTotal, $0.colorHex as String?) }
        let bonusByType = topNPlusOther(bonusItems, n: 5, otherKey: "autres")

        let casinoItems = casinos.map { ($0.name, $0.pocket, nil as String?) }
        let spendByCasino = topNPlusOther(casinoItems, n: 4, otherKey: "autres")

        let amountInItems = machines
            .filter { $0.amountIn > 0 }
            .map { ($0.name, $0.amountIn, nil as String?) }
        let amountInByMachine = topNPlusOther(amountInItems, n: 5, otherKey: "autres")

        return DistributionStats(
            spendBySource: spendBySource,
            capitalFlow: capitalFlow,
            visitResults: visitResults,
            sessionResultsCount: sessionResultsCount,
            bonusByType: bonusByType,
            spendByCasino: spendByCasino,
            amountInByMachine: amountInByMachine
        )
    }

    private static func topNPlusOther(
        _ items: [(String, Double, String?)],
        n: Int,
        otherKey: String
    ) -> [DistSlice] {
        let sorted = items.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        guard !sorted.isEmpty else { return [] }
        if sorted.count <= n {
            return sorted.map { DistSlice(key: $0.0, value: $0.1, colorHex: $0.2) }
        }
        let top = Array(sorted.prefix(n))
        let rest = sorted.dropFirst(n).reduce(0.0) { $0 + $1.1 }
        var slices = top.map { DistSlice(key: $0.0, value: $0.1, colorHex: $0.2) }
        if rest > 0 {
            slices.append(DistSlice(key: otherKey, value: rest, colorHex: nil))
        }
        return slices
    }

    private static func cumulative(_ visits: [Visit]) -> [CumulativeNetPoint] {
        var sum = 0.0
        var out: [CumulativeNetPoint] = []
        for (i, v) in visits.enumerated() {
            sum += v.net ?? 0
            out.append(CumulativeNetPoint(date: v.startedAt, net: sum, index: i))
        }
        return out
    }

    private static func monthlyBars(_ visits: [Visit]) -> [MonthlyBarPoint] {
        let cal = CTDates.calendar
        var map: [String: (Date, Double, Double, Double)] = [:]
        let formatter = DateFormatter()
        formatter.locale = CTDates.fr
        formatter.timeZone = CTDates.tz
        formatter.dateFormat = "MMM yy"

        for v in visits {
            let comps = cal.dateComponents([.year, .month], from: v.startedAt)
            guard let monthStart = cal.date(from: comps) else { continue }
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            var t = map[key] ?? (monthStart, 0, 0, 0)
            t.1 += v.cashExpense
            t.2 += v.effectiveGains ?? 0
            t.3 += v.net ?? 0
            map[key] = t
        }

        return map.keys.sorted().compactMap { key in
            guard let t = map[key] else { return nil }
            return MonthlyBarPoint(
                monthKey: key,
                label: formatter.string(from: t.0),
                spent: t.1,
                gains: t.2,
                net: t.3
            )
        }
    }

    private static func streak(_ visits: [Visit], winning: Bool) -> Int {
        let closed = visits.filter { $0.net != nil }.sorted { $0.startedAt > $1.startedAt }
        var n = 0
        for v in closed {
            let win = (v.net ?? 0) > 0
            if win == winning { n += 1 } else { break }
        }
        return n
    }

    private static func typeBreakdown(_ visits: [Visit]) -> [(String, Int, Double)] {
        var map: [String: (Int, Double)] = [:]
        for v in visits {
            for s in v.sessions {
                let name = s.machineType?.name ?? s.catalogMachine?.machineType?.name ?? "Autre"
                var t = map[name] ?? (0, 0)
                t.0 += 1
                t.1 += s.sessionNet
                map[name] = t
            }
        }
        return map.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.2 > $1.2 }
    }

    private static func globalBonusMult(_ visits: [Visit]) -> Double? {
        var win = 0.0, bet = 0.0
        for v in visits {
            for s in v.sessions {
                for b in s.bonuses {
                    if let m = b.betAmount, m > 0 {
                        win += b.winAmount
                        bet += m
                    }
                }
            }
        }
        return bet > 0 ? win / bet : nil
    }

    private static func bestBonus(_ visits: [Visit]) -> (win: Double, mult: Double?, machine: String, date: Date)? {
        var best: (Double, Double?, String, Date)?
        for v in visits {
            for s in v.sessions {
                for b in s.bonuses {
                    if best == nil || b.winAmount > best!.0 {
                        best = (b.winAmount, b.multiplier, s.machineName, b.at)
                    }
                }
            }
        }
        return best.map { ($0.0, $0.1, $0.2, $0.3) }
    }
}
