import SwiftUI
import SwiftData

@main
struct CasinoTrackApp: App {
    private let container: ModelContainer
    @State private var languageStore = LanguageStore.shared

    init() {
        let schema = Schema([
            Casino.self,
            MachineType.self,
            BonusType.self,
            Machine.self,
            Visit.self,
            BudgetEntry.self,
            MachineSession.self,
            BonusEvent.self,
        ])
        // CloudKit private DB - sync auto entre appareils du même Apple ID
        let config = ModelConfiguration(
            "CasinoTrackCloud",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(CloudSync.containerID)
        )
        do {
            container = try ModelContainer(for: schema, configurations: config)
            Task { @MainActor in CloudSync.cloudKitStoreActive = true }
        } catch {
            // Fallback local si CloudKit indisponible (pas d’entitlement iCloud
            // sur compte Dev perso, simulateur sans iCloud, etc.)
            print("CloudKit container failed (\(error)). Falling back to local store.")
            do {
                let local = ModelConfiguration(
                    "CasinoTrackLocal",
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
                container = try ModelContainer(for: schema, configurations: local)
                Task { @MainActor in CloudSync.cloudKitStoreActive = false }
            } catch {
                fatalError("SwiftData container failed: \(error)")
            }
        }
        SeedImporter.runIfNeeded(container: container)
        PhotoMigrator.migrateFilePhotosIfNeeded(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .tint(CTTheme.gold)
                .environment(\.timeZone, CTDates.tz)
                .environment(\.calendar, CTDates.calendar(for: languageStore.language))
                .ctLanguage(languageStore)
        }
        .modelContainer(container)
    }
}
