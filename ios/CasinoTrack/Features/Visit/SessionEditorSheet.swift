import SwiftUI
import SwiftData

struct SessionEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    var visit: Visit
    var session: MachineSession?
    var machines: [Machine]
    var bonusTypes: [BonusType] = []

    /// Session active dans le sheet (passée à l’ouverture, ou créée après choix machine).
    @State private var activeSession: MachineSession?
    @State private var didBootstrap = false

    @State private var query = ""
    @State private var selected: Machine?
    @State private var customName = ""
    @State private var amountIn: Double = 0
    @State private var betText = ""
    @State private var cashOut: Double?
    @State private var notes = ""

    @State private var showTopupPad = false
    @State private var showCashOutPad = false
    @State private var showSetInPad = false
    @State private var showBetPad = false
    @State private var showBonus = false
    @State private var showDetails = false
    @State private var showDurationEdit = false
    @State private var showDeleteConfirm = false
    @State private var isLeavingMachine = false
    /// Force le hub à relire les relations SwiftData (bonus) après sheet / delete.
    @State private var hubListEpoch = 0

    @State private var padAmount = 0.0
    @State private var padSource: BudgetSource = .liquide

    private var isEditing: Bool { activeSession != nil }

    private var preferredBetUnit: Double? {
        selected?.defaultBet
    }

    private var filtered: [Machine] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = machines
        if q.isEmpty { return Array(base.prefix(40)) }
        return base.filter { $0.name.lowercased().contains(q) }
    }

    private var navTitle: String {
        if isEditing {
            let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? (activeSession?.machineName ?? "Session") : name
        }
        return "Choisir une machine"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = activeSession {
                    EditSessionHub(
                        session: session,
                        amountIn: amountIn,
                        cashOut: cashOut,
                        listEpoch: hubListEpoch,
                        showDetails: $showDetails,
                        onAddBonus: { showBonus = true },
                        onAddMoney: {
                            padAmount = 0
                            showTopupPad = true
                        },
                        onCashOut: {
                            isLeavingMachine = true
                            padAmount = cashOut ?? 0
                            showCashOutPad = true
                        },
                        onEditDuration: { showDurationEdit = true },
                        onDeleteBonus: deleteBonus,
                        onRequestDelete: { showDeleteConfirm = true },
                        details: {
                            VStack(alignment: .leading, spacing: 14) {
                                machinePicker
                                amountAbsoluteRow
                                betRow
                                notesField
                                PrimaryButton(title: language.t.sessionSaveDetails, icon: "checkmark") { save() }
                            }
                            .padding(.top, 8)
                        }
                    )
                } else {
                    machinePickForm
                }
            }
            .scrollContentBackground(.hidden)
            .background(CTTheme.bg)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.t.close) { dismiss() }
                }
                if isEditing && showDetails {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(language.t.save) { save() }
                            .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear { bootstrapIfNeeded() }
            .sheet(isPresented: $showTopupPad) {
                MoneyPadSheet(
                    title: language.t.sessionAddToMachine,
                    amount: $padAmount,
                    sources: BudgetSource.allCases,
                    source: $padSource,
                    confirmTitle: language.t.add
                ) {
                    amountIn += padAmount
                    if let session = activeSession {
                        let entry = BudgetEntry(
                            kind: "topup",
                            amount: padAmount,
                            source: padSource.rawValue,
                            visit: session.visit ?? visit,
                            linkedSession: session
                        )
                        context.insert(entry)
                        persistAmountsIfEditing()
                    }
                }
            }
            .sheet(isPresented: $showCashOutPad, onDismiss: {
                isLeavingMachine = false
            }) {
                MoneyPadSheet(
                    title: language.t.sessionCashOutTitle,
                    amount: $padAmount,
                    sources: nil,
                    source: $padSource,
                    confirmTitle: language.t.sessionCashOutConfirm
                ) {
                    cashOut = padAmount
                    let leaving = isLeavingMachine
                    persistAmountsIfEditing(closingTiming: leaving)
                    isLeavingMachine = false
                    if leaving {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDurationEdit) {
                if let session = activeSession {
                    DurationEditSheet(
                        totalSeconds: Int(session.effectiveDuration.rounded())
                    ) { seconds in
                        session.applyManualDuration(seconds: seconds)
                        try? context.save()
                    }
                }
            }
            .sheet(isPresented: $showSetInPad) {
                MoneyPadSheet(
                    title: language.t.sessionAmountInTitle,
                    amount: $padAmount,
                    sources: nil,
                    source: $padSource
                ) {
                    amountIn = padAmount
                    persistAmountsIfEditing()
                }
            }
            .sheet(isPresented: $showBetPad) {
                BetMoneyPadSheet(
                    title: language.t.sessionBetTitle,
                    amount: $padAmount,
                    preferredUnit: preferredBetUnit
                ) {
                    betText = String(format: "%.2f", padAmount)
                }
            }
            .sheet(isPresented: $showBonus, onDismiss: {
                hubListEpoch &+= 1
            }) {
                if let session = activeSession {
                    BonusEditorSheet(
                        session: session,
                        bonusTypes: bonusTypes,
                        machine: selected ?? session.catalogMachine
                    )
                }
            }
            .confirmationDialog(
                language.t.sessionDeleteTitle,
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(language.t.delete, role: .destructive) {
                    deleteSession()
                }
                Button(language.t.cancel, role: .cancel) {}
            } message: {
                Text(language.t.sessionDeleteMessage)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Machine pick (création)

    private var machinePickForm: some View {
        List {
            Section {
                Text(language.t.sessionPickHint)
                    .font(.subheadline)
                    .foregroundStyle(CTTheme.muted)
                    .listRowBackground(Color.clear)
            }
            Section(language.t.machine) {
                machinePickerRows
            }
            Section {
                TextField("Nom libre", text: $customName)
                PrimaryButton(title: language.t.sessionStart, icon: "play.fill") {
                    beginSession(
                        machine: selected,
                        freeName: customName
                    )
                }
                .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            } header: {
                Text(language.t.sessionFreeName)
            }
        }
    }

    // MARK: - Shared fields

    private var machinePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.t.machine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CTTheme.muted)
            TextField("Rechercher", text: $query)
                .padding(12)
                .background(CTTheme.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            ForEach(filtered.prefix(8)) { m in
                Button {
                    selected = m
                    customName = m.name
                    if let bet = m.defaultBet, betText.isEmpty {
                        betText = String(format: "%.2f", bet)
                    }
                } label: {
                    HStack {
                        MachineThumb(path: m.photoPath, data: m.photoData, size: 36)
                        VStack(alignment: .leading) {
                            Text(m.isFavorite ? "★ \(m.name)" : m.name)
                                .foregroundStyle(CTTheme.ink)
                            if let man = m.manufacturer {
                                Text(man).font(.caption).foregroundStyle(CTTheme.muted)
                            }
                        }
                        Spacer()
                        if selected?.persistentModelID == m.persistentModelID {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(CTTheme.gold)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            TextField("Nom libre", text: $customName)
                .padding(12)
                .background(CTTheme.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var machinePickerRows: some View {
        TextField("Rechercher", text: $query)
        ForEach(filtered) { m in
            Button {
                beginSession(machine: m, freeName: m.name)
            } label: {
                HStack {
                    MachineThumb(path: m.photoPath, data: m.photoData, size: 40)
                    VStack(alignment: .leading) {
                        Text(m.isFavorite ? "★ \(m.name)" : m.name)
                            .foregroundStyle(CTTheme.ink)
                        if let man = m.manufacturer {
                            Text(man).font(.caption).foregroundStyle(CTTheme.muted)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CTTheme.muted)
                }
            }
        }
    }

    private var amountAbsoluteRow: some View {
        Button {
            padAmount = amountIn
            showSetInPad = true
        } label: {
            fieldRow(language.t.sessionAmountInTitle, MoneyMath.formatEUR(amountIn))
        }
        .buttonStyle(.plain)
    }

    private var betRow: some View {
        Button {
            padAmount = MoneyMath.toNumber(betText)
            showBetPad = true
        } label: {
            fieldRow(language.t.sessionBetTitle, betText.isEmpty ? "-" : MoneyMath.formatEUR(MoneyMath.toNumber(betText)))
        }
        .buttonStyle(.plain)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.t.notes)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CTTheme.muted)
            TextField(language.t.optional, text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(CTTheme.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func fieldRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(CTTheme.gold).fontWeight(.semibold)
        }
        .padding()
        .frame(minHeight: CTTheme.minTap)
        .background(CTTheme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Persistence

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        if let session {
            activeSession = session
            loadFromSession()
        }
    }

    private func loadFromSession() {
        guard let session = activeSession else { return }
        customName = session.machineName
        selected = session.catalogMachine
        amountIn = session.amountIn
        if let bet = session.betSetting {
            betText = String(format: "%.2f", bet)
        } else {
            betText = ""
        }
        cashOut = session.cashOut
        notes = session.notes ?? ""
    }

    /// Crée la `MachineSession` puis bascule immédiatement vers le hub d’édition.
    private func beginSession(machine: Machine?, freeName: String) {
        let name = freeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let bet = machine?.defaultBet
        let s = MachineSession(
            machineName: name,
            amountIn: 0,
            betSetting: bet,
            cashOut: nil,
            startedAt: .now,
            endedAt: nil,
            notes: nil,
            visit: visit,
            machineType: machine?.machineType,
            catalogMachine: machine
        )
        context.insert(s)
        try? context.save()
        selected = machine
        customName = name
        amountIn = 0
        cashOut = nil
        notes = ""
        if let bet {
            betText = String(format: "%.2f", bet)
        } else {
            betText = ""
        }
        activeSession = s
        scheduleOpenAddMoneyAfterCreate()
    }

    /// Après création seulement : laisse le hub s’afficher, puis ouvre « Rajouter de l’argent ».
    private func scheduleOpenAddMoneyAfterCreate() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard activeSession != nil else { return }
            padAmount = 0
            showTopupPad = true
        }
    }

    private func persistAmountsIfEditing(closingTiming: Bool = false) {
        guard let session = activeSession else { return }
        session.amountIn = amountIn
        session.cashOut = cashOut
        if closingTiming {
            session.closeTiming()
        }
        syncVisitGainsFromSessions(for: session)
        try? context.save()
    }

    /// Recalcule gains / net visite depuis les cash-outs dès qu’une session a un retrait.
    private func syncVisitGainsFromSessions(for session: MachineSession? = nil) {
        let target = session?.visit ?? activeSession?.visit ?? visit
        target.syncGainsFromSessions()
    }

    private func deleteBonus(_ bonus: BonusEvent) {
        guard let session = activeSession else {
            context.delete(bonus)
            try? context.save()
            hubListEpoch &+= 1
            return
        }
        if let idx = session.bonuses.firstIndex(where: { $0.persistentModelID == bonus.persistentModelID }) {
            session.bonuses.remove(at: idx)
        }
        context.delete(bonus)
        try? context.save()
        hubListEpoch &+= 1
    }

    private func deleteSession() {
        guard let session = activeSession else { return }
        // Legacy : topups non liés → retirer les montants correspondants du budget visite.
        if session.linkedBudgetEntries.isEmpty, session.amountIn > 0 {
            removeMatchingUnlinkedTopups(
                amount: session.amountIn,
                from: session.visit ?? visit
            )
        }
        let visitRef = session.visit ?? visit
        let removedCashOut = session.cashOut != nil
        // Cascade : linkedBudgetEntries + bonuses
        context.delete(session)
        if !visitRef.syncGainsFromSessions(), removedCashOut {
            // Plus aucun retrait machine → retirer les gains synchronisés.
            visitRef.manualTotalWin = nil
        }
        try? context.save()
        dismiss()
    }

    /// Heuristique pour les anciennes sessions sans `linkedSession` : retire les topups
    /// non liés les plus récents jusqu’à couvrir `amount` (FIFO inverse).
    private func removeMatchingUnlinkedTopups(amount: Double, from visit: Visit) {
        var remaining = amount
        let candidates = visit.budgets
            .filter { $0.kind == "topup" && $0.linkedSession == nil }
            .sorted { $0.at > $1.at }
        for entry in candidates {
            guard remaining > 0.009 else { break }
            if entry.amount <= remaining + 0.009 {
                remaining -= entry.amount
                context.delete(entry)
            }
        }
    }

    private func save() {
        guard let session = activeSession else { return }
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let bet = betText.isEmpty ? nil : MoneyMath.toNumber(betText)
        let notesValue = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        session.machineName = name
        session.catalogMachine = selected
        session.machineType = selected?.machineType
        session.amountIn = amountIn
        session.betSetting = bet
        session.cashOut = cashOut
        session.notes = notesValue.isEmpty ? nil : notesValue
        if cashOut != nil, session.endedAt == nil {
            session.closeTiming()
        }
        syncVisitGainsFromSessions(for: session)
        try? context.save()
        dismiss()
    }
}

// MARK: - Edit hub (floor actions only)

private struct EditSessionHub<Details: View>: View {
    @Environment(LanguageStore.self) private var language
    @Bindable var session: MachineSession
    var amountIn: Double
    var cashOut: Double?
    var listEpoch: Int
    @Binding var showDetails: Bool
    var onAddBonus: () -> Void
    var onAddMoney: () -> Void
    var onCashOut: () -> Void
    var onEditDuration: () -> Void
    var onDeleteBonus: (BonusEvent) -> Void
    var onRequestDelete: () -> Void
    @ViewBuilder var details: () -> Details

    private var sortedBonuses: [BonusEvent] {
        _ = listEpoch
        return session.bonuses.sorted { $0.at < $1.at }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard

                Button(action: onEditDuration) {
                    HStack {
                        Label(language.t.sessionDuration, systemImage: "timer")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CTTheme.ink)
                        Spacer()
                        SessionDurationText(session: session, font: .subheadline.weight(.semibold))
                            .foregroundStyle(CTTheme.gold)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CTTheme.muted)
                    }
                    .padding()
                    .frame(minHeight: CTTheme.minTap)
                    .background(CTTheme.bgElevated.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                bonusesBlock

                VStack(spacing: 10) {
                    Text(language.t.sessionActions)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CTTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    quickAction(
                        title: language.t.sessionAddBonus,
                        subtitle: language.t.sessionAddBonusSub,
                        icon: "sparkles",
                        tint: CTTheme.gold,
                        action: onAddBonus
                    )

                    quickAction(
                        title: language.t.sessionAddMoney,
                        subtitle: language.t.sessionAddMoneySub,
                        icon: "plus.circle.fill",
                        tint: CTTheme.win,
                        action: onAddMoney
                    )

                    quickAction(
                        title: language.t.sessionLeaveMachine,
                        subtitle: language.t.sessionLeaveMachineSub,
                        icon: "door.left.hand.open",
                        tint: CTTheme.champagne,
                        action: onCashOut
                    )
                }

                DisclosureGroup(isExpanded: $showDetails) {
                    details()
                } label: {
                    Text(language.t.sessionMachineDetails)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CTTheme.ink)
                }
                .tint(CTTheme.gold)

                Button(role: .destructive, action: onRequestDelete) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        Text(language.t.delete)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: CTTheme.minTap)
                    .foregroundStyle(CTTheme.lose)
                    .background(CTTheme.felt.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityLabel(language.t.sessionDeleteA11y)
            }
            .padding()
        }
        .ctScreen()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                summaryChip(title: language.t.sessionPutIn, value: MoneyMath.formatEUR(amountIn))
                summaryChip(
                    title: language.t.sessionCashOut,
                    value: cashOut.map { MoneyMath.formatEUR($0) } ?? "-"
                )
                summaryChip(
                    title: language.t.net,
                    value: MoneyMath.formatEUR(MoneyMath.sessionNet(amountIn: amountIn, cashOut: cashOut)),
                    emphasize: true
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CTTheme.bgElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var bonusesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.t.bonus)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CTTheme.muted)

            if sortedBonuses.isEmpty {
                Text(language.t.sessionNoBonus)
                    .font(.subheadline)
                    .foregroundStyle(CTTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(CTTheme.felt.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(sortedBonuses) { bonus in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hexString: bonus.types.first?.colorHex ?? "#cea658"))
                            .frame(width: 10, height: 10)
                        Text(bonus.typeLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CTTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(MoneyMath.formatEUR(bonus.winAmount))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(CTTheme.gold)
                        Button {
                            onDeleteBonus(bonus)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(CTTheme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(language.t.sessionDeleteBonusA11y)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: CTTheme.minTap)
                    .background(CTTheme.felt.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func summaryChip(title: String, value: String, emphasize: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(CTTheme.muted)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(emphasize ? CTTheme.gold : CTTheme.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickAction(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(CTTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(CTTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CTTheme.muted)
            }
            .padding()
            .frame(minHeight: CTTheme.minTap)
            .background(CTTheme.felt.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Duration edit

struct DurationEditSheet: View {
    @Environment(LanguageStore.self) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Int
    @State private var minutes: Int
    var onConfirm: (Int) -> Void

    init(totalSeconds: Int, onConfirm: @escaping (Int) -> Void) {
        let clamped = max(0, totalSeconds)
        _hours = State(initialValue: min(99, clamped / 3600))
        _minutes = State(initialValue: (clamped % 3600) / 60)
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Heures", selection: $hours) {
                    ForEach(0..<100, id: \.self) { Text("\($0) h").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("Minutes", selection: $minutes) {
                    ForEach(0..<60, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle(language.t.durationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.t.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.t.ok) {
                        onConfirm(hours * 3600 + minutes * 60)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(CTTheme.bg)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
