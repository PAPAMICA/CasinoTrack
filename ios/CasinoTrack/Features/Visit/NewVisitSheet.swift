import SwiftUI
import SwiftData

struct NewVisitSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @Query(sort: \Casino.name) private var allCasinos: [Casino]

    private var casinos: [Casino] {
        allCasinos.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    @State private var casino: Casino?
    @State private var query = ""
    @State private var startedAt = Date()
    @State private var notes = ""

    private var filteredCasinos: [Casino] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = casinos
        if q.isEmpty { return Array(base.prefix(40)) }
        return base.filter {
            $0.name.lowercased().contains(q)
                || ($0.city?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(language.t.casino) {
                    TextField(language.t.search, text: $query)
                    ForEach(filteredCasinos) { c in
                        Button {
                            casino = c
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.isFavorite ? "★ \(c.name)" : c.name)
                                        .foregroundStyle(CTTheme.ink)
                                    if let city = c.city, !city.isEmpty {
                                        Text(city)
                                            .font(.caption)
                                            .foregroundStyle(CTTheme.muted)
                                    }
                                }
                                Spacer()
                                if casino?.persistentModelID == c.persistentModelID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(CTTheme.gold)
                                }
                            }
                        }
                    }
                    if filteredCasinos.isEmpty {
                        Text(query.isEmpty ? language.t.newVisitNoCasino : language.t.newVisitNoResult)
                            .foregroundStyle(CTTheme.muted)
                    }
                }
                Section(language.t.newVisitWhen) {
                    DatePicker(language.t.date, selection: $startedAt)
                }
                Section(language.t.notes) {
                    TextField(language.t.optional, text: $notes, axis: .vertical)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CTTheme.bg)
            .navigationTitle(language.t.newVisitTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.t.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.t.newVisitStart) { create() }
                        .disabled(casino == nil)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if casino == nil { casino = casinos.first }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func create() {
        guard let casino else { return }
        let visit = Visit(
            startedAt: startedAt,
            plannedBudget: 0,
            notes: notes.isEmpty ? nil : notes,
            casino: casino
        )
        context.insert(visit)
        try? context.save()
        dismiss()
    }
}
