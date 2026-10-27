import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageStore.self) private var language
    @Query(sort: \Visit.startedAt, order: .reverse) private var visits: [Visit]
    @State private var showNew = false
    @State private var visitPendingDelete: Visit?
    @State private var listAppeared = false

    private var t: L10n { language.t }

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    CTEmptyState(
                        title: t.historyEmptyTitle,
                        subtitle: t.historyEmptyDescription,
                        systemImage: "calendar",
                        ctaTitle: t.floorNewVisit,
                        ctaIcon: "plus"
                    ) {
                        showNew = true
                    }
                } else {
                    List {
                        ForEach(Array(visits.enumerated()), id: \.element.persistentModelID) { index, visit in
                            NavigationLink {
                                VisitDetailView(visit: visit)
                            } label: {
                                visitRow(visit)
                            }
                            .listRowBackground(CTTheme.bgElevated.opacity(0.7))
                            .ctStagger(listAppeared, index: min(index, 12))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    visitPendingDelete = visit
                                } label: {
                                    Label(t.delete, systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .ctTriggerAppear($listAppeared)
                }
            }
            .animation(CTMotion.content, value: visits.isEmpty)
            .ctScreen()
            .navigationTitle(t.tabVisits)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: {
                        Image(systemName: "plus")
                            .symbolEffect(.bounce, value: showNew)
                    }
                }
            }
            .sheet(isPresented: $showNew) {
                NewVisitSheet()
                    .ctSheetChrome()
            }
            .confirmationDialog(
                visitPendingDelete?.isLive == true
                    ? t.historyDeleteLiveTitle
                    : t.historyDeleteTitle,
                isPresented: Binding(
                    get: { visitPendingDelete != nil },
                    set: { if !$0 { visitPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(t.delete, role: .destructive) {
                    if let visit = visitPendingDelete {
                        visit.deleteCascade(in: context)
                        try? context.save()
                    }
                    visitPendingDelete = nil
                }
                Button(t.cancel, role: .cancel) {
                    visitPendingDelete = nil
                }
            } message: {
                if visitPendingDelete?.isLive == true {
                    Text(t.historyDeleteLiveMessage)
                } else {
                    Text(t.historyDeleteMessage)
                }
            }
        }
    }

    private func visitRow(_ visit: Visit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusPill(kind: visit.isLive ? .live : .done)
                    Text(visit.casino?.name ?? t.casino)
                        .font(.headline)
                    Text(CTDates.string(visit.startedAt, date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(CTTheme.muted)
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption2)
                        VisitDurationText(visit: visit, font: .caption)
                    }
                    .foregroundStyle(CTTheme.champagne)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    MoneyText(value: visit.net, withSign: true)
                        .font(.headline)
                    Text(MoneyMath.formatMultiplier(visit.spendMultiplier))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CTTheme.gold)
                }
            }

            BudgetBreakdownRow(
                cb: visit.budgetCB,
                liquide: visit.budgetLiquide,
                reinvested: visit.reinvested
            )

            HStack {
                Text(t.sessionsCount(visit.sessions.count))
                if visit.totalBudget > 0 {
                    Text("·")
                    Text(t.capitalLabel(MoneyMath.formatEUR(visit.totalBudget)))
                }
                if let gains = visit.effectiveGains {
                    Text("·")
                    Text(t.gainsLabel(MoneyMath.formatEUR(gains)))
                }
            }
            .font(.caption2)
            .foregroundStyle(CTTheme.muted)
        }
        .padding(.vertical, 4)
    }
}
