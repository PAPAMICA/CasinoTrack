import Charts
import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(LanguageStore.self) private var language
    @Query(sort: \Visit.startedAt, order: .reverse) private var visits: [Visit]
    @Query(sort: \Casino.name) private var casinos: [Casino]
    @Query(sort: \Machine.name) private var catalogMachines: [Machine]
    @AppStorage("bankManualAdjustment") private var bankManualAdjustment = 0.0
    @State private var filter = StatsFilter()
    @State private var machineSort = 0
    @State private var showGallery = false
    @State private var showBankAdjust = false
    @State private var sectionsAppeared = false

    private var t: L10n { language.t }

    private var snapshot: StatsSnapshot {
        StatsEngine.build(visits: visits, filter: filter)
    }

    /// Solde Banque affiché = net sorties (filtrées) + ajustement manuel global.
    private var displayedBank: Double {
        snapshot.bankroll.net + bankManualAdjustment
    }

    /// Machine catalogue pour une ligne de ranking (lien session, sinon match par nom).
    private func resolveMachine(for rank: MachineRank) -> Machine? {
        if let linked = rank.machine { return linked }
        return catalogMachines.first {
            $0.name.localizedCaseInsensitiveCompare(rank.name) == .orderedSame
        }
    }

    private var hasFilteredData: Bool {
        snapshot.bankroll.visitsCount > 0
    }

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            bankSection(showMetrics: false)
                            CTEmptyState(
                                title: t.statsEmptyTitle,
                                subtitle: t.statsEmptySub,
                                systemImage: "chart.line.uptrend.xyaxis"
                            )
                        }
                        .padding()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            filters
                                .ctStagger(sectionsAppeared, index: 0)

                            bankSection(showMetrics: hasFilteredData)
                                .ctStagger(sectionsAppeared, index: 1)

                            if !hasFilteredData {
                                filteredEmptyBlock
                                    .ctStagger(sectionsAppeared, index: 2)
                            } else {
                                // Répartitions → tendances → temps → classements
                                distributionBlock
                                    .ctStagger(sectionsAppeared, index: 2)
                                evolutionBlock
                                    .ctStagger(sectionsAppeared, index: 3)
                                timeBlock
                                    .ctStagger(sectionsAppeared, index: 4)
                                machinesBlock
                                    .ctStagger(sectionsAppeared, index: 5)
                                bonusBlock
                                    .ctStagger(sectionsAppeared, index: 6)
                                casinosBlock
                                    .ctStagger(sectionsAppeared, index: 7)
                            }
                        }
                        .padding()
                    }
                    .ctTriggerAppear($sectionsAppeared)
                }
            }
            .animation(CTMotion.content, value: visits.isEmpty)
            .animation(CTMotion.content, value: hasFilteredData)
            .animation(CTMotion.content, value: filter)
            .ctScreen()
            .navigationTitle(t.tabStats)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGallery = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundStyle(CTTheme.gold)
                            .symbolEffect(.bounce, value: showGallery)
                    }
                    .accessibilityLabel(t.statsBonusGalleryA11y)
                }
            }
            .navigationDestination(isPresented: $showGallery) {
                BonusGalleryView()
            }
            .sheet(isPresented: $showBankAdjust) {
                BankAdjustmentSheet(adjustment: $bankManualAdjustment)
                    .ctSheetChrome(detents: [.large])
            }
            .onChange(of: filter) { _, _ in
                withAnimation(CTMotion.appearFast) { sectionsAppeared = true }
            }
        }
    }

    private var filteredEmptyBlock: some View {
        CTEmptyState(
            title: language.t.statsFilterEmptyTitle,
            subtitle: language.t.statsFilterEmptySub,
            systemImage: "line.3.horizontal.decrease.circle"
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(StatsFilter.Period.allCases.filter { $0 != .visit }) { p in
                        Button {
                            withAnimation(CTMotion.appearFast) { filter.period = p }
                        } label: {
                            Text(p.label)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(filter.period == p ? CTTheme.gold : CTTheme.felt.opacity(0.7))
                                .foregroundStyle(filter.period == p ? CTTheme.bg : CTTheme.ink)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(CTPressButtonStyle(pressedScale: 0.96))
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    chip(language.t.all, selected: filter.casinoLegacyId == nil) { filter.casinoLegacyId = nil }
                    ForEach(casinos) { c in
                        chip(c.name, selected: filter.casinoLegacyId == c.legacyId) {
                            filter.casinoLegacyId = c.legacyId
                        }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(selected ? CTTheme.gold.opacity(0.25) : CTTheme.bgElevated)
                .overlay(Capsule().strokeBorder(selected ? CTTheme.gold : .clear, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(CTPressButtonStyle(pressedScale: 0.96))
    }

    // MARK: - Banque (= net sorties + ajustement manuel)

    @ViewBuilder
    private func bankSection(showMetrics: Bool) -> some View {
        let b = snapshot.bankroll
        let balance = displayedBank
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                sectionHeader(
                    language.t.statsBankroll,
                    subtitle: language.t.statsBankrollSub
                )
                Spacer(minLength: 8)
                Button {
                    showBankAdjust = true
                } label: {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(CTTheme.gold)
                        .frame(width: 36, height: 36)
                        .background(CTTheme.felt.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(CTPressButtonStyle(pressedScale: 0.92))
                .accessibilityLabel(language.t.statsBankAdjustA11y)
            }

            Button {
                showBankAdjust = true
            } label: {
                Text(MoneyMath.formatEUR(balance, withSign: true))
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                    .foregroundStyle(balance > 0 ? CTTheme.win : (balance < 0 ? CTTheme.lose : CTTheme.champagne))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(CTTheme.bgElevated.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .contentTransition(.numericText())
            .animation(CTMotion.snappy, value: balance)
            .accessibilityLabel(language.t.statsBankroll)
            .accessibilityValue(MoneyMath.formatEUR(balance, withSign: true))
            .accessibilityHint(language.t.statsBankAdjustA11y)

            if abs(bankManualAdjustment) > 0.000_1 {
                Text(language.t.statsBankAdjustDetail(MoneyMath.formatEUR(bankManualAdjustment, withSign: true)))
                    .font(.caption)
                    .foregroundStyle(CTTheme.muted)
            }

            if showMetrics {
                if b.visitsCount > 0 {
                    Text(language.t.statsNetSubtitle(b.visitsCount))
                        .font(.footnote)
                        .foregroundStyle(CTTheme.muted)
                }

                HStack(spacing: 10) {
                    mini(language.t.statsSpent, b.pocket, asExpense: true)
                    mini(language.t.statsReinvested, b.reinvested, asExpense: true)
                    mini(language.t.gains, b.gains)
                }

                HStack(spacing: 10) {
                    breakdownChip(title: language.t.sourceCB, value: b.cb, color: CTTheme.lose)
                    breakdownChip(title: language.t.sourceCash, value: b.liquide, color: CTTheme.lose)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.t.statsPocketROI)
                            .font(.caption)
                            .foregroundStyle(CTTheme.muted)
                        Text(language.t.statsPocketROIHint)
                            .font(.caption2)
                            .foregroundStyle(CTTheme.muted.opacity(0.85))
                        Text(b.pocketROI.map { MoneyMath.formatMultiplier($0) } ?? "-")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(CTTheme.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                            .animation(CTMotion.snappy, value: b.pocketROI)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(language.t.statsReinvestRate)
                            .font(.caption)
                            .foregroundStyle(CTTheme.muted)
                        Text(language.t.statsReinvestRateHint)
                            .font(.caption2)
                            .foregroundStyle(CTTheme.muted.opacity(0.85))
                        Text(b.reinvestRate.map { "\(Int(($0 * 100).rounded())) %" } ?? "-")
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                            .animation(CTMotion.snappy, value: b.reinvestRate)
                    }
                }
                .padding()
                .background(CTTheme.bgElevated.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let best = b.bestNet, let worst = b.worstNet {
                    HStack {
                        Label {
                            Text(language.t.statsBest(MoneyMath.formatEUR(best, withSign: true)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CTTheme.win)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        } icon: {
                            Image(systemName: "arrow.up.right").foregroundStyle(CTTheme.win)
                        }
                        Spacer(minLength: 8)
                        Label {
                            Text(language.t.statsWorst(MoneyMath.formatEUR(worst, withSign: true)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CTTheme.lose)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        } icon: {
                            Image(systemName: "arrow.down.right").foregroundStyle(CTTheme.lose)
                        }
                    }
                }

                if snapshot.winStreak > 0 || snapshot.loseStreak > 0 {
                    Text(snapshot.winStreak > 0
                         ? language.t.statsWinStreak(snapshot.winStreak)
                         : language.t.statsLoseStreak(snapshot.loseStreak))
                        .font(.subheadline)
                        .foregroundStyle(snapshot.winStreak > 0 ? CTTheme.win : CTTheme.lose)
                }
            }
        }
    }

    private func breakdownChip(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(CTTheme.muted)
            Text(language.t.statsShareOfSpent).font(.caption2).foregroundStyle(CTTheme.muted.opacity(0.85))
            Text(MoneyMath.formatEUR(value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CTTheme.felt.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func mini(_ t: String, _ v: Double, asExpense: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CTTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            MoneyText(value: v, asExpense: asExpense)
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CTTheme.bgElevated.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Temps

    private var timeBlock: some View {
        let t = snapshot.time
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                language.t.time,
                subtitle: language.t.statsTimeSub
            )

            HStack(spacing: 10) {
                timeCard(
                    title: language.t.tabVisits,
                    hint: language.t.statsVisitDurationHint,
                    value: CTDuration.string(seconds: t.totalVisitSeconds)
                )
                timeCard(
                    title: language.t.machines,
                    hint: language.t.statsSessionDurationHint,
                    value: CTDuration.string(seconds: t.totalSessionSeconds)
                )
            }

            HStack(spacing: 10) {
                timeCard(
                    title: language.t.statsAvgPerVisit,
                    hint: t.visitCount > 0 ? language.t.visitsCount(t.visitCount) : language.t.none,
                    value: t.avgVisitSeconds.map { CTDuration.string(seconds: $0) } ?? "-"
                )
                timeCard(
                    title: language.t.statsAvgPerSession,
                    hint: t.sessionCount > 0 ? language.t.sessionsCount(t.sessionCount) : language.t.none,
                    value: t.avgSessionSeconds.map { CTDuration.string(seconds: $0) } ?? "-"
                )
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.t.statsNetPerHour)
                        .font(.caption)
                        .foregroundStyle(CTTheme.muted)
                    Text(language.t.statsNetPerHourHint)
                        .font(.caption2)
                        .foregroundStyle(CTTheme.muted.opacity(0.85))
                }
                Spacer()
                if let eph = t.netPerHour {
                    Text(MoneyMath.formatEUR(eph, withSign: true) + "/h")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(eph >= 0 ? CTTheme.win : CTTheme.lose)
                        .monospacedDigit()
                } else {
                    Text("-")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CTTheme.muted)
                }
            }
            .padding()
            .background(CTTheme.bgElevated.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func timeCard(title: String, hint: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(CTTheme.muted)
            Text(hint).font(.caption2).foregroundStyle(CTTheme.muted.opacity(0.85))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CTTheme.champagne)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CTTheme.bgElevated.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Évolution

    private var evolutionBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                language.t.statsEvolution,
                subtitle: language.t.statsEvolutionSub
            )

            if snapshot.cumulativeNets.count > 1 {
                Text(language.t.statsCumulativeNet)
                    .font(.subheadline.weight(.semibold))
                Text(language.t.statsVisitAfterVisit)
                    .font(.caption2)
                    .foregroundStyle(CTTheme.muted)

                Chart(snapshot.cumulativeNets) { point in
                    LineMark(
                        x: .value("Sortie", point.index),
                        y: .value("Net", point.net)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(CTTheme.gold)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    AreaMark(
                        x: .value("Sortie", point.index),
                        y: .value("Net", point.net)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [CTTheme.gold.opacity(0.28), CTTheme.felt.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(CTTheme.feltSoft.opacity(0.5))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(shortEUR(v))
                                    .font(.caption2)
                                    .foregroundStyle(CTTheme.muted)
                            }
                        }
                    }
                }
                .frame(height: 160)
                .padding(12)
                .background(CTTheme.bgElevated.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(CTMotion.chart, value: snapshot.cumulativeNets.count)
            } else {
                Text(language.t.statsNotEnoughVisits)
                    .font(.footnote)
                    .foregroundStyle(CTTheme.muted)
            }

            if snapshot.monthlyBars.count >= 1 {
                Text(language.t.statsByMonth)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                Text(language.t.statsSpentGainsNet)
                    .font(.caption2)
                    .foregroundStyle(CTTheme.muted)

                Chart {
                    ForEach(snapshot.monthlyBars) { m in
                        BarMark(
                            x: .value("Mois", m.label),
                            y: .value("Dépensé", m.spent)
                        )
                        .foregroundStyle(CTTheme.feltSoft)
                        .position(by: .value("Série", "Dépensé"))

                        BarMark(
                            x: .value("Mois", m.label),
                            y: .value("Gains", m.gains)
                        )
                        .foregroundStyle(CTTheme.gold)
                        .position(by: .value("Série", "Gains"))

                        BarMark(
                            x: .value("Mois", m.label),
                            y: .value("Net", m.net)
                        )
                        .foregroundStyle(m.net >= 0 ? CTTheme.win : CTTheme.lose)
                        .position(by: .value("Série", "Net"))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(CTTheme.feltSoft.opacity(0.5))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(shortEUR(v))
                                    .font(.caption2)
                                    .foregroundStyle(CTTheme.muted)
                            }
                        }
                    }
                }
                .frame(height: 180)
                .padding(12)
                .background(CTTheme.bgElevated.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(CTMotion.chart, value: snapshot.monthlyBars.count)
            }
        }
    }

    // MARK: - Répartitions (barres plates)

    private struct DistCardModel: Identifiable {
        let id: String
        let title: String
        let slices: [DistSlice]
        let kind: DistValueKind
    }

    /// Cashflow budget + résultats (une info = une barre).
    private var distributionCards: [DistCardModel] {
        let d = snapshot.distributions
        let cards: [DistCardModel] = [
            .init(id: "spend", title: language.t.statsDistSpendSource, slices: d.spendBySource, kind: .money),
            .init(id: "capital", title: language.t.statsDistCapital, slices: d.capitalFlow, kind: .money),
            .init(id: "visit€", title: language.t.statsDistVisitResults, slices: d.visitResults, kind: .money),
            .init(id: "sessN", title: language.t.statsDistSessionCount, slices: d.sessionResultsCount, kind: .count),
        ]
        return cards.filter { $0.slices.count >= 2 }
    }

    private var distributionBlock: some View {
        let cards = distributionCards
        return Group {
            if !cards.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(
                        language.t.statsDistribution,
                        subtitle: language.t.statsDistributionSub
                    )
                    ForEach(cards) { card in
                        distBar(title: card.title, slices: card.slices, kind: card.kind)
                    }
                }
            }
        }
    }

    private func distBar(title: String, slices: [DistSlice], kind: DistValueKind) -> some View {
        let total = slices.reduce(0.0) { $0 + $1.value }
        let segments = slices.map { slice in
            DistBarSegment(
                key: slice.key,
                label: distLabel(for: slice.key),
                value: slice.value,
                color: distColor(for: slice, in: slices)
            )
        }
        return DistributionBar(
            title: title,
            segments: segments,
            totalText: distTotalLabel(total: total, kind: kind),
            valueFormatter: { distValueLabel($0, kind: kind) },
            percentFormatter: { language.t.statsDistPercent($0) }
        )
    }

    private func distTotalLabel(total: Double, kind: DistValueKind) -> String {
        switch kind {
        case .money:
            return shortEUR(total)
        case .count:
            return "\(Int(total.rounded()))"
        case .durationSeconds:
            return CTDuration.string(seconds: Int(total.rounded()))
        }
    }

    private func distValueLabel(_ value: Double, kind: DistValueKind) -> String {
        switch kind {
        case .money:
            return MoneyMath.formatEUR(value)
        case .count:
            return "\(Int(value.rounded()))"
        case .durationSeconds:
            return CTDuration.string(seconds: Int(value.rounded()))
        }
    }

    private func distLabel(for key: String) -> String {
        switch key {
        case "cb": return language.t.sourceCB
        case "liquide": return language.t.sourceCash
        case "pocket": return language.t.statsSpent
        case "reinvested": return language.t.sourceBudget
        case "wins": return language.t.statsDistWins
        case "losses": return language.t.statsDistLosses
        case "autres": return language.t.statsDistOthers
        default: return key
        }
    }

    private func distColor(for slice: DistSlice, in all: [DistSlice]) -> Color {
        switch slice.key {
        case "cb": return CTTheme.champagne
        case "liquide": return CTTheme.goldBright
        case "pocket": return CTTheme.feltSoft
        case "reinvested": return CTTheme.gold
        case "wins": return CTTheme.win
        case "losses": return CTTheme.lose
        case "autres": return CTTheme.muted
        default:
            if let hex = slice.colorHex, !hex.isEmpty {
                return Color(hexString: hex)
            }
            let palette: [Color] = [
                CTTheme.gold, CTTheme.feltSoft, CTTheme.champagne,
                CTTheme.goldBright, CTTheme.felt, CTTheme.win,
            ]
            let idx = all.firstIndex(where: { $0.key == slice.key }) ?? 0
            return palette[idx % palette.count]
        }
    }

    private func shortEUR(_ value: Double) -> String {
        let absV = abs(value)
        let sign = value < 0 ? "−" : ""
        if absV >= 1000 {
            return "\(sign)\(Int((absV / 1000).rounded())) k€"
        }
        return "\(sign)\(Int(absV.rounded())) €"
    }

    // MARK: - Machines

    private var machinesBlock: some View {
        let sorted: [MachineRank] = {
            switch machineSort {
            case 1: return snapshot.machines.sorted { $0.amountIn > $1.amountIn }
            case 2: return snapshot.machines.sorted { ($0.multiplier ?? -1) > ($1.multiplier ?? -1) }
            case 3: return snapshot.machines.sorted { $0.bonusCount > $1.bonusCount }
            case 4: return snapshot.machines.sorted { $0.durationSeconds > $1.durationSeconds }
            default: return snapshot.machines
            }
        }()
        let d = snapshot.distributions
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                language.t.machines,
                subtitle: language.t.statsMachinesSub
            )

            if d.amountInByMachine.count >= 2 {
                distBar(title: language.t.statsDistMachineIn, slices: d.amountInByMachine, kind: .money)
            }

            Picker("", selection: $machineSort) {
                Text(language.t.net).tag(0)
                Text(language.t.sessionPutIn).tag(1)
                Text("×").tag(2)
                Text(language.t.bonus).tag(3)
                Text(language.t.time).tag(4)
            }
            .pickerStyle(.segmented)

            if sorted.isEmpty {
                Text(language.t.statsNoSessions)
                    .font(.footnote)
                    .foregroundStyle(CTTheme.muted)
            } else {
                ForEach(sorted) { m in
                    if let machine = resolveMachine(for: m) {
                        NavigationLink {
                            MachineDetailView(machine: machine)
                        } label: {
                            machineRow(m, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        machineRow(m, showsChevron: false)
                    }
                }
            }
        }
    }

    private func machineRow(_ m: MachineRank, showsChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(m.name).font(.body.weight(.semibold))
                if m.hot {
                    Text(language.t.statsHot)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CTTheme.gold.opacity(0.2))
                        .foregroundStyle(CTTheme.gold)
                        .clipShape(Capsule())
                }
                Spacer()
                Text(MoneyMath.formatEUR(m.net, withSign: true))
                    .font(.body.weight(.bold))
                    .foregroundStyle(m.net >= 0 ? CTTheme.win : CTTheme.lose)
                    .monospacedDigit()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CTTheme.muted)
                }
            }
            Text(language.t.statsSessionPL)
                .font(.caption2)
                .foregroundStyle(CTTheme.muted)

            HStack(spacing: 0) {
                machineMetric(language.t.sessionPutIn, MoneyMath.formatEUR(m.amountIn), CTTheme.champagne)
                machineMetric(language.t.sessions, "\(m.sessions)", CTTheme.ink)
                machineMetric(language.t.bonus, "\(m.bonusCount)", CTTheme.ink)
                machineMetric("×", MoneyMath.formatMultiplier(m.multiplier), CTTheme.gold)
            }
            HStack(spacing: 0) {
                machineMetric(
                    language.t.time,
                    m.durationSeconds > 0 ? CTDuration.string(seconds: m.durationSeconds) : "-",
                    CTTheme.champagne
                )
                machineMetric(
                    "€/h",
                    m.euroPerHour.map { MoneyMath.formatEUR($0, withSign: true) } ?? "-",
                    (m.euroPerHour ?? 0) >= 0 ? CTTheme.win : CTTheme.lose
                )
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(CTTheme.bgElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func machineMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(CTTheme.muted)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bonus

    private var bonusBlock: some View {
        let d = snapshot.distributions
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                language.t.bonus,
                subtitle: language.t.statsBonusSub
            )

            if d.bonusByType.count >= 2 {
                distBar(title: language.t.statsDistBonusTypes, slices: d.bonusByType, kind: .money)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.t.statsAvgBonusMult)
                        .foregroundStyle(CTTheme.muted)
                    Text(language.t.statsAvgBonusMultHint)
                        .font(.caption2)
                        .foregroundStyle(CTTheme.muted.opacity(0.85))
                }
                Spacer()
                Text(MoneyMath.formatMultiplier(snapshot.avgBonusMult))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CTTheme.gold)
            }
            .padding()
            .background(CTTheme.bgElevated.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                ForEach(snapshot.combos) { c in
                    VStack(spacing: 4) {
                        Text(c.label).font(.caption).foregroundStyle(CTTheme.muted)
                        Text("\(c.count)").font(.headline)
                        Text(MoneyMath.formatMultiplier(c.avgMult)).font(.caption2).foregroundStyle(CTTheme.gold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(CTTheme.felt.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            ForEach(Array(snapshot.bonuses.prefix(6))) { b in
                RankRow(
                    title: b.name,
                    subtitle: language.t.statsBonusShare(b.count, Int((b.winShare * 100).rounded())),
                    trailing: MoneyMath.formatMultiplier(b.avgMult),
                    trailingColor: CTTheme.gold
                )
            }

            if let best = snapshot.bestBonus {
                Text(language.t.statsRecord(MoneyMath.formatEUR(best.win), best.machine))
                    .font(.footnote)
                    .foregroundStyle(CTTheme.champagne)
            }
        }
    }

    // MARK: - Casinos

    private var casinosBlock: some View {
        let d = snapshot.distributions
        let multiCasino = filter.casinoLegacyId == nil && snapshot.casinos.count >= 2
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                language.t.casinos,
                subtitle: language.t.statsCasinosSub
            )

            if multiCasino, d.spendByCasino.count >= 2 {
                distBar(title: language.t.statsDistCasinos, slices: d.spendByCasino, kind: .money)
            }

            ForEach(snapshot.casinos) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(c.name).font(.body.weight(.semibold))
                        Spacer()
                        Text(MoneyMath.formatEUR(c.net, withSign: true))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(c.net >= 0 ? CTTheme.win : CTTheme.lose)
                            .monospacedDigit()
                    }
                    Text(language.t.statsCasinoDetail(visits: c.visits, spent: MoneyMath.formatEUR(c.pocket), reinvested: MoneyMath.formatEUR(c.reinvested)))
                        .font(.caption)
                        .foregroundStyle(CTTheme.muted)
                    if c.durationSeconds > 0 {
                        Text(language.t.statsTimeLabel(CTDuration.string(seconds: c.durationSeconds)))
                            .font(.caption2)
                            .foregroundStyle(CTTheme.champagne)
                    }
                }
                .padding(.vertical, 8)
            }

            if !snapshot.byMachineType.isEmpty {
                Text(language.t.statsByMachineType)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                Text(language.t.statsByMachineTypeSub)
                    .font(.caption2)
                    .foregroundStyle(CTTheme.muted)
                ForEach(snapshot.byMachineType, id: \.0) { row in
                    RankRow(
                        title: row.0,
                        subtitle: language.t.sessionsCount(row.1),
                        trailing: MoneyMath.formatEUR(row.2, withSign: true),
                        trailingColor: row.2 >= 0 ? CTTheme.win : CTTheme.lose
                    )
                }
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(CTTheme.muted)
        }
    }
}

// MARK: - Ajustement manuel Banque (+/− hors casino)

private enum BankAdjustMode: Hashable {
    case add, withdraw
}

struct BankAdjustmentSheet: View {
    @Binding var adjustment: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @State private var mode: BankAdjustMode = .add
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    modeButton(language.t.add, .add)
                    modeButton(language.t.withdraw, .withdraw)
                }

                Text(language.t.statsBankAdjustFooter)
                    .font(.caption)
                    .foregroundStyle(CTTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                MoneyPad(valueText: $text)

                PrimaryButton(title: mode == .add ? language.t.add : language.t.withdraw) {
                    let amount = MoneyMath.toNumber(text)
                    guard amount > 0 else { return }
                    if mode == .add {
                        adjustment += amount
                    } else {
                        adjustment -= amount
                    }
                    dismiss()
                }
            }
            .padding()
            .ctSheetScreen()
            .navigationTitle(language.t.statsBankAdjustTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.t.close) { dismiss() }
                }
            }
        }
    }

    private func modeButton(_ title: String, _ value: BankAdjustMode) -> some View {
        Button {
            mode = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(mode == value ? CTTheme.gold : CTTheme.felt.opacity(0.7))
                .foregroundStyle(mode == value ? CTTheme.bg : CTTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
