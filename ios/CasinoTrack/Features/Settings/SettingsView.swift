import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var language

    @State private var visitCount = 0
    @State private var machineCount = 0
    @State private var casinoCount = 0
    @State private var syncStatus: CloudSync.Status = .localOnly
    @State private var syncLabel = "…"

    private var t: L10n { language.t }

    var body: some View {
        @Bindable var language = language
        NavigationStack {
            List {
                Section {
                    Picker(t.settingsLanguage, selection: $language.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text("\(lang.shortCode) · \(lang.displayName)").tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text(t.settingsLanguage)
                } footer: {
                    Text(t.settingsLanguageFooter)
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: CloudSync.isSyncingEnabled(syncStatus) ? "checkmark.icloud.fill" : "xmark.icloud")
                            .font(.title2)
                            .foregroundStyle(CloudSync.isSyncingEnabled(syncStatus) ? CTTheme.win : CTTheme.lose)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.settingsICloudBackup)
                                .font(.headline)
                            Text(syncLabel)
                                .font(.footnote)
                                .foregroundStyle(CTTheme.muted)
                        }
                    }
                    .padding(.vertical, 4)

                    Text(syncHelpText)
                        .font(.footnote)
                        .foregroundStyle(CTTheme.muted)
                } header: {
                    Text(t.settingsSync)
                }

                Section(t.settingsLocalData) {
                    LabeledContent(t.tabVisits, value: "\(visitCount)")
                    LabeledContent(t.machines, value: "\(machineCount)")
                    LabeledContent(t.casinos, value: "\(casinoCount)")
                }

                Section(t.settingsAbout) {
                    LabeledContent(t.settingsApp, value: "CasinoTrack")
                    LabeledContent(t.settingsVersion, value: appVersionLabel)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.settingsContainer)
                            .foregroundStyle(.secondary)
                        Text(CloudSync.containerID)
                            .font(.caption.monospaced())
                            .foregroundStyle(CTTheme.muted)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CTTheme.bg)
            .navigationTitle(t.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t.ok) { dismiss() }
                }
            }
            .task {
                refreshCounts()
                let status = CloudSync.currentStatus()
                syncStatus = status
                syncLabel = CloudSync.statusLabel(status)
            }
            .onChange(of: language.language) { _, _ in
                syncLabel = CloudSync.statusLabel(syncStatus)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var syncHelpText: String {
        if CloudSync.isSyncingEnabled(syncStatus) {
            return t.settingsSyncHelpActive
        }
        return t.settingsSyncHelpLocal
    }

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func refreshCounts() {
        visitCount = (try? modelContext.fetchCount(FetchDescriptor<Visit>())) ?? 0
        machineCount = (try? modelContext.fetchCount(FetchDescriptor<Machine>())) ?? 0
        casinoCount = (try? modelContext.fetchCount(FetchDescriptor<Casino>())) ?? 0
    }
}
