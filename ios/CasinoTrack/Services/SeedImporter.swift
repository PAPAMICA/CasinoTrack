import Foundation
import SwiftData

enum SeedImporter {
    /// Nouveau flag après activation CloudKit (nouveau store)
    private static let flagKey = "seed.imported.cloud.v1"

    static func runIfNeeded(container: ModelContainer) {
        let context = ModelContext(container)
        // Avec iCloud : ne pas reseeder si des données existent déjà (sync ou install précédente)
        let hasData: Bool = {
            let casinos = (try? context.fetchCount(FetchDescriptor<Casino>())) ?? 0
            let visits = (try? context.fetchCount(FetchDescriptor<Visit>())) ?? 0
            let machines = (try? context.fetchCount(FetchDescriptor<Machine>())) ?? 0
            return casinos + visits + machines > 0
        }()
        if hasData {
            UserDefaults.standard.set(true, forKey: flagKey)
            ensureExtraBonusTypes(container: container)
            migrateBudgetSources(container: container)
            migrateOct27VisitFunding(container: container)
            migrateOct27VisitExitGains(container: container)
            migrateOct28VisitClose(container: container)
            return
        }
        if UserDefaults.standard.bool(forKey: flagKey) {
            ensureExtraBonusTypes(container: container)
            migrateBudgetSources(container: container)
            migrateOct27VisitFunding(container: container)
            migrateOct27VisitExitGains(container: container)
            migrateOct28VisitClose(container: container)
            return
        }
        do {
            try importSeed(into: context)
            try context.save()
            UserDefaults.standard.set(true, forKey: flagKey)
            migrateBudgetSources(container: container)
            migrateOct27VisitFunding(container: container)
            migrateOct27VisitExitGains(container: container)
            migrateOct28VisitClose(container: container)
        } catch {
            print("Seed import failed: \(error)")
        }
    }

    /// Normalise `gain` → `fromPrevious` sur les BudgetEntry existantes.
    private static func migrateBudgetSources(container: ModelContainer) {
        let key = "migrate.budgetSource.fromPrevious.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let context = ModelContext(container)
        let entries = (try? context.fetch(FetchDescriptor<BudgetEntry>())) ?? []
        var changed = false
        for entry in entries where entry.source == "gain" {
            entry.source = BudgetSource.fromPrevious.rawValue
            changed = true
        }
        if changed { try? context.save() }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Corrige la sortie du 27 oct (Europe/Paris) : Budget 400 + CB 200 (cagnotte 600).
    private static func migrateOct27VisitFunding(container: ModelContainer) {
        let key = "migrate.oct27.potFunding.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let context = ModelContext(container)
        let visits = (try? context.fetch(FetchDescriptor<Visit>())) ?? []
        let cal = CTDates.calendar
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 27
        guard let dayStart = cal.date(from: comps),
              let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        let targets = visits.filter { $0.startedAt >= dayStart && $0.startedAt < dayEnd }
        for visit in targets {
            // Ne corriger que si l’ancienne forme « un seul gain/fromPrevious ~450 » est encore là,
            // ou un seul planned sans CB 200.
            let funding = visit.budgets.filter { !$0.isCagnotteWithdraw && $0.linkedSession == nil }
            let hasCB200 = funding.contains {
                BudgetSource.parse($0.source) == .cb && abs($0.amount - 200) < 0.01
            }
            let hasBudget400 = funding.contains {
                BudgetSource.parse($0.source) == .fromPrevious && abs($0.amount - 400) < 0.01
            }
            if hasCB200 && hasBudget400 {
                visit.plannedBudget = 600
                continue
            }

            // Remplace les alimentations non liées par Budget 400 + CB 200.
            for entry in funding {
                context.delete(entry)
            }
            let at = visit.startedAt
            context.insert(BudgetEntry(
                kind: "planned",
                amount: 400,
                source: BudgetSource.fromPrevious.rawValue,
                at: at,
                note: "Budget (gains précédents)",
                visit: visit
            ))
            context.insert(BudgetEntry(
                kind: "planned",
                amount: 200,
                source: BudgetSource.cb.rawValue,
                at: at,
                note: "CB",
                visit: visit
            ))
            visit.plannedBudget = 600
            // Conserve manualTotalWin s’il existe ; sinon aligne sur cagnotte.
            if visit.manualTotalWin == nil {
                visit.syncGainsFromCagnotte()
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Corrige les gains de sortie du 27 oct : argent sorti = 700 € (net 100).
    /// Ne touche que si l’override manuel est encore à 1000 (ancienne erreur seed).
    private static func migrateOct27VisitExitGains(container: ModelContainer) {
        let key = "migrate.oct27.exitGains700.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let context = ModelContext(container)
        let visits = (try? context.fetch(FetchDescriptor<Visit>())) ?? []
        let cal = CTDates.calendar
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 27
        guard let dayStart = cal.date(from: comps),
              let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        let targets = visits.filter { $0.startedAt >= dayStart && $0.startedAt < dayEnd }
        for visit in targets {
            if let win = visit.manualTotalWin, abs(win - 1000) < 0.01 {
                visit.manualTotalWin = 700
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Clôture la sortie Divonne 400+200 au **28 oct 2026** (calendrier user) :
    /// CB 200, Budget 400, Liquide 0, cagnotte/gains 700, net +100.
    private static func migrateOct28VisitClose(container: ModelContainer) {
        let key = "migrate.oct28.close.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let context = ModelContext(container)
        let visits = (try? context.fetch(FetchDescriptor<Visit>())) ?? []
        let cal = CTDates.calendar

        func dayBounds(_ day: Int) -> (Date, Date)? {
            var comps = DateComponents()
            comps.year = 2026
            comps.month = 10
            comps.day = day
            guard let start = cal.date(from: comps),
                  let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
            return (start, end)
        }

        guard let (d27s, d27e) = dayBounds(27),
              let (d28s, d28e) = dayBounds(28) else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        func potFunding(_ visit: Visit) -> [BudgetEntry] {
            visit.budgets.filter { !$0.isCagnotteWithdraw && $0.linkedSession == nil }
        }

        func matchesScenario(_ visit: Visit) -> Bool {
            let funding = potFunding(visit)
            let hasCB200 = funding.contains {
                BudgetSource.parse($0.source) == .cb && abs($0.amount - 200) < 0.01
            }
            let hasBudget400 = funding.contains {
                BudgetSource.parse($0.source) == .fromPrevious && abs($0.amount - 400) < 0.01
            }
            if hasCB200 && hasBudget400 { return true }
            let name = visit.casino?.name ?? ""
            guard name.localizedCaseInsensitiveContains("Divonne") else { return false }
            if abs(visit.plannedBudget - 600) < 0.01 { return true }
            if let win = visit.manualTotalWin, abs(win - 700) < 0.01 || abs(win - 1000) < 0.01 {
                return true
            }
            return false
        }

        let on27 = visits.filter { $0.startedAt >= d27s && $0.startedAt < d27e && matchesScenario($0) }
        let on28 = visits.filter { $0.startedAt >= d28s && $0.startedAt < d28e && matchesScenario($0) }
        // Deux sorties distinctes → fixer celle du 28 ; sinon décaler le 27 → 28.
        let targets = on28.isEmpty ? on27 : on28
        let dayDelta: TimeInterval = 24 * 3600

        for visit in targets {
            if visit.startedAt >= d27s && visit.startedAt < d27e {
                visit.startedAt = visit.startedAt.addingTimeInterval(dayDelta)
                if let ended = visit.endedAt {
                    visit.endedAt = ended.addingTimeInterval(dayDelta)
                }
                for entry in visit.budgets {
                    entry.at = entry.at.addingTimeInterval(dayDelta)
                }
                for session in visit.sessions {
                    session.startedAt = session.startedAt.addingTimeInterval(dayDelta)
                    if let ended = session.endedAt {
                        session.endedAt = ended.addingTimeInterval(dayDelta)
                    }
                    for bonus in session.bonuses {
                        bonus.at = bonus.at.addingTimeInterval(dayDelta)
                    }
                }
            }

            let funding = potFunding(visit)
            let hasCB200 = funding.contains {
                BudgetSource.parse($0.source) == .cb && abs($0.amount - 200) < 0.01
            }
            let hasBudget400 = funding.contains {
                BudgetSource.parse($0.source) == .fromPrevious && abs($0.amount - 400) < 0.01
            }
            if hasCB200 && hasBudget400 {
                for entry in funding where BudgetSource.parse(entry.source) == .liquide {
                    context.delete(entry)
                }
            } else {
                for entry in funding {
                    context.delete(entry)
                }
                let at = visit.startedAt
                context.insert(BudgetEntry(
                    kind: "planned",
                    amount: 400,
                    source: BudgetSource.fromPrevious.rawValue,
                    at: at,
                    note: "Budget (gains précédents)",
                    visit: visit
                ))
                context.insert(BudgetEntry(
                    kind: "planned",
                    amount: 200,
                    source: BudgetSource.cb.rawValue,
                    at: at,
                    note: "CB",
                    visit: visit
                ))
            }

            visit.plannedBudget = 600
            visit.manualTotalWin = 700
            if visit.endedAt == nil {
                let duration = max(visit.effectiveDuration, 1)
                visit.endedAt = visit.startedAt.addingTimeInterval(duration)
            }
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    private static func ensureExtraBonusTypes(container: ModelContainer) {
        let context = ModelContext(container)
        let extras: [(String, String, Int)] = [
            ("Yummy", "#22c55e", 20),
            ("Upsized", "#ef4444", 21),
            ("Spicy", "#a855f7", 22),
            ("Boost", "#16a34a", 23),
            ("Rise", "#dc2626", 24),
            ("Catch", "#eab308", 25),
        ]
        for (name, color, order) in extras {
            let pred = #Predicate<BonusType> { $0.name == name }
            let existing = try? context.fetch(FetchDescriptor(predicate: pred))
            if existing?.isEmpty != false {
                context.insert(BonusType(name: name, sortOrder: order, colorHex: color))
            }
        }
        try? context.save()
    }

    private static func importSeed(into context: ModelContext) throws {
        guard let url = Self.seedURL() else { throw SeedError.missingFile }
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        var machineTypesByLegacy: [Int: MachineType] = [:]
        var bonusTypesByLegacy: [Int: BonusType] = [:]
        var bonusTypesByName: [String: BonusType] = [:]
        var casinosByLegacy: [Int: Casino] = [:]
        var machinesByLegacy: [Int: Machine] = [:]

        if let types = root["types"] as? [String: Any] {
            for row in (types["machineTypes"] as? [[String: Any]]) ?? [] {
                let id = int(row["id"])
                let mt = MachineType(
                    legacyId: id,
                    name: string(row["name"]) ?? "Autre",
                    sortOrder: int(row["sort_order"]) ?? 0
                )
                context.insert(mt)
                if let id { machineTypesByLegacy[id] = mt }
            }
            for row in (types["bonusTypes"] as? [[String: Any]]) ?? [] {
                let id = int(row["id"])
                let name = string(row["name"]) ?? "Autre"
                let bt = BonusType(
                    legacyId: id,
                    name: name,
                    sortOrder: int(row["sort_order"]) ?? 0,
                    colorHex: string(row["color"]) ?? "#cea658"
                )
                context.insert(bt)
                if let id { bonusTypesByLegacy[id] = bt }
                bonusTypesByName[name] = bt
            }
        }

        for row in (root["extra_bonus_types"] as? [[String: Any]]) ?? [] {
            guard let name = string(row["name"]), !name.isEmpty else { continue }
            guard bonusTypesByName[name] == nil else { continue }
            let bt = BonusType(
                name: name,
                sortOrder: int(row["sort_order"]) ?? 99,
                colorHex: string(row["color"]) ?? "#cea658"
            )
            context.insert(bt)
            bonusTypesByName[name] = bt
        }

        for row in (root["casinos"] as? [[String: Any]]) ?? [] {
            let id = int(row["id"])
            let casino = Casino(
                legacyId: id,
                name: string(row["name"]) ?? "Casino",
                address: string(row["address"]),
                city: string(row["city"]),
                lat: double(row["lat"]),
                lon: double(row["lon"]),
                website: string(row["website"]),
                source: string(row["source"]) ?? "seed",
                isFavorite: bool(row["is_favorite"]),
                createdAt: date(row["created_at"]) ?? .now
            )
            context.insert(casino)
            if let id { casinosByLegacy[id] = casino }
        }

        for row in (root["machines"] as? [[String: Any]]) ?? [] {
            let id = int(row["id"])
            let photo = string(row["photo_path"])
            let photoData = photo.flatMap { PhotoStore.dataFromBundleOrDisk(relativePath: $0) }
            let machine = Machine(
                legacyId: id,
                name: string(row["name"]) ?? "Machine",
                manufacturer: string(row["manufacturer"]),
                photoPath: photo,
                photoData: photoData,
                defaultBet: double(row["default_bet"]),
                bonusFeatures: string(row["bonus_features"]),
                hasJackpot: bool(row["has_jackpot"]),
                isFavorite: bool(row["is_favorite"]),
                notes: string(row["notes"]),
                createdAt: date(row["created_at"]) ?? .now,
                machineType: int(row["machine_type_id"]).flatMap { machineTypesByLegacy[$0] }
            )
            if let ids = row["bonus_type_ids"] as? [Any] {
                machine.bonusTypes = ids.compactMap { int($0).flatMap { bonusTypesByLegacy[$0] } }
            }
            if let ids = row["casino_ids"] as? [Any] {
                machine.casinos = ids.compactMap { int($0).flatMap { casinosByLegacy[$0] } }
            }
            context.insert(machine)
            if let id { machinesByLegacy[id] = machine }
        }

        for row in (root["visits"] as? [[String: Any]]) ?? [] {
            let id = int(row["id"])
            let casino = int(row["casino_id"]).flatMap { casinosByLegacy[$0] }
            let visit = Visit(
                legacyId: id,
                startedAt: date(row["started_at"]) ?? .now,
                endedAt: date(row["ended_at"]),
                plannedBudget: double(row["planned_budget"]) ?? 0,
                manualTotalWin: double(row["manual_total_win"]),
                notes: string(row["notes"]),
                createdAt: date(row["created_at"]) ?? .now,
                casino: casino
            )
            context.insert(visit)

            for b in (row["budgets"] as? [[String: Any]]) ?? [] {
                let rawSource = string(b["source"]) ?? "liquide"
                let normalizedSource: String = {
                    if rawSource == "gain" { return BudgetSource.fromPrevious.rawValue }
                    if rawSource == MoneyMath.cagnotteSourceRaw { return rawSource }
                    return BudgetSource.parse(rawSource).rawValue
                }()
                let entry = BudgetEntry(
                    kind: string(b["kind"]) ?? "planned",
                    amount: double(b["amount"]) ?? 0,
                    source: normalizedSource,
                    at: date(b["at"]) ?? visit.startedAt,
                    note: string(b["note"]),
                    visit: visit
                )
                context.insert(entry)
            }

            for s in (row["sessions"] as? [[String: Any]]) ?? [] {
                let session = MachineSession(
                    legacyId: int(s["id"]),
                    machineName: string(s["machine_name"]) ?? "Machine",
                    amountIn: double(s["amount_in"]) ?? 0,
                    betSetting: double(s["bet_setting"]),
                    cashOut: double(s["cash_out"]),
                    startedAt: date(s["started_at"]) ?? visit.startedAt,
                    notes: string(s["notes"]),
                    visit: visit,
                    machineType: int(s["machine_type_id"]).flatMap { machineTypesByLegacy[$0] },
                    catalogMachine: int(s["catalog_machine_id"]).flatMap { machinesByLegacy[$0] }
                )
                context.insert(session)

                for b in (s["bonuses"] as? [[String: Any]]) ?? [] {
                    let photo = string(b["photo_path"])
                    let photoData = photo.flatMap { PhotoStore.dataFromBundleOrDisk(relativePath: $0) }
                    var linked: [BonusType] = []
                    if let types = b["types"] as? [[String: Any]] {
                        linked = types.compactMap { t in
                            if let id = int(t["id"]), let bt = bonusTypesByLegacy[id] { return bt }
                            if let name = string(t["name"]), let bt = bonusTypesByName[name] { return bt }
                            return nil
                        }
                    } else if let ids = b["bonus_type_ids"] as? [Any] {
                        linked = ids.compactMap { int($0).flatMap { bonusTypesByLegacy[$0] } }
                    } else if let id = int(b["bonus_type_id"]) {
                        if let bt = bonusTypesByLegacy[id] { linked = [bt] }
                    }
                    let event = BonusEvent(
                        legacyId: int(b["id"]),
                        winAmount: double(b["win_amount"]) ?? 0,
                        betAmount: double(b["bet_amount"]),
                        label: string(b["label"]),
                        photoPath: photo,
                        photoData: photoData,
                        at: date(b["at"]) ?? session.startedAt,
                        session: session,
                        types: linked
                    )
                    context.insert(event)
                }
            }
        }
    }

    private static func seedURL() -> URL? {
        if let u = Bundle.main.url(forResource: "seed", withExtension: "json", subdirectory: "SeedData") {
            return u
        }
        if let u = Bundle.main.url(forResource: "seed", withExtension: "json") {
            return u
        }
        if let root = Bundle.main.resourceURL {
            let candidate = root.appendingPathComponent("SeedData/seed.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func string(_ any: Any?) -> String? {
        guard let any, !(any is NSNull) else { return nil }
        if let s = any as? String { return s }
        return String(describing: any)
    }

    private static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        if let d = any as? Double { return Int(d) }
        return nil
    }

    private static func double(_ any: Any?) -> Double? {
        if any is NSNull || any == nil { return nil }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String {
            let cleaned = s.replacingOccurrences(of: ",", with: ".")
            return Double(cleaned)
        }
        return nil
    }

    private static func bool(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }

    private static func date(_ any: Any?) -> Date? {
        guard let s = string(any) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    enum SeedError: Error { case missingFile }
}
