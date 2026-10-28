import SwiftUI
import SwiftData

struct VisitBudgetSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @Bindable var visit: Visit

    @State private var showAdd = false
    @State private var editingEntry: BudgetEntry?
    @State private var padAmount = 0.0
    @State private var padSource: BudgetSource = .liquide
    @State private var padKind: String = "topup"
    @State private var entryPendingDelete: BudgetEntry?

    private var sortedEntries: [BudgetEntry] {
        visit.budgets.sorted { $0.at < $1.at }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryRow(language.t.visitPotBalance, visit.displayedCagnotteBalance, emphasize: true)
                    summaryRow(language.t.sourceCB, visit.budgetCB, asExpense: true)
                    summaryRow(language.t.sourceCash, visit.budgetLiquide, asExpense: true)
                    summaryRow(language.t.sourceBudget, visit.budgetFromPrevious, asExpense: true)
                    if visit.withdrawnFromPot > 0 {
                        summaryRow(language.t.budgetWithdrawn, visit.withdrawnFromPot)
                    }
                    summaryRow(language.t.capital, visit.totalBudget, asExpense: true)
                } header: {
                    Text(language.t.budgetTotals)
                }

                Section {
                    if sortedEntries.isEmpty {
                        Text(language.t.budgetEmpty)
                            .foregroundStyle(CTTheme.muted)
                    } else {
                        ForEach(sortedEntries) { entry in
                            Button {
                                beginEdit(entry)
                            } label: {
                                entryRow(entry)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    entryPendingDelete = entry
                                } label: {
                                    Label(language.t.delete, systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text(language.t.budgetEntries)
                } footer: {
                    Text(language.t.budgetFooter)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CTTheme.bg)
            .navigationTitle(language.t.budgetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.t.close) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        beginAdd()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(language.t.budgetAddA11y)
                }
            }
            .sheet(isPresented: $showAdd) {
                budgetPadSheet(title: language.t.visitFundPot, confirmTitle: language.t.add) {
                    let entry = BudgetEntry(
                        kind: padKind,
                        amount: padAmount,
                        source: padSource.rawValue,
                        visit: visit
                    )
                    context.insert(entry)
                    syncPlannedBudgetIfNeeded()
                    visit.syncGainsFromCagnotte()
                    try? context.save()
                }
            }
            .sheet(item: $editingEntry) { entry in
                budgetPadSheet(title: language.t.budgetEditEntry, confirmTitle: language.t.save) {
                    entry.amount = padAmount
                    if entry.isCagnotteWithdraw {
                        entry.source = MoneyMath.cagnotteSourceRaw
                    } else {
                        entry.source = padSource.rawValue
                        if padKind == "planned" || entry.kind == "planned" {
                            entry.kind = padKind
                        }
                    }
                    syncPlannedBudgetIfNeeded()
                    visit.syncGainsFromCagnotte()
                    try? context.save()
                }
            }
            .confirmationDialog(
                language.t.budgetDeleteEntry,
                isPresented: Binding(
                    get: { entryPendingDelete != nil },
                    set: { if !$0 { entryPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(language.t.delete, role: .destructive) {
                    if let entry = entryPendingDelete {
                        context.delete(entry)
                        syncPlannedBudgetIfNeeded()
                        visit.syncGainsFromCagnotte()
                        try? context.save()
                    }
                    entryPendingDelete = nil
                }
                Button(language.t.cancel, role: .cancel) {
                    entryPendingDelete = nil
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func summaryRow(
        _ title: String,
        _ value: Double,
        emphasize: Bool = false,
        asExpense: Bool = false
    ) -> some View {
        let amountColor: Color = {
            if emphasize { return CTTheme.gold }
            if asExpense, abs(value) > 0 { return CTTheme.lose }
            return CTTheme.ink
        }()
        return HStack {
            Text(title)
                .foregroundStyle(emphasize ? CTTheme.ink : CTTheme.muted)
                .fontWeight(emphasize ? .semibold : .regular)
            Spacer()
            Text(MoneyMath.formatEUR(value))
                .fontWeight(.semibold)
                .foregroundStyle(amountColor)
                .monospacedDigit()
        }
        .listRowBackground(CTTheme.bgElevated.opacity(0.85))
    }

    private func entryRow(_ entry: BudgetEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.kindLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CTTheme.ink)
                HStack(spacing: 6) {
                    Text(entry.sourceLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CTTheme.champagne)
                    Text(CTDates.string(entry.at, date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(CTTheme.muted)
                }
                if entry.linkedSession != nil {
                    Text(language.t.budgetLinkedMachine)
                        .font(.caption2)
                        .foregroundStyle(CTTheme.muted)
                }
            }
            Spacer(minLength: 8)
            Text(MoneyMath.formatEUR(entry.amount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(entry.isCagnotteWithdraw ? CTTheme.lose : CTTheme.gold)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CTTheme.muted)
        }
        .listRowBackground(CTTheme.bgElevated.opacity(0.85))
    }

    private func beginAdd() {
        padAmount = 0
        padSource = .liquide
        padKind = "topup"
        showAdd = true
    }

    private func beginEdit(_ entry: BudgetEntry) {
        padAmount = entry.amount
        if entry.isCagnotteWithdraw {
            padSource = .liquide
        } else {
            padSource = BudgetSource.parse(entry.source)
        }
        padKind = entry.kind
        editingEntry = entry
    }

    private func syncPlannedBudgetIfNeeded() {
        let planned = visit.budgets
            .filter { $0.kind == "planned" && !$0.isCagnotteWithdraw }
            .reduce(0.0) { $0 + $1.amount }
        visit.plannedBudget = planned
    }

    @ViewBuilder
    private func budgetPadSheet(
        title: String,
        confirmTitle: String,
        onConfirm: @escaping () -> Void
    ) -> some View {
        let editingCagnotte = editingEntry?.isCagnotteWithdraw == true
        NavigationStack {
            VStack(spacing: 16) {
                if !editingCagnotte {
                    Picker(language.t.type, selection: $padKind) {
                        Text(language.t.budgetInitial).tag("planned")
                        Text(language.t.visitTopup).tag("topup")
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        ForEach(BudgetSource.potFundingCases) { s in
                            Button {
                                padSource = s
                            } label: {
                                Text(s.label)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(padSource == s ? CTTheme.gold : CTTheme.felt.opacity(0.7))
                                    .foregroundStyle(padSource == s ? CTTheme.bg : CTTheme.ink)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(language.t.visitFundPotHint)
                        .font(.caption)
                        .foregroundStyle(CTTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(language.t.sourceReplay)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CTTheme.champagne)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                BudgetAmountPad(amount: $padAmount)

                PrimaryButton(title: confirmTitle) {
                    onConfirm()
                    showAdd = false
                    editingEntry = nil
                }
            }
            .padding()
            .ctSheetScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.t.close) {
                        showAdd = false
                        editingEntry = nil
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct BudgetAmountPad: View {
    @Binding var amount: Double
    @State private var text = ""

    var body: some View {
        MoneyPad(valueText: $text)
            .onAppear {
                text = amount > 0 ? String(format: "%.2f", amount) : ""
            }
            .onChange(of: text) { _, newValue in
                amount = MoneyMath.toNumber(newValue)
            }
    }
}
