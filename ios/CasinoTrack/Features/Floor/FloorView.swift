import SwiftUI
import SwiftData

struct FloorView: View {
    @Environment(\.modelContext) private var context
    @Environment(LanguageStore.self) private var language
    @Query(sort: \Visit.startedAt, order: .reverse) private var visits: [Visit]
    @State private var showNew = false
    @State private var showSettings = false
    @State private var idleAppeared = false

    private var live: Visit? { visits.first(where: \.isLive) }
    private var lastClosed: Visit? { visits.first(where: { !$0.isLive }) }
    private var closedVisits: [Visit] { visits.filter { !$0.isLive } }

    private var liveID: PersistentIdentifier? { live?.persistentModelID }

    private var totalSpent: Double {
        visits.reduce(0) { $0 + $1.cashExpense }
    }

    private var totalNet: Double {
        closedVisits.compactMap(\.net).reduce(0, +)
    }

    /// × total = net / (CB + Liquide) — Budget exclu.
    private var totalMultiplier: Double? {
        MoneyMath.aggregatePocketMultiplier(net: totalNet, cashSpent: totalSpent)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let live {
                    VisitDetailView(visit: live)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            )
                        )
                } else {
                    idleContent
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(CTMotion.content, value: liveID)
            .ctScreen()
            .navigationTitle(live == nil ? "" : language.t.tabFloor)
            .navigationBarTitleDisplayMode(live == nil ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .symbolEffect(.bounce, value: showSettings)
                    }
                }
            }
            .sheet(isPresented: $showNew) {
                NewVisitSheet()
                    .ctSheetChrome()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(\.modelContext, context)
                    .ctSheetChrome(detents: [.large])
            }
            .onChange(of: liveID) { _, newValue in
                if newValue == nil {
                    idleAppeared = false
                    DispatchQueue.main.async {
                        withAnimation(CTMotion.appear) {
                            idleAppeared = true
                        }
                    }
                }
            }
        }
    }

    private var idleContent: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: max(24, geo.size.height * 0.08))

                    VStack(spacing: 28) {
                        idleHero
                        homeSummary
                        idleCTA
                        if let last = lastClosed {
                            lastVisitCard(last)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 520)

                    Spacer(minLength: 48)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        .ctTriggerAppear($idleAppeared)
    }

    private var idleHero: some View {
        VStack(spacing: 14) {
            Image(systemName: "suit.diamond.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(CTTheme.gold)
                .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: idleAppeared)
                .ctAppear(idleAppeared, offset: 12)

            Text("CasinoTrack")
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundStyle(CTTheme.gold)
                .ctAppear(idleAppeared, offset: 16)

            Text(language.t.floorTagline)
                .font(.body)
                .foregroundStyle(CTTheme.champagne.opacity(0.9))
                .multilineTextAlignment(.center)
                .ctAppear(idleAppeared, offset: 14)
        }
        .frame(maxWidth: .infinity)
        .animation(CTMotion.heroDelay(0), value: idleAppeared)
    }

    /// Stats globales — idle uniquement (masquées quand une sortie est live).
    private var homeSummary: some View {
        let t = language.t
        return HStack(spacing: 10) {
            summaryTile(
                title: t.floorSpent,
                subtitle: t.floorSpentHint,
                value: MoneyMath.formatEUR(totalSpent),
                color: CTTheme.lose,
                index: 0
            )
            summaryTile(
                title: t.floorNetGain,
                subtitle: t.floorNetGainHint,
                value: MoneyMath.formatEUR(totalNet, withSign: true),
                color: totalNet >= 0 ? CTTheme.win : CTTheme.lose,
                index: 1
            )
            summaryTile(
                title: t.floorTotalMult,
                subtitle: t.floorTotalMultHint,
                value: MoneyMath.formatMultiplier(totalMultiplier),
                color: CTTheme.gold,
                index: 2
            )
        }
        .ctAppear(idleAppeared, offset: 14)
        .animation(CTMotion.appear.delay(0.12), value: idleAppeared)
    }

    private func summaryTile(
        title: String,
        subtitle: String,
        value: String,
        color: Color,
        index: Int
    ) -> some View {
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
                .ctNumericText(value: value)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(CTTheme.muted.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CTTheme.bgElevated.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CTTheme.gold.opacity(0.12), lineWidth: 1)
        )
        .ctStagger(idleAppeared, index: index, offset: 8)
    }

    private var idleCTA: some View {
        PrimaryButton(title: language.t.floorNewVisit, icon: "plus") {
            showNew = true
        }
        .ctAppear(idleAppeared, offset: 18, scale: 0.96)
        .animation(CTMotion.springAppear.delay(0.18), value: idleAppeared)
    }

    private func lastVisitCard(_ last: Visit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.t.floorLastVisit)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CTTheme.muted)
                .textCase(.uppercase)
                .tracking(0.8)

            NavigationLink {
                VisitDetailView(visit: last)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(last.casino?.name ?? language.t.casino)
                                .font(.headline)
                            Text(CTDates.string(last.startedAt, date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(CTTheme.muted)
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.caption2)
                                VisitDurationText(visit: last, font: .caption)
                            }
                            .foregroundStyle(CTTheme.champagne)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            MoneyText(value: last.net, withSign: true)
                                .font(.headline)
                            Text(MoneyMath.formatMultiplier(last.spendMultiplier))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(CTTheme.gold)
                        }
                    }
                    BudgetBreakdownRow(
                        cb: last.budgetCB,
                        liquide: last.budgetLiquide,
                        reinvested: last.reinvested
                    )
                }
                .padding(16)
                .background(CTTheme.bgElevated.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(CTTheme.gold.opacity(0.14), lineWidth: 1)
                )
            }
            .buttonStyle(CTCardPressStyle())
        }
        .ctAppear(idleAppeared, offset: 12)
        .animation(CTMotion.appear.delay(0.28), value: idleAppeared)
    }
}
