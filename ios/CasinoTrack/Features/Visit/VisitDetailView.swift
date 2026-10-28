import SwiftUI
import SwiftData
import PhotosUI

struct VisitDetailView: View {
    @Bindable var visit: Visit

    var body: some View {
        VisitDetailBody(visit: visit)
    }
}

private struct VisitDetailBody: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @Bindable var visit: Visit
    @Query(sort: [SortDescriptor(\BonusType.sortOrder), SortDescriptor(\BonusType.name)])
    private var bonusTypes: [BonusType]
    @Query(sort: \Machine.name) private var allMachines: [Machine]

    private var machines: [Machine] {
        allMachines.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    @State private var showNewSession = false
    @State private var editingSession: MachineSession?
    @State private var showFundPot = false
    @State private var showClose = false
    @State private var showBudgetSheet = false
    @State private var fundAmount = 50.0
    @State private var fundSource: BudgetSource = .liquide
    @State private var closeAmount = 0.0
    @State private var lightbox: UIImage?
    @State private var showDurationEdit = false
    @State private var showDeleteConfirm = false
    @State private var contentAppeared = false
    @State private var didPromptFundPot = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                    .ctStagger(contentAppeared, index: 0)
                NetHero(net: visit.net, subtitle: visitMultiplierSubtitle)
                    .ctStagger(contentAppeared, index: 1)
                financeStrip
                    .ctStagger(contentAppeared, index: 2)
                actionRow
                    .ctStagger(contentAppeared, index: 3)
                sessionsBlock
                    .ctStagger(contentAppeared, index: 4)
            }
            .padding()
        }
        .ctTriggerAppear($contentAppeared)
        .safeAreaInset(edge: .bottom) {
            if visit.isLive {
                PrimaryButton(title: language.t.visitAddMachine, icon: "plus") {
                    showNewSession = true
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial.opacity(0.001))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .symbolEffect(.bounce, value: showDeleteConfirm)
                }
                .accessibilityLabel(language.t.visitDeleteA11y)
            }
        }
        .confirmationDialog(
            visit.isLive ? language.t.historyDeleteLiveTitle : language.t.historyDeleteTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(language.t.delete, role: .destructive) {
                deleteVisit()
            }
            Button(language.t.cancel, role: .cancel) {}
        } message: {
            Text(deleteConfirmMessage)
        }
        .sheet(isPresented: $showNewSession) {
            SessionEditorSheet(
                visit: visit,
                session: nil,
                machines: machines,
                bonusTypes: bonusTypes
            )
            .ctSheetChrome(detents: [.large])
        }
        .sheet(item: $editingSession) { session in
            SessionEditorSheet(
                visit: visit,
                session: session,
                machines: machines,
                bonusTypes: bonusTypes
            )
            .ctSheetChrome(detents: [.large])
        }
        .sheet(isPresented: $showFundPot) {
            MoneyPadSheet(
                title: language.t.visitFundPot,
                amount: $fundAmount,
                sources: BudgetSource.potFundingCases,
                source: $fundSource,
                confirmTitle: language.t.add,
                footer: language.t.visitFundPotHint
            ) {
                let entry = BudgetEntry(
                    kind: visit.budgets.isEmpty ? "planned" : "topup",
                    amount: fundAmount,
                    source: fundSource.rawValue,
                    visit: visit
                )
                context.insert(entry)
                if entry.kind == "planned" {
                    visit.plannedBudget = visit.budgets
                        .filter { $0.kind == "planned" && !$0.isCagnotteWithdraw }
                        .reduce(0) { $0 + $1.amount }
                }
                visit.syncGainsFromCagnotte()
                try? context.save()
            }
            .ctSheetChrome()
        }
        .onAppear {
            promptFundPotIfNeeded()
        }
        .sheet(isPresented: $showBudgetSheet) {
            VisitBudgetSheet(visit: visit)
                .ctSheetChrome()
        }
        .sheet(isPresented: $showClose) {
            CloseVisitSheet(visit: visit, amount: $closeAmount)
                .ctSheetChrome()
        }
        .sheet(isPresented: $showDurationEdit) {
            DurationEditSheet(
                totalSeconds: Int(visit.effectiveDuration.rounded())
            ) { seconds in
                visit.applyManualDuration(seconds: seconds)
                try? context.save()
            }
            .ctSheetChrome(detents: [.medium])
        }
        .fullScreenCover(item: Binding(
            get: { lightbox.map { IdentifiedImage(image: $0) } },
            set: { lightbox = $0?.image }
        )) { item in
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: item.image)
                    .resizable()
                    .scaledToFit()
                VStack {
                    HStack {
                        Spacer()
                        Button(language.t.close) { lightbox = nil }
                            .padding()
                    }
                    Spacer()
                }
            }
        }
    }

    private var deleteConfirmMessage: String {
        if visit.isLive {
            return language.t.historyDeleteLiveMessage
        }
        return language.t.historyDeleteMessage
    }

    private func deleteVisit() {
        visit.deleteCascade(in: context)
        try? context.save()
        dismiss()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusPill(kind: visit.isLive ? .live : .done)
                Spacer()
            }
            Text(visit.casino?.name ?? language.t.casino)
                .font(.title.weight(.bold))
            Text(CTDates.string(visit.startedAt, date: .complete, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(CTTheme.muted)
            Button {
                showDurationEdit = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.subheadline)
                    VisitDurationText(visit: visit, font: .subheadline.weight(.semibold))
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CTTheme.muted)
                }
                .foregroundStyle(CTTheme.champagne)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.t.visitEditDurationA11y)
        }
    }

    private var visitMultiplierSubtitle: String? {
        let mult = MoneyMath.formatMultiplier(visit.spendMultiplier)
        guard visit.costBasis > 0 else { return mult }
        return language.t.visitMultiplierOnCapital(mult, MoneyMath.formatEUR(visit.costBasis))
    }

    private func promptFundPotIfNeeded() {
        guard visit.isLive, !didPromptFundPot else { return }
        didPromptFundPot = true
        let hasFunding = visit.budgets.contains { !$0.isCagnotteWithdraw }
        if !hasFunding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                fundAmount = 50
                fundSource = .liquide
                showFundPot = true
            }
        }
    }

    /// Bandeau cagnotte + sources, cliquable pour gérer les mouvements.
    private var financeStrip: some View {
        Button {
            showBudgetSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(language.t.visitPotBalance)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CTTheme.muted)
                    Spacer()
                    Text(MoneyMath.formatEUR(visit.displayedCagnotteBalance))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CTTheme.gold)
                        .monospacedDigit()
                    Image(systemName: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundStyle(CTTheme.muted)
                }
                HStack(spacing: 12) {
                    metric(language.t.sourceCB, visit.budgetCB, asExpense: true)
                    metric(language.t.sourceCash, visit.budgetLiquide, asExpense: true)
                    metric(language.t.sourceBudget, visit.budgetFromPrevious, asExpense: true)
                }
            }
            .padding(12)
            .background(CTTheme.bgElevated.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(CTCardPressStyle())
        .accessibilityLabel(language.t.visitBudgetA11y)
        .accessibilityHint(language.t.visitBudgetHint)
    }

    private func metric(_ title: String, _ value: Double?, asExpense: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(CTTheme.muted)
            MoneyText(value: value, asExpense: asExpense)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(CTTheme.felt.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if visit.isLive {
                SecondaryButton(title: language.t.visitFundPot, icon: "tray.and.arrow.down.fill") {
                    fundAmount = 50
                    fundSource = .liquide
                    showFundPot = true
                }
                SecondaryButton(title: language.t.visitClose, icon: "checkmark.circle") {
                    closeAmount = visit.effectiveGains ?? visit.cagnotteBalance
                    showClose = true
                }
            } else {
                SecondaryButton(title: language.t.gains, icon: "pencil") {
                    closeAmount = visit.effectiveGains ?? visit.cagnotteBalance
                    showClose = true
                }
                SecondaryButton(title: language.t.visitReopen, icon: "arrow.uturn.backward") {
                    visit.endedAt = nil
                    try? context.save()
                }
            }
        }
    }

    private var sessionsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.t.sessions)
                .font(.headline)
            if visit.sessions.isEmpty {
                Text(language.t.visitNoMachines)
                    .foregroundStyle(CTTheme.muted)
            } else {
                ForEach(Array(visit.sessions.sorted(by: { $0.startedAt < $1.startedAt }).enumerated()), id: \.element.persistentModelID) { index, session in
                    sessionCard(session)
                        .ctStagger(contentAppeared, index: index + 5)
                }
            }
        }
        .animation(CTMotion.appearFast, value: visit.sessions.count)
    }

    private func sessionCard(_ session: MachineSession) -> some View {
        Button {
            editingSession = session
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    MachineThumb(
                        path: session.catalogMachine?.photoPath,
                        data: session.catalogMachine?.photoData
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.machineName).font(.headline)
                        Text(language.t.inOut(inAmount: MoneyMath.formatEUR(session.amountIn), outAmount: session.cashOut.map { MoneyMath.formatEUR($0) }))
                            .font(.caption)
                            .foregroundStyle(CTTheme.muted)
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.caption2)
                            SessionDurationText(session: session, font: .caption)
                        }
                        .foregroundStyle(CTTheme.champagne)
                    }
                    Spacer()
                    MoneyText(value: session.sessionNet, withSign: true)
                        .font(.subheadline.weight(.semibold))
                }

                if !session.bonuses.isEmpty {
                    ForEach(session.bonuses.sorted(by: { $0.at < $1.at })) { bonus in
                        HStack {
                            Circle()
                                .fill(Color(hexString: bonus.types.first?.colorHex ?? "#cea658"))
                                .frame(width: 8, height: 8)
                            Text(bonus.typeLabel)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(MoneyMath.formatEUR(bonus.winAmount))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                            Text(MoneyMath.formatMultiplier(bonus.multiplier))
                                .font(.caption)
                                .foregroundStyle(CTTheme.gold)
                            if let img = bonus.resolvedImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .highPriorityGesture(
                                        TapGesture().onEnded { lightbox = img }
                                    )
                                    .accessibilityLabel(language.t.visitBonusPhotoA11y)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CTTheme.bgElevated.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(CTCardPressStyle())
        .accessibilityHint(language.t.visitSessionEditHint)
    }
}

private struct IdentifiedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct CloseVisitSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @Bindable var visit: Visit
    @Binding var amount: Double
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(language.t.visitGainsRemaining)
                    .font(.subheadline)
                    .foregroundStyle(CTTheme.muted)
                MoneyPad(valueText: $text)
                PrimaryButton(title: visit.isLive ? language.t.visitFinish : language.t.visitUpdate) {
                    visit.manualTotalWin = MoneyMath.toNumber(text)
                    if visit.isLive { visit.endedAt = .now }
                    try? context.save()
                    dismiss()
                }
            }
            .padding()
            .ctSheetScreen()
            .navigationTitle(language.t.gains)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.t.close) { dismiss() }
                }
            }
            .onAppear { text = amount > 0 ? String(format: "%.2f", amount) : "" }
        }
    }
}
