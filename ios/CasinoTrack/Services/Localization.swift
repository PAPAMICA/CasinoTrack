import Foundation
import Observation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case fr
    case en

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .fr: Locale(identifier: "fr_FR")
        case .en: Locale(identifier: "en_US")
        }
    }

    var displayName: String {
        switch self {
        case .fr: "Français"
        case .en: "English"
        }
    }

    var shortCode: String {
        switch self {
        case .fr: "FR"
        case .en: "EN"
        }
    }
}

@Observable
@MainActor
final class LanguageStore {
    static let shared = LanguageStore()

    private static let storageKey = "appLanguage"

    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    var t: L10n { L10n(language) }
    var locale: Locale { language.locale }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.fr.rawValue
        language = AppLanguage(rawValue: raw) ?? .fr
    }
}

struct L10n {
    let language: AppLanguage

    init(_ language: AppLanguage) {
        self.language = language
    }

    private func t(_ fr: String, _ en: String) -> String {
        language == .fr ? fr : en
    }

    // MARK: - Tabs & common

    var tabFloor: String { t("Floor", "Floor") }
    var tabVisits: String { t("Sorties", "Visits") }
    var tabCatalog: String { t("Catalogue", "Catalog") }
    var tabStats: String { t("Stats", "Stats") }

    var ok: String { t("OK", "OK") }
    var cancel: String { t("Annuler", "Cancel") }
    var close: String { t("Fermer", "Close") }
    var delete: String { t("Supprimer", "Delete") }
    var save: String { t("Enregistrer", "Save") }
    var edit: String { t("Modifier", "Edit") }
    var add: String { t("Ajouter", "Add") }
    var search: String { t("Rechercher", "Search") }
    var optional: String { t("Optionnel", "Optional") }
    var notes: String { t("Notes", "Notes") }
    var date: String { t("Date", "Date") }
    var none: String { t("Aucune", "None") }
    var all: String { t("Tous", "All") }
    var casino: String { t("Casino", "Casino") }
    var machine: String { t("Machine", "Machine") }
    var machines: String { t("Machines", "Machines") }
    var casinos: String { t("Casinos", "Casinos") }
    var bonus: String { t("Bonus", "Bonus") }
    var session: String { t("Session", "Session") }
    var sessions: String { t("Sessions", "Sessions") }
    var budget: String { t("Budget", "Budget") }
    var gains: String { t("Gains", "Winnings") }
    var capital: String { t("Capital", "Capital") }
    var time: String { t("Temps", "Time") }
    var net: String { "NET" }
    var type: String { t("Type", "Type") }
    var validate: String { t("Valider", "Confirm") }
    var sourceCB: String { "CB" }
    var sourceCash: String { t("Liquide", "Cash") }
    var sourceReinvested: String { t("Réinvesti", "Reinvested") }
    var sourceReinvestedShort: String { t("Réinv.", "Reinv.") }
    var budgetDash: String { t("Budget -", "Budget -") }
    var statusLive: String { t("En cours", "Live") }
    var statusDone: String { t("Terminée", "Done") }
    var netFormula: String { t("Net = gains − poche − réinvesti", "Net = winnings − pocket − reinvested") }

    // MARK: - Settings

    var settingsTitle: String { t("Réglages", "Settings") }
    var settingsLanguage: String { t("Langue", "Language") }
    var settingsLanguageFooter: String {
        t(
            "Change l’affichage de l’app immédiatement. Indépendant de la langue du système.",
            "Changes the app language immediately. Independent from the system language."
        )
    }
    var settingsSync: String { "Sync" }
    var settingsICloudBackup: String { t("Sauvegarde iCloud", "iCloud Backup") }
    var settingsLocalData: String { t("Données locales", "Local data") }
    var settingsAbout: String { t("À propos", "About") }
    var settingsApp: String { "App" }
    var settingsVersion: String { t("Version", "Version") }
    var settingsContainer: String { t("Conteneur", "Container") }
    var settingsSyncHelpActive: String {
        t(
            "Tes sorties, machines, casinos et photos se synchronisent automatiquement avec ton Apple ID dès qu’une connexion est dispo. Au casino hors ligne, tout reste utilisable en local.",
            "Your visits, machines, casinos and photos sync automatically with your Apple ID when online. Offline at the casino, everything still works locally."
        )
    }
    var settingsSyncHelpLocal: String {
        t(
            "Les données restent sur cet appareil. La sync iCloud nécessite un compte Apple Developer payant avec la capability CloudKit activée.",
            "Data stays on this device. iCloud sync requires a paid Apple Developer account with the CloudKit capability enabled."
        )
    }
    var syncActive: String { t("iCloud actif - sync automatique", "iCloud active — automatic sync") }
    var syncLocalOnly: String {
        t(
            "Stockage local (iCloud non provisionné sur ce build)",
            "Local storage (iCloud not provisioned on this build)"
        )
    }
    var syncUnavailable: String { t("Sync indisponible", "Sync unavailable") }

    // MARK: - Floor

    var floorTagline: String { t("Des gains, des pertes, des stats.", "Wins, losses, stats.") }
    var floorNewVisit: String { t("Nouvelle sortie", "New visit") }
    var floorLastVisit: String { t("Dernière sortie", "Last visit") }
    var floorSpent: String { t("Dépensé", "Spent") }
    var floorSpentHint: String { t("CB + Liquide", "Card + Cash") }
    var floorNetGain: String { t("Gain net", "Net profit") }
    var floorNetGainHint: String { t("Toutes sorties", "All visits") }
    var floorTotalMult: String { t("× total", "× total") }
    var floorTotalMultHint: String { t("Net / dépensé", "Net / spent") }

    // MARK: - History

    var historyEmptyTitle: String { t("Aucune sortie", "No visits") }
    var historyEmptyDescription: String {
        t("Démarre une sortie depuis Floor.", "Start a visit from Floor.")
    }
    var historyDeleteLiveTitle: String { t("Supprimer la sortie en cours ?", "Delete the live visit?") }
    var historyDeleteTitle: String { t("Supprimer cette sortie ?", "Delete this visit?") }
    var historyDeleteLiveMessage: String {
        t(
            "La sortie en cours et tout son contenu (sessions, budget, bonus, photos) seront définitivement effacés.",
            "The live visit and all its content (sessions, budget, bonuses, photos) will be permanently deleted."
        )
    }
    var historyDeleteMessage: String {
        t(
            "Sessions, budget, bonus et photos associés seront définitivement effacés.",
            "Associated sessions, budget, bonuses and photos will be permanently deleted."
        )
    }

    func sessionsCount(_ n: Int) -> String {
        switch language {
        case .fr: return "\(n) session\(n > 1 ? "s" : "")"
        case .en: return "\(n) session\(n == 1 ? "" : "s")"
        }
    }

    func visitsCount(_ n: Int) -> String {
        switch language {
        case .fr: return "\(n) sortie\(n > 1 ? "s" : "")"
        case .en: return "\(n) visit\(n == 1 ? "" : "s")"
        }
    }

    func photosCount(_ n: Int) -> String {
        switch language {
        case .fr: return "\(n) photo\(n > 1 ? "s" : "")"
        case .en: return "\(n) photo\(n == 1 ? "" : "s")"
        }
    }

    func timesCount(_ n: Int) -> String {
        switch language {
        case .fr: return "\(n) fois"
        case .en: return "\(n) time\(n == 1 ? "" : "s")"
        }
    }

    func capitalLabel(_ amount: String) -> String {
        t("Capital \(amount)", "Bankroll \(amount)")
    }

    func gainsLabel(_ amount: String) -> String {
        t("Gains \(amount)", "Winnings \(amount)")
    }

    // MARK: - New visit

    var newVisitTitle: String { t("Nouvelle sortie", "New visit") }
    var newVisitWhen: String { t("Quand", "When") }
    var newVisitStart: String { t("Démarrer", "Start") }
    var newVisitNoCasino: String { t("Aucun casino", "No casino") }
    var newVisitNoResult: String { t("Aucun résultat", "No results") }

    // MARK: - Visit detail

    var visitAddMachine: String { t("Ajouter une machine", "Add a machine") }
    var visitDelete: String { t("Supprimer la sortie", "Delete visit") }
    var visitDeleteA11y: String { t("Supprimer la sortie", "Delete visit") }
    var visitTopup: String { t("Recharge", "Top-up") }
    var visitClose: String { t("Clôturer", "Close out") }
    var visitReopen: String { t("Rouvrir", "Reopen") }
    var visitNoMachines: String { t("Aucune machine pour l’instant.", "No machines yet.") }
    var visitEditDurationA11y: String {
        t("Modifier la durée de la sortie", "Edit visit duration")
    }
    var visitBudgetA11y: String { t("Gérer le budget de la sortie", "Manage visit budget") }
    var visitBudgetHint: String {
        t(
            "Ouvre la liste des entrées CB, liquide et réinvesti",
            "Opens the list of card, cash and reinvested entries"
        )
    }
    var visitDeleteHint: String {
        t("Efface la sortie et ses données associées", "Deletes the visit and related data")
    }
    var visitBonusPhotoA11y: String { t("Voir la photo du bonus", "View bonus photo") }
    var visitSessionEditHint: String { t("Ouvre l’édition de la session", "Opens session editing") }
    var visitFinish: String { t("Terminer la sortie", "End visit") }
    var visitUpdate: String { t("Mettre à jour", "Update") }
    var visitGainsRemaining: String {
        t("Gains restants / total saisi", "Remaining winnings / entered total")
    }

    func visitMultiplierOnCapital(_ mult: String, _ capital: String) -> String {
        t(
            "\(mult) sur capital \(capital) · gains − poche − réinvesti",
            "\(mult) on bankroll \(capital) · winnings − pocket − reinvested"
        )
    }

    func inOut(inAmount: String, outAmount: String?) -> String {
        if let outAmount {
            return t("In \(inAmount) · Out \(outAmount)", "In \(inAmount) · Out \(outAmount)")
        }
        return t("In \(inAmount)", "In \(inAmount)")
    }

    // MARK: - Budget

    var budgetTitle: String { t("Budget sortie", "Visit budget") }
    var budgetTotals: String { t("Totaux", "Totals") }
    var budgetEntries: String { t("Entrées", "Entries") }
    var budgetEmpty: String { t("Aucune entrée budget.", "No budget entries.") }
    var budgetFooter: String {
        t(
            "Tape une ligne pour modifier le montant ou la source. Les recharges liées à une machine sont retirées automatiquement si tu supprimes la session.",
            "Tap a row to edit amount or source. Top-ups linked to a machine are removed automatically if you delete the session."
        )
    }
    var budgetNewEntry: String { t("Nouvelle entrée", "New entry") }
    var budgetEditEntry: String { t("Modifier", "Edit") }
    var budgetDeleteEntry: String { t("Supprimer cette entrée ?", "Delete this entry?") }
    var budgetAddA11y: String { t("Ajouter une entrée", "Add an entry") }
    var budgetInitial: String { t("Budget initial", "Initial budget") }
    var budgetLinkedMachine: String { t("Liée à une machine", "Linked to a machine") }
    var budgetKindPlanned: String { t("Budget initial", "Initial budget") }
    var budgetKindTopup: String { t("Recharge", "Top-up") }

    // MARK: - Session editor

    var sessionPickHint: String {
        t(
            "Choisis une machine pour ouvrir la session (argent, bonus, chronomètre).",
            "Pick a machine to open the session (money, bonuses, timer)."
        )
    }
    var sessionStart: String { t("Commencer", "Start") }
    var sessionFreeName: String { t("Ou nom libre", "Or free name") }
    var sessionSaveDetails: String { t("Enregistrer les détails", "Save details") }
    var sessionAddToMachine: String { t("Ajouter à la machine", "Add to machine") }
    var sessionCashOutTitle: String { t("Argent retiré en partant", "Cash out when leaving") }
    var sessionCashOutConfirm: String { t("Valider le retrait", "Confirm cash out") }
    var sessionAmountInTitle: String { t("Argent misé (total)", "Money put in (total)") }
    var sessionBetTitle: String { t("Mise", "Bet") }
    var sessionDeleteTitle: String { t("Supprimer cette session ?", "Delete this session?") }
    var sessionDeleteMessage: String {
        t(
            "Les recharges liées à cette machine seront aussi retirées du budget de la sortie.",
            "Top-ups linked to this machine will also be removed from the visit budget."
        )
    }
    var sessionDuration: String { t("Durée", "Duration") }
    var sessionActions: String { t("Actions", "Actions") }
    var sessionAddBonus: String { t("Ajouter un bonus", "Add a bonus") }
    var sessionAddBonusSub: String { t("Bonus déclenché", "Triggered bonus") }
    var sessionAddMoney: String { t("Rajouter de l’argent", "Add more money") }
    var sessionAddMoneySub: String { t("Ajouter à la machine", "Add to the machine") }
    var sessionLeaveMachine: String { t("Quitter la machine", "Leave machine") }
    var sessionLeaveMachineSub: String { t("Saisir le cash out", "Enter cash out") }
    var sessionMachineDetails: String { t("Machine, mise, notes", "Machine, bet, notes") }
    var sessionDeleteA11y: String { t("Supprimer la session", "Delete session") }
    var sessionPutIn: String { t("Mis", "In") }
    var sessionCashOut: String { t("Retrait", "Cash out") }
    var sessionNoBonus: String { t("Aucun bonus pour l’instant.", "No bonuses yet.") }
    var sessionDeleteBonusA11y: String { t("Supprimer le bonus", "Delete bonus") }
    var durationTitle: String { t("Durée", "Duration") }

    // MARK: - Bonus editor

    var bonusTypes: String { t("Types", "Types") }
    var bonusNoMachineTypes: String {
        t(
            "Aucun bonus lié à la machine - catalogue complet",
            "No bonuses linked to this machine — full catalog"
        )
    }
    var bonusWin: String { t("Gain", "Win") }
    var bonusBet: String { t("Mise du bonus", "Bonus bet") }
    var bonusSave: String { t("Enregistrer le bonus", "Save bonus") }
    var bonusCameraA11y: String { t("Appareil photo", "Camera") }
    var bonusLibraryA11y: String { t("Photothèque", "Photo library") }
    var bonusDeletePhotoA11y: String { t("Supprimer la photo", "Delete photo") }

    // MARK: - Catalog

    var catalogEmptyMachines: String { t("Aucune machine", "No machines") }
    var catalogEmptyMachinesSub: String { t("Ajoute une machine avec +.", "Add a machine with +.") }
    var catalogEmptyCasinos: String { t("Aucun casino", "No casinos") }
    var catalogEmptyCasinosSub: String { t("Ajoute un casino avec +.", "Add a casino with +.") }
    var catalogNoResult: String { t("Aucun résultat", "No results") }
    var catalogNoResultSub: String { t("Essaie une autre recherche.", "Try another search.") }
    var catalogAddMachineA11y: String { t("Ajouter une machine", "Add a machine") }
    var catalogAddCasinoA11y: String { t("Ajouter un casino", "Add a casino") }
    var catalogDeleteMachineTitle: String { t("Supprimer cette machine ?", "Delete this machine?") }
    var catalogDeleteCasinoTitle: String { t("Supprimer ce casino ?", "Delete this casino?") }
    func catalogDeleteMachineMessage(_ name: String) -> String {
        t("« \(name) » sera retirée du catalogue.", "“\(name)” will be removed from the catalog.")
    }
    func catalogDeleteCasinoMessage(_ name: String) -> String {
        t("« \(name) » sera retiré du catalogue.", "“\(name)” will be removed from the catalog.")
    }
    var catalogIdentity: String { t("Identité", "Identity") }
    var catalogName: String { t("Nom", "Name") }
    var catalogManufacturer: String { t("Fabricant", "Manufacturer") }
    var catalogFavorite: String { t("Favori", "Favorite") }
    var catalogNewMachine: String { t("Nouvelle machine", "New machine") }
    var catalogEditMachine: String { t("Éditer machine", "Edit machine") }
    var catalogDeleteMachineAction: String { t("Supprimer la machine", "Delete machine") }
    var catalogNewCasino: String { t("Nouveau casino", "New casino") }
    var catalogEditCasino: String { t("Éditer casino", "Edit casino") }
    var catalogDeleteCasinoAction: String { t("Supprimer le casino", "Delete casino") }
    var catalogCity: String { t("Ville", "City") }

    // MARK: - Stats

    var statsEmptyTitle: String { t("Pas encore de stats", "No stats yet") }
    var statsEmptySub: String {
        t(
            "Tes sorties alimenteront bankroll, graphiques et classements.",
            "Your visits will fill bankroll, charts and rankings."
        )
    }
    var statsBonusGalleryA11y: String { t("Galerie bonus", "Bonus gallery") }
    var statsPeriodAll: String { t("Tout", "All") }
    var statsPeriod30d: String { t("30 j", "30d") }
    var statsPeriodMonth: String { t("Mois", "Month") }
    var statsPeriodYear: String { t("Année", "Year") }
    var statsPeriodVisit: String { t("Sortie", "Visit") }
    var statsBankroll: String { "Bankroll" }
    var statsBankrollSub: String {
        t(
            "Argent sorti de la poche vs gains des sorties",
            "Money from your pocket vs visit winnings"
        )
    }
    func statsNetSubtitle(_ visits: Int) -> String {
        let count = visitsCount(visits)
        return t("\(count) · gain/perte net", "\(count) · net win/loss")
    }
    var statsSpent: String { t("Dépensé", "Spent") }
    var statsSpentHint: String { t("CB + Liquide", "Card + Cash") }
    var statsReinvested: String { t("Réinvesti", "Reinvested") }
    var statsReinvestedHint: String { t("Gains remis", "Winnings put back") }
    var statsGainsHint: String { t("Total encaissé", "Total cashed") }
    var statsPocketROI: String { t("× net / dépensé", "× net / spent") }
    var statsPocketROIHint: String { t("Gain net ÷ (CB + Liquide)", "Net ÷ (Card + Cash)") }
    var statsReinvestRate: String { t("Taux réinvesti", "Reinvest rate") }
    var statsReinvestRateHint: String {
        t("Réinvesti ÷ (dépensé + réinv.)", "Reinvested ÷ (spent + reinv.)")
    }
    func statsBest(_ amount: String) -> String { t("Meilleure \(amount)", "Best \(amount)") }
    func statsWorst(_ amount: String) -> String { t("Pire \(amount)", "Worst \(amount)") }
    func statsWinStreak(_ n: Int) -> String { t("Streak gagnante : \(n)", "Winning streak: \(n)") }
    func statsLoseStreak(_ n: Int) -> String { t("Streak perdante : \(n)", "Losing streak: \(n)") }
    var statsShareOfSpent: String { t("Part du dépensé", "Share of spent") }
    var statsTimeSub: String {
        t(
            "Totaux et moyennes — le détail machines / casinos est plus bas",
            "Totals and averages — machine / casino detail is below"
        )
    }
    var statsVisitDurationHint: String { t("Σ durée des sorties", "Σ visit duration") }
    var statsSessionDurationHint: String { t("Σ durée des sessions", "Σ session duration") }
    var statsAvgPerVisit: String { t("Moy. / sortie", "Avg / visit") }
    var statsAvgPerSession: String { t("Moy. / session", "Avg / session") }
    var statsNetPerHour: String { t("Gain net / heure", "Net / hour") }
    var statsNetPerHourHint: String { t("Net ÷ heures de sorties", "Net ÷ visit hours") }
    var statsEvolution: String { t("Évolution", "Trend") }
    var statsEvolutionSub: String {
        t("Net cumulé et bilan mensuel", "Cumulative net and monthly summary")
    }
    var statsCumulativeNet: String { t("Net cumulé", "Cumulative net") }
    var statsVisitAfterVisit: String { t("Sortie après sortie", "Visit after visit") }
    var statsNotEnoughVisits: String {
        t("Pas assez de sorties pour le graphique", "Not enough visits for the chart")
    }
    var statsByMonth: String { t("Par mois", "By month") }
    var statsSpentGainsNet: String { t("Dépensé, gains et net", "Spent, winnings and net") }
    var statsDistribution: String { t("Répartitions", "Breakdown") }
    var statsDistributionSub: String {
        t(
            "Cashflow budget, puis résultats sorties et sessions",
            "Budget cashflow, then visit and session results"
        )
    }
    var statsDistSpendSource: String { t("Dépensé : CB / Liquide", "Spent: Card / Cash") }
    var statsDistCapital: String { t("Capital : poche / réinvesti", "Capital: pocket / reinvested") }
    var statsDistVisitResults: String { t("Résultat des sorties (€)", "Visit results (€)") }
    var statsDistSessionCount: String { t("Sessions gagnantes / perdantes", "Winning / losing sessions") }
    var statsDistBonusTypes: String { t("Gains bonus par type", "Bonus wins by type") }
    var statsDistCasinos: String { t("Dépensé par casino", "Spent by casino") }
    var statsDistMachineIn: String { t("Mis par machine", "Amount in by machine") }
    var statsDistWins: String { t("Gains", "Wins") }
    var statsDistLosses: String { t("Pertes", "Losses") }
    var statsDistOthers: String { t("Autres", "Other") }
    func statsDistPercent(_ pct: Int) -> String { "\(pct) %" }
    var statsFilterEmptyTitle: String {
        t("Aucune sortie sur ce filtre", "No visits for this filter")
    }
    var statsFilterEmptySub: String {
        t(
            "Élargis la période ou change de casino pour voir les stats.",
            "Widen the period or change casino to see stats."
        )
    }
    var statsMachinesSub: String {
        t(
            "Où l’argent est mis, puis classement détaillé (triable)",
            "Where money went in, then a sortable detailed ranking"
        )
    }
    var statsNoSessions: String {
        t("Aucune session sur la période", "No sessions in this period")
    }
    var statsHot: String { t("en forme", "hot") }
    var statsSessionPL: String {
        t("Gain/perte · Σ cash-out − mis", "P/L · Σ cash-out − in")
    }
    var statsBonusSub: String {
        t(
            "× = gain bonus ÷ mise bonus (quand connue)",
            "× = bonus win ÷ bonus bet (when known)"
        )
    }
    var statsAvgBonusMult: String { t("× moyen global", "Overall avg ×") }
    var statsAvgBonusMultHint: String {
        t("Sur tous les bonus avec mise", "Across all bonuses with a bet")
    }
    func statsBonusShare(_ count: Int, _ pct: Int) -> String {
        t(
            "\(timesCount(count)) · \(pct) % des gains bonus",
            "\(timesCount(count)) · \(pct)% of bonus wins"
        )
    }
    func statsRecord(_ win: String, _ machine: String) -> String {
        t("Record \(win) · \(machine)", "Record \(win) · \(machine)")
    }
    var statsCasinosSub: String {
        t(
            "Parts du dépensé, puis net / temps par casino",
            "Spend shares, then net / time per casino"
        )
    }
    func statsCasinoDetail(visits: Int, spent: String, reinvested: String) -> String {
        let v = language == .fr
            ? "\(visits) visite\(visits > 1 ? "s" : "")"
            : "\(visits) visit\(visits == 1 ? "" : "s")"
        return t(
            "\(v) · dépensé \(spent) · réinvesti \(reinvested)",
            "\(v) · spent \(spent) · reinvested \(reinvested)"
        )
    }
    func statsTimeLabel(_ duration: String) -> String {
        t("Temps \(duration)", "Time \(duration)")
    }
    var statsByMachineType: String { t("Par type de machine", "By machine type") }
    var statsByMachineTypeSub: String {
        t("Net cumulé des sessions", "Cumulative session net")
    }

    // MARK: - Gallery

    var galleryTitle: String { t("Galerie bonus", "Bonus gallery") }
    var galleryEmpty: String { t("Aucune photo de bonus", "No bonus photos") }
    var galleryAllCasinos: String { t("Tous casinos", "All casinos") }
    var galleryAllMachines: String { t("Toutes machines", "All machines") }
    var galleryAllTypes: String { t("Tous types", "All types") }
    var gallerySort: String { t("Tri", "Sort") }
    var gallerySortDate: String { t("Date", "Date") }
    var gallerySortGain: String { t("Gain", "Win") }
    var galleryDescending: String { t("Décroissant", "Descending") }
    var galleryAscending: String { t("Croissant", "Ascending") }
}

extension View {
    /// Injecte le store de langue + locale SwiftUI (refresh via Observation, sans restart).
    func ctLanguage(_ store: LanguageStore) -> some View {
        self
            .environment(store)
            .environment(\.locale, store.locale)
    }
}
