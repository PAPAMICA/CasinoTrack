import SwiftUI
import SwiftData

struct CatalogView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageStore.self) private var language
    @Query(sort: \Machine.name) private var allMachines: [Machine]
    @Query(sort: \Casino.name) private var allCasinos: [Casino]
    @Query private var allSessions: [MachineSession]

    private var t: L10n { language.t }

    private var machines: [Machine] {
        allMachines.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var casinos: [Casino] {
        allCasinos.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    @State private var segment = 0
    @State private var query = ""
    @State private var showMachineEditor = false
    @State private var showCasinoEditor = false
    @State private var editingMachine: Machine?
    @State private var editingCasino: Casino?
    @State private var machineToDelete: Machine?
    @State private var casinoToDelete: Casino?
    @State private var listAppeared = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $segment) {
                    Text(t.machines).tag(0)
                    Text(t.casinos).tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: segment) { _, _ in
                    listAppeared = false
                    DispatchQueue.main.async {
                        withAnimation(CTMotion.appear) { listAppeared = true }
                    }
                }

                TextField(t.search, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                if segment == 0 {
                    machinesList
                } else {
                    casinosList
                }
            }
            .animation(CTMotion.tabSwitch, value: segment)
            .ctScreen()
            .navigationTitle(t.tabCatalog)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if segment == 0 {
                            editingMachine = nil
                            showMachineEditor = true
                        } else {
                            editingCasino = nil
                            showCasinoEditor = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .symbolEffect(.bounce, value: showMachineEditor || showCasinoEditor)
                    }
                    .accessibilityLabel(segment == 0 ? t.catalogAddMachineA11y : t.catalogAddCasinoA11y)
                }
            }
            .sheet(isPresented: $showMachineEditor) {
                MachineEditorSheet(machine: editingMachine)
                    .ctSheetChrome()
            }
            .sheet(isPresented: $showCasinoEditor) {
                CasinoEditorSheet(casino: editingCasino)
                    .ctSheetChrome()
            }
            .confirmationDialog(
                language.t.catalogDeleteMachineTitle,
                isPresented: Binding(
                    get: { machineToDelete != nil },
                    set: { if !$0 { machineToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(language.t.delete, role: .destructive) {
                    if let machineToDelete {
                        context.delete(machineToDelete)
                        try? context.save()
                    }
                    machineToDelete = nil
                }
                Button(language.t.cancel, role: .cancel) { machineToDelete = nil }
            } message: {
                Text(machineToDelete.map { language.t.catalogDeleteMachineMessage($0.name) } ?? "")
            }
            .confirmationDialog(
                language.t.catalogDeleteCasinoTitle,
                isPresented: Binding(
                    get: { casinoToDelete != nil },
                    set: { if !$0 { casinoToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(language.t.delete, role: .destructive) {
                    if let casinoToDelete {
                        context.delete(casinoToDelete)
                        try? context.save()
                    }
                    casinoToDelete = nil
                }
                Button(language.t.cancel, role: .cancel) { casinoToDelete = nil }
            } message: {
                Text(casinoToDelete.map { language.t.catalogDeleteCasinoMessage($0.name) } ?? "")
            }
        }
    }

    @ViewBuilder
    private var machinesList: some View {
        let q = query.lowercased()
        let rows = machines.filter {
            q.isEmpty
                || $0.name.lowercased().contains(q)
                || ($0.manufacturer?.lowercased().contains(q) ?? false)
        }
        if rows.isEmpty && query.isEmpty {
            CTEmptyState(
                title: t.catalogEmptyMachines,
                subtitle: t.catalogEmptyMachinesSub,
                systemImage: "rectangle.grid.3x2",
                ctaTitle: t.add,
                ctaIcon: "plus"
            ) {
                editingMachine = nil
                showMachineEditor = true
            }
        } else {
            List {
                if rows.isEmpty {
                    ContentUnavailableView(
                        t.catalogNoResult,
                        systemImage: "magnifyingglass",
                        description: Text(t.catalogNoResultSub)
                    )
                    .listRowBackground(Color.clear)
                    .ctAppear(listAppeared)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.persistentModelID) { index, m in
                        let stats = StatsEngine.catalogStats(for: m, sessions: allSessions)
                        NavigationLink {
                            MachineDetailView(machine: m)
                        } label: {
                            HStack(spacing: 12) {
                                MachineThumb(path: m.photoPath, data: m.photoData)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(m.isFavorite ? "★ \(m.name)" : m.name)
                                        .font(.headline)
                                    Text([m.manufacturer, m.machineType?.name].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(CTTheme.muted)
                                    if stats.sessionCount > 0 {
                                        Text(machineRowStatsLine(stats))
                                            .font(.caption2)
                                            .foregroundStyle(CTTheme.champagne)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                }
                            }
                        }
                        .listRowBackground(CTTheme.bgElevated.opacity(0.7))
                        .ctStagger(listAppeared, index: min(index, 12))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                machineToDelete = m
                            } label: {
                                Label(language.t.delete, systemImage: "trash")
                            }
                            Button {
                                editingMachine = m
                                showMachineEditor = true
                            } label: {
                                Label(language.t.edit, systemImage: "pencil")
                            }
                            .tint(CTTheme.feltSoft)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                m.isFavorite.toggle()
                                try? context.save()
                            } label: {
                                Label(m.isFavorite ? "Retirer" : "Favori", systemImage: "star")
                            }
                            .tint(CTTheme.gold)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ctTriggerAppear($listAppeared)
        }
    }

    private func machineRowStatsLine(_ stats: MachineCatalogStats) -> String {
        var parts: [String] = [
            "Mis \(MoneyMath.formatEUR(stats.amountIn))",
            MoneyMath.formatMultiplier(stats.multiplier),
        ]
        if stats.bonusCount > 0 {
            parts.append("\(stats.bonusCount) bonus")
        } else {
            parts.append("\(stats.sessionCount) sess.")
        }
        if stats.totalDurationSeconds > 0 {
            parts.append(CTDuration.string(seconds: stats.totalDurationSeconds))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var casinosList: some View {
        let q = query.lowercased()
        let rows = casinos.filter {
            q.isEmpty
                || $0.name.lowercased().contains(q)
                || ($0.city?.lowercased().contains(q) ?? false)
        }
        if rows.isEmpty && query.isEmpty {
            CTEmptyState(
                title: t.catalogEmptyCasinos,
                subtitle: t.catalogEmptyCasinosSub,
                systemImage: "building.2",
                ctaTitle: t.add,
                ctaIcon: "plus"
            ) {
                editingCasino = nil
                showCasinoEditor = true
            }
        } else {
            List {
                if rows.isEmpty {
                    ContentUnavailableView(
                        t.catalogNoResult,
                        systemImage: "magnifyingglass",
                        description: Text(t.catalogNoResultSub)
                    )
                    .listRowBackground(Color.clear)
                    .ctAppear(listAppeared)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.persistentModelID) { index, c in
                        NavigationLink {
                            CasinoDetailView(casino: c)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(c.isFavorite ? "★ \(c.name)" : c.name).font(.headline)
                                    Text(c.city ?? c.address ?? "-")
                                        .font(.caption)
                                        .foregroundStyle(CTTheme.muted)
                                }
                                Spacer()
                                Text("\(c.visits.count)")
                                    .foregroundStyle(CTTheme.muted)
                                    .ctNumericText(value: c.visits.count)
                            }
                        }
                        .listRowBackground(CTTheme.bgElevated.opacity(0.7))
                        .ctStagger(listAppeared, index: min(index, 12))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                casinoToDelete = c
                            } label: {
                                Label(language.t.delete, systemImage: "trash")
                            }
                            Button {
                                editingCasino = c
                                showCasinoEditor = true
                            } label: {
                                Label(language.t.edit, systemImage: "pencil")
                            }
                            .tint(CTTheme.feltSoft)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                c.isFavorite.toggle()
                                try? context.save()
                            } label: {
                                Label("Favori", systemImage: "star")
                            }
                            .tint(CTTheme.gold)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ctTriggerAppear($listAppeared)
        }
    }
}

struct MachineDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @Bindable var machine: Machine
    @Query(sort: \MachineSession.startedAt, order: .reverse) private var allSessions: [MachineSession]
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var detailAppeared = false

    private var stats: MachineCatalogStats {
        StatsEngine.catalogStats(for: machine, sessions: allSessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let img = machine.resolvedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                HStack {
                    Text(machine.name).font(.title2.bold())
                    Spacer()
                    Button {
                        machine.isFavorite.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: machine.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(CTTheme.gold)
                    }
                }
                if let man = machine.manufacturer {
                    Text(man).foregroundStyle(CTTheme.muted)
                }
                if let type = machine.machineType?.name {
                    Text(type).font(.subheadline)
                }
                if let bet = machine.defaultBet {
                    Text("Mise défaut \(MoneyMath.formatEUR(bet))")
                        .font(.subheadline)
                        .foregroundStyle(CTTheme.champagne)
                }
                if !machine.casinos.isEmpty {
                    Text("Casinos").font(.headline)
                    Text(machine.casinos.map(\.name).joined(separator: ", "))
                        .foregroundStyle(CTTheme.muted)
                }
                if !machine.bonusTypes.isEmpty {
                    Text("Bonus connus").font(.headline)
                    FlowBonusChipsReadonly(types: machine.bonusTypes)
                }
                if let features = machine.bonusFeatures, !features.isEmpty {
                    Text(features).font(.footnote).foregroundStyle(CTTheme.muted)
                }

                machineStatsSection

                PrimaryButton(title: language.t.edit, icon: "pencil") { showEditor = true }
                SecondaryButton(title: language.t.delete, icon: "trash") { showDeleteConfirm = true }
            }
            .padding()
            .ctAppear(detailAppeared)
            .animation(CTMotion.appear, value: detailAppeared)
        }
        .ctScreen()
        .navigationTitle(language.t.machine)
        .navigationBarTitleDisplayMode(.inline)
        .ctTriggerAppear($detailAppeared)
        .sheet(isPresented: $showEditor) {
            MachineEditorSheet(machine: machine)
                .ctSheetChrome()
        }
        .confirmationDialog(
            language.t.catalogDeleteMachineTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(language.t.delete, role: .destructive) {
                context.delete(machine)
                try? context.save()
                dismiss()
            }
            Button(language.t.cancel, role: .cancel) {}
        }
    }

    private var machineStatsSection: some View {
        let s = stats
        return VStack(alignment: .leading, spacing: 12) {
            Text(language.t.tabStats).font(.headline)

            HStack(spacing: 10) {
                machineStatTile(
                    title: "Gain/perte",
                    value: MoneyMath.formatEUR(s.sessionNet, withSign: true),
                    color: s.sessionNet >= 0 ? CTTheme.win : CTTheme.lose
                )
                machineStatTile(
                    title: "Mis",
                    value: MoneyMath.formatEUR(s.amountIn),
                    color: CTTheme.champagne
                )
                machineStatTile(
                    title: "×",
                    value: MoneyMath.formatMultiplier(s.multiplier),
                    color: CTTheme.gold
                )
            }

            HStack(spacing: 10) {
                machineStatTile(
                    title: "Sessions",
                    value: "\(s.sessionCount)",
                    color: CTTheme.ink
                )
                machineStatTile(
                    title: "Temps",
                    value: CTDuration.string(seconds: s.totalDurationSeconds),
                    color: CTTheme.champagne
                )
                machineStatTile(
                    title: language.t.bonus,
                    value: "\(s.bonusCount)",
                    color: CTTheme.ink
                )
            }

            machineStatTile(
                title: "Gains bonus",
                value: MoneyMath.formatEUR(s.bonusGains),
                color: s.bonusGains > 0 ? CTTheme.win : CTTheme.ink
            )

            if s.bonuses.isEmpty {
                Text("Aucun bonus enregistré")
                    .font(.footnote)
                    .foregroundStyle(CTTheme.muted)
            } else {
                Text("Liste des bonus").font(.headline)
                VStack(spacing: 0) {
                    ForEach(s.bonuses) { bonus in
                        RankRow(
                            title: bonus.typeLabel,
                            subtitle: CTDates.string(bonus.at, date: .abbreviated, time: .shortened),
                            trailing: [
                                MoneyMath.formatEUR(bonus.winAmount),
                                MoneyMath.formatMultiplier(bonus.multiplier),
                            ].joined(separator: "  "),
                            trailingColor: CTTheme.gold,
                            badge: nil
                        )
                        if bonus.persistentModelID != s.bonuses.last?.persistentModelID {
                            Divider().overlay(CTTheme.feltSoft.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(CTTheme.bgElevated.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func machineStatTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CTTheme.muted)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CTTheme.bgElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CasinoDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @Bindable var casino: Casino
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var detailAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(casino.name).font(.title2.bold())
                    Spacer()
                    Button {
                        casino.isFavorite.toggle()
                        try? context.save()
                    } label: {
                        Image(systemName: casino.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(CTTheme.gold)
                            .symbolEffect(.bounce, value: casino.isFavorite)
                    }
                }
                if let city = casino.city {
                    Text(city).foregroundStyle(CTTheme.muted)
                }
                if let address = casino.address {
                    Text(address).font(.footnote).foregroundStyle(CTTheme.muted)
                }
                if let website = casino.website {
                    Text(website).font(.footnote).foregroundStyle(CTTheme.gold)
                }
                Text("\(casino.visits.count) sortie(s)")
                    .foregroundStyle(CTTheme.muted)
                if !casino.machines.isEmpty {
                    Text("Machines liées").font(.headline)
                    Text(casino.machines.map(\.name).sorted().joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(CTTheme.muted)
                }

                PrimaryButton(title: language.t.edit, icon: "pencil") { showEditor = true }
                SecondaryButton(title: language.t.delete, icon: "trash") { showDeleteConfirm = true }
            }
            .padding()
            .ctAppear(detailAppeared)
            .animation(CTMotion.appear, value: detailAppeared)
        }
        .ctScreen()
        .navigationTitle(language.t.casino)
        .navigationBarTitleDisplayMode(.inline)
        .ctTriggerAppear($detailAppeared)
        .sheet(isPresented: $showEditor) {
            CasinoEditorSheet(casino: casino)
                .ctSheetChrome()
        }
        .confirmationDialog(
            language.t.catalogDeleteCasinoTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(language.t.delete, role: .destructive) {
                context.delete(casino)
                try? context.save()
                dismiss()
            }
            Button(language.t.cancel, role: .cancel) {}
        } message: {
            Text(casino.visits.isEmpty
                 ? "Cette action est définitive."
                 : "Les sorties liées garderont un casino vide.")
        }
    }
}

private struct FlowBonusChipsReadonly: View {
    let types: [BonusType]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(types) { t in
                Text(t.name)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(hexString: t.colorHex).opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
