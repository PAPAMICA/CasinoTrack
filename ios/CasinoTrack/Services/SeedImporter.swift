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
            return
        }
        if UserDefaults.standard.bool(forKey: flagKey) {
            ensureExtraBonusTypes(container: container)
            return
        }
        do {
            try importSeed(into: context)
            try context.save()
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            print("Seed import failed: \(error)")
        }
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
                let entry = BudgetEntry(
                    kind: string(b["kind"]) ?? "planned",
                    amount: double(b["amount"]) ?? 0,
                    source: string(b["source"]) ?? "liquide",
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
