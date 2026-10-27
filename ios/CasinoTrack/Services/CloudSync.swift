import Foundation

/// Sync / statut iCloud.
///
/// Important : le compte Apple Developer *personnel* ne peut pas signer les
/// entitlements iCloud/CloudKit. Appeler `CKContainer` sans entitlement plante
/// l’app (crash à l’ouverture des Réglages). On n’importe donc pas CloudKit ici.
enum CloudSync {
    static let containerID = "iCloud.net.papamica.casinotrack"

    /// Mis à jour au démarrage : true si le ModelContainer CloudKit a démarré.
    @MainActor
    static var cloudKitStoreActive = false

    enum Status: Equatable {
        case active
        case localOnly
        case unavailable
    }

    @MainActor
    static func currentStatus() -> Status {
        cloudKitStoreActive ? .active : .localOnly
    }

    @MainActor
    static func statusLabel(_ status: Status) -> String {
        let t = LanguageStore.shared.t
        switch status {
        case .active:
            return t.syncActive
        case .localOnly:
            return t.syncLocalOnly
        case .unavailable:
            return t.syncUnavailable
        }
    }

    static func isSyncingEnabled(_ status: Status) -> Bool {
        status == .active
    }
}
