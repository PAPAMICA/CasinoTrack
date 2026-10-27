import SwiftUI
import SwiftData
import PhotosUI

struct MachineEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    @Query(sort: [SortDescriptor(\MachineType.sortOrder), SortDescriptor(\MachineType.name)])
    private var machineTypes: [MachineType]
    @Query(sort: [SortDescriptor(\BonusType.sortOrder), SortDescriptor(\BonusType.name)])
    private var bonusTypes: [BonusType]
    @Query(sort: \Casino.name) private var casinos: [Casino]

    var machine: Machine?

    @State private var name = ""
    @State private var manufacturer = ""
    @State private var notes = ""
    @State private var bonusFeatures = ""
    @State private var defaultBetText = ""
    @State private var hasJackpot = false
    @State private var isFavorite = false
    @State private var selectedType: MachineType?
    @State private var selectedBonusIDs: Set<PersistentIdentifier> = []
    @State private var selectedCasinoIDs: Set<PersistentIdentifier> = []
    @State private var photoPath: String?
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showDeleteConfirm = false
    @State private var showBetPad = false
    @State private var padAmount = 0.0

    init(machine: Machine? = nil) {
        self.machine = machine
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(language.t.catalogIdentity) {
                    TextField(language.t.catalogName, text: $name)
                    TextField(language.t.catalogManufacturer, text: $manufacturer)
                    Picker(language.t.type, selection: $selectedType) {
                        Text(language.t.none).tag(Optional<MachineType>.none)
                        ForEach(machineTypes) { t in
                            Text(t.name).tag(Optional(t))
                        }
                    }
                    Toggle("Jackpot", isOn: $hasJackpot)
                    Toggle(language.t.catalogFavorite, isOn: $isFavorite)
                }
                Section("Mise & notes") {
                    Button {
                        padAmount = MoneyMath.toNumber(defaultBetText)
                        showBetPad = true
                    } label: {
                        HStack {
                            Text("Mise par défaut")
                            Spacer()
                            Text(defaultBetText.isEmpty ? "-" : MoneyMath.formatEUR(MoneyMath.toNumber(defaultBetText)))
                                .foregroundStyle(CTTheme.gold)
                        }
                    }
                    TextField("Bonus / features", text: $bonusFeatures, axis: .vertical)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section("Bonus associés") {
                    ForEach(bonusTypes) { t in
                        Button {
                            toggle(t.persistentModelID, in: &selectedBonusIDs)
                        } label: {
                            HStack {
                                Circle().fill(Color(hexString: t.colorHex)).frame(width: 10, height: 10)
                                Text(t.name).foregroundStyle(CTTheme.ink)
                                Spacer()
                                if selectedBonusIDs.contains(t.persistentModelID) {
                                    Image(systemName: "checkmark").foregroundStyle(CTTheme.gold)
                                }
                            }
                        }
                    }
                }
                Section(language.t.casinos) {
                    ForEach(casinos) { c in
                        Button {
                            toggle(c.persistentModelID, in: &selectedCasinoIDs)
                        } label: {
                            HStack {
                                Text(c.name).foregroundStyle(CTTheme.ink)
                                Spacer()
                                if selectedCasinoIDs.contains(c.persistentModelID) {
                                    Image(systemName: "checkmark").foregroundStyle(CTTheme.gold)
                                }
                            }
                        }
                    }
                }
                Section("Photo") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text(photoPath == nil ? "Ajouter une photo" : "Changer la photo")
                        }
                    }
                    if let img = PhotoStore.image(data: photoData, path: photoPath) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button("Retirer la photo", role: .destructive) {
                            self.photoPath = nil
                            self.photoData = nil
                        }
                    }
                }
                if machine != nil {
                    Section {
                        Button(language.t.catalogDeleteMachineAction, role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CTTheme.bg)
            .navigationTitle(machine == nil ? language.t.catalogNewMachine : language.t.catalogEditMachine)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.t.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.t.save) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let item,
                          let data = try? await item.loadTransferable(type: Data.self),
                          let ui = UIImage(data: data),
                          let jpeg = ui.jpegData(compressionQuality: 0.75) else { return }
                    photoData = jpeg
                    photoPath = try? PhotoStore.saveJPEG(jpeg, folder: "machines")
                }
            }
            .sheet(isPresented: $showBetPad) {
                BetMoneyPadSheet(
                    title: "Mise par défaut",
                    amount: $padAmount,
                    preferredUnit: MoneyMath.toNumber(defaultBetText) > 0
                        ? MoneyMath.toNumber(defaultBetText) : nil
                ) {
                    defaultBetText = padAmount > 0 ? String(format: "%.2f", padAmount) : ""
                }
            }
            .confirmationDialog(
                language.t.catalogDeleteMachineTitle,
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(language.t.delete, role: .destructive) { deleteMachine() }
                Button(language.t.cancel, role: .cancel) {}
            } message: {
                Text("Les sessions liées garderont le nom, sans lien catalogue.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        guard let machine else { return }
        name = machine.name
        manufacturer = machine.manufacturer ?? ""
        notes = machine.notes ?? ""
        bonusFeatures = machine.bonusFeatures ?? ""
        if let bet = machine.defaultBet { defaultBetText = String(format: "%.2f", bet) }
        hasJackpot = machine.hasJackpot
        isFavorite = machine.isFavorite
        selectedType = machine.machineType
        selectedBonusIDs = Set(machine.bonusTypes.map(\.persistentModelID))
        selectedCasinoIDs = Set(machine.casinos.map(\.persistentModelID))
        photoPath = machine.photoPath
        photoData = machine.photoData
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: Machine
        if let machine {
            target = machine
        } else {
            let created = Machine(name: trimmed)
            context.insert(created)
            target = created
        }
        target.name = trimmed
        target.manufacturer = manufacturer.nilIfEmpty
        target.notes = notes.nilIfEmpty
        target.bonusFeatures = bonusFeatures.nilIfEmpty
        target.defaultBet = defaultBetText.isEmpty ? nil : MoneyMath.toNumber(defaultBetText)
        target.hasJackpot = hasJackpot
        target.isFavorite = isFavorite
        target.machineType = selectedType
        target.bonusTypes = bonusTypes.filter { selectedBonusIDs.contains($0.persistentModelID) }
        target.casinos = casinos.filter { selectedCasinoIDs.contains($0.persistentModelID) }
        target.photoPath = photoPath
        target.photoData = photoData
        try? context.save()
        dismiss()
    }

    private func deleteMachine() {
        if let machine {
            context.delete(machine)
            try? context.save()
        }
        dismiss()
    }

    private func toggle(_ id: PersistentIdentifier, in set: inout Set<PersistentIdentifier>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
}

// Fix broken save() - rewrite MachineEditorSheet save cleanly by patching file
extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

struct CasinoEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language

    var casino: Casino?

    @State private var name = ""
    @State private var city = ""
    @State private var address = ""
    @State private var website = ""
    @State private var isFavorite = false
    @State private var showDeleteConfirm = false

    init(casino: Casino? = nil) {
        self.casino = casino
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(language.t.casino) {
                    TextField(language.t.catalogName, text: $name)
                    TextField(language.t.catalogCity, text: $city)
                    TextField("Adresse", text: $address, axis: .vertical)
                    TextField("Site web", text: $website)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Toggle(language.t.catalogFavorite, isOn: $isFavorite)
                }
                if let casino {
                    Section {
                        Text("\(casino.visits.count) sortie(s) liée(s)")
                            .foregroundStyle(CTTheme.muted)
                        Button(language.t.catalogDeleteCasinoAction, role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CTTheme.bg)
            .navigationTitle(casino == nil ? language.t.catalogNewCasino : language.t.catalogEditCasino)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.t.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.t.save) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard let casino else { return }
                name = casino.name
                city = casino.city ?? ""
                address = casino.address ?? ""
                website = casino.website ?? ""
                isFavorite = casino.isFavorite
            }
            .confirmationDialog(
                language.t.catalogDeleteCasinoTitle,
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(language.t.delete, role: .destructive) { deleteCasino() }
                Button(language.t.cancel, role: .cancel) {}
            } message: {
                Text(casino?.visits.isEmpty == false
                     ? "Les sorties liées garderont un casino vide."
                     : "Cette action est définitive.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: Casino
        if let casino {
            target = casino
        } else {
            let created = Casino(name: trimmed, source: "manual")
            context.insert(created)
            target = created
        }
        target.name = trimmed
        target.city = city.nilIfEmpty
        target.address = address.nilIfEmpty
        target.website = website.nilIfEmpty
        target.isFavorite = isFavorite
        try? context.save()
        dismiss()
    }

    private func deleteCasino() {
        if let casino {
            context.delete(casino)
            try? context.save()
        }
        dismiss()
    }
}
