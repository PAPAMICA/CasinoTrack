import SwiftUI
import SwiftData

private enum GallerySortKey: String, CaseIterable, Identifiable {
    case date
    case gain
    case multiplier

    var id: String { rawValue }

    @MainActor
    var label: String {
        let t = LanguageStore.shared.t
        switch self {
        case .date: return t.gallerySortDate
        case .gain: return t.gallerySortGain
        case .multiplier: return "×"
        }
    }
}

struct BonusGalleryView: View {
    @Environment(LanguageStore.self) private var language
    @Query(sort: \BonusEvent.at, order: .reverse) private var bonuses: [BonusEvent]
    @Query(sort: \Casino.name) private var casinos: [Casino]
    @Query(sort: \BonusType.sortOrder) private var bonusTypes: [BonusType]

    @State private var period: StatsFilter.Period = .all
    @State private var casinoLegacyId: Int?
    @State private var machineName: String?
    @State private var bonusTypeId: PersistentIdentifier?
    @State private var sortKey: GallerySortKey = .date
    @State private var sortDescending = true
    @State private var lightboxBonus: BonusEvent?
    @State private var gridAppeared = false

    private var photoBonuses: [BonusEvent] {
        bonuses.filter { $0.photoData != nil || ($0.photoPath?.isEmpty == false) }
    }

    private var machineNames: [String] {
        Array(Set(photoBonuses.map { $0.session?.machineName ?? "?" }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filtered: [BonusEvent] {
        let list = photoBonuses.filter { bonus in
            if !matchesPeriod(bonus.at) { return false }
            if let casinoLegacyId {
                let visitCasino = bonus.session?.visit?.casino?.legacyId
                if visitCasino != casinoLegacyId { return false }
            }
            if let machineName, bonus.session?.machineName != machineName { return false }
            if let bonusTypeId {
                let ids = bonus.types.map(\.persistentModelID)
                if !ids.contains(bonusTypeId) { return false }
            }
            return true
        }
        return sorted(list)
    }

    private func sorted(_ list: [BonusEvent]) -> [BonusEvent] {
        list.sorted { a, b in
            let primary: ComparisonResult
            switch sortKey {
            case .date:
                primary = a.at.compare(b.at)
            case .gain:
                primary = a.winAmount < b.winAmount
                    ? .orderedAscending
                    : (a.winAmount > b.winAmount ? .orderedDescending : .orderedSame)
            case .multiplier:
                let am = a.multiplier ?? -Double.infinity
                let bm = b.multiplier ?? -Double.infinity
                primary = am < bm
                    ? .orderedAscending
                    : (am > bm ? .orderedDescending : .orderedSame)
            }
            if primary == .orderedSame {
                switch sortKey {
                case .date:
                    return a.winAmount > b.winAmount
                case .gain, .multiplier:
                    return a.at > b.at
                }
            }
            return sortDescending
                ? primary == .orderedDescending
                : primary == .orderedAscending
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filters
                if filtered.isEmpty {
                    CTEmptyState(
                        title: language.t.galleryEmpty,
                        systemImage: "photo.on.rectangle.angled"
                    )
                    .frame(minHeight: 280)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(filtered.enumerated()), id: \.element.persistentModelID) { index, bonus in
                            Button {
                                lightboxBonus = bonus
                            } label: {
                                GalleryCell(bonus: bonus)
                            }
                            .buttonStyle(CTCardPressStyle())
                            .ctStagger(gridAppeared, index: min(index, 16))
                        }
                    }
                    .ctTriggerAppear($gridAppeared)
                }
            }
            .padding()
        }
        .ctScreen()
        .navigationTitle(language.t.galleryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $lightboxBonus) { bonus in
            BonusLightboxView(bonus: bonus) {
                lightboxBonus = nil
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            sortControls
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(StatsFilter.Period.allCases.filter { $0 != .visit }) { p in
                        filterChip(p.label, selected: period == p) { period = p }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    filterChip(language.t.galleryAllCasinos, selected: casinoLegacyId == nil) { casinoLegacyId = nil }
                    ForEach(casinos) { c in
                        filterChip(c.name, selected: casinoLegacyId == c.legacyId) {
                            casinoLegacyId = c.legacyId
                        }
                    }
                }
            }
            if !machineNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        filterChip(language.t.galleryAllMachines, selected: machineName == nil) { machineName = nil }
                        ForEach(machineNames, id: \.self) { name in
                            filterChip(name, selected: machineName == name) { machineName = name }
                        }
                    }
                }
            }
            if !bonusTypes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        filterChip(language.t.galleryAllTypes, selected: bonusTypeId == nil) { bonusTypeId = nil }
                        ForEach(bonusTypes) { type in
                            filterChip(type.name, selected: bonusTypeId == type.persistentModelID) {
                                bonusTypeId = type.persistentModelID
                            }
                        }
                    }
                }
            }
            Text(language.t.photosCount(filtered.count))
                .font(.caption)
                .foregroundStyle(CTTheme.muted)
        }
    }

    private var sortControls: some View {
        HStack(spacing: 10) {
            Picker(language.t.gallerySort, selection: $sortKey) {
                ForEach(GallerySortKey.allCases) { key in
                    Text(key.label).tag(key)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: sortKey) { _, _ in
                sortDescending = true
            }

            Button {
                sortDescending.toggle()
            } label: {
                Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CTTheme.gold)
                    .frame(width: CTTheme.minTap, height: CTTheme.minTap)
                    .background(CTTheme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sortDescending ? language.t.galleryDescending : language.t.galleryAscending)
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(selected ? CTTheme.gold.opacity(0.25) : CTTheme.bgElevated)
                .overlay(Capsule().strokeBorder(selected ? CTTheme.gold : .clear, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func matchesPeriod(_ date: Date) -> Bool {
        let cal = CTDates.calendar
        let now = Date()
        switch period {
        case .all, .visit:
            return true
        case .days30:
            guard let start = cal.date(byAdding: .day, value: -30, to: now) else { return true }
            return date >= start
        case .month:
            return cal.isDate(date, equalTo: now, toGranularity: .month)
        case .year:
            return cal.isDate(date, equalTo: now, toGranularity: .year)
        }
    }
}

private struct GalleryCell: View {
    @Environment(LanguageStore.self) private var language
    let bonus: BonusEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                CTTheme.felt
                if let img = bonus.resolvedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(CTTheme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(bonus.session?.machineName ?? language.t.machine)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(bonus.typeLabel)
                .font(.caption)
                .foregroundStyle(CTTheme.champagne)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(MoneyMath.formatEUR(bonus.winAmount))
                    .foregroundStyle(CTTheme.win)
                    .fontWeight(.semibold)
                Text(MoneyMath.formatMultiplier(bonus.multiplier))
                    .foregroundStyle(CTTheme.gold)
            }
            .font(.caption)
            .monospacedDigit()
            if let casino = bonus.session?.visit?.casino?.name {
                Text(casino)
                    .font(.caption2)
                    .foregroundStyle(CTTheme.muted)
                    .lineLimit(1)
            }
            Text(CTDates.string(bonus.at, date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(CTTheme.muted)
        }
        .padding(10)
        .background(CTTheme.bgElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct BonusLightboxView: View {
    @Environment(LanguageStore.self) private var language
    let bonus: BonusEvent
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(CTTheme.ink.opacity(0.9))
                            .frame(minWidth: CTTheme.minTap, minHeight: CTTheme.minTap)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                Spacer(minLength: 0)

                if let img = bonus.resolvedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(CTTheme.muted)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text(bonus.session?.machineName ?? language.t.machine)
                        .font(.headline)
                    Text(bonus.typeLabel)
                        .font(.subheadline)
                        .foregroundStyle(CTTheme.champagne)
                    HStack(spacing: 10) {
                        Text(MoneyMath.formatEUR(bonus.winAmount))
                            .foregroundStyle(CTTheme.win)
                            .fontWeight(.semibold)
                        Text(MoneyMath.formatMultiplier(bonus.multiplier))
                            .foregroundStyle(CTTheme.gold)
                    }
                    .monospacedDigit()
                    if let casino = bonus.session?.visit?.casino?.name {
                        Text(casino)
                            .font(.caption)
                            .foregroundStyle(CTTheme.muted)
                    }
                    Text(CTDates.string(bonus.at, date: .complete, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(CTTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(CTTheme.bg.opacity(0.92))
            }
            .foregroundStyle(CTTheme.ink)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}
