import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct BonusEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var language
    var session: MachineSession
    /// Catalogue complet (fallback si la machine n’a aucun bonus lié).
    var bonusTypes: [BonusType]
    /// Machine catalogue (sinon `session.catalogMachine`).
    var machine: Machine? = nil

    @State private var selected: Set<PersistentIdentifier> = []
    @State private var winText = ""
    @State private var betText = ""
    @State private var showWinPad = false
    @State private var showBetPad = false
    @State private var padAmount = 0.0
    @State private var padSource: BudgetSource = .liquide
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPath: String?
    @State private var photoData: Data?
    @State private var showCamera = false
    @State private var cameraImage: UIImage?

    private var resolvedMachine: Machine? { machine ?? session.catalogMachine }

    private var machineLinkedTypes: [BonusType] {
        let linked = resolvedMachine?.bonusTypes ?? []
        return linked.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var usingFullCatalog: Bool { machineLinkedTypes.isEmpty }

    private var availableBonusTypes: [BonusType] {
        usingFullCatalog ? bonusTypes : machineLinkedTypes
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(session.machineName)
                        .font(.headline)
                        .foregroundStyle(CTTheme.muted)

                    Text(language.t.bonusTypes)
                        .font(.subheadline.weight(.semibold))
                    if usingFullCatalog {
                        Text(language.t.bonusNoMachineTypes)
                            .font(.caption)
                            .foregroundStyle(CTTheme.muted)
                    }
                    FlowBonusChips(types: availableBonusTypes, selected: $selected)

                    Button {
                        padAmount = MoneyMath.toNumber(winText)
                        showWinPad = true
                    } label: {
                        fieldLabel(language.t.bonusWin, MoneyMath.formatEUR(MoneyMath.toNumber(winText)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        padAmount = MoneyMath.toNumber(betText)
                        showBetPad = true
                    } label: {
                        fieldLabel(language.t.bonusBet, betText.isEmpty ? "-" : MoneyMath.formatEUR(MoneyMath.toNumber(betText)))
                    }
                    .buttonStyle(.plain)

                    photoSection

                    PrimaryButton(title: language.t.bonusSave, icon: "sparkles") { save() }
                }
                .padding()
            }
            .ctScreen()
            .navigationTitle(language.t.bonus)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.t.close) { dismiss() } }
            }
            .sheet(isPresented: $showWinPad) {
                MoneyPadSheet(title: language.t.bonusWin, amount: $padAmount, sources: nil, source: $padSource) {
                    winText = String(format: "%.2f", padAmount)
                }
            }
            .sheet(isPresented: $showBetPad) {
                BetMoneyPadSheet(
                    title: language.t.bonusBet,
                    amount: $padAmount,
                    preferredUnit: session.catalogMachine?.defaultBet ?? session.betSetting
                ) {
                    betText = String(format: "%.2f", padAmount)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker(image: $cameraImage)
                    .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let item,
                          let data = try? await item.loadTransferable(type: Data.self) else { return }
                    applyPhoto(UIImage(data: data))
                }
            }
            .onChange(of: cameraImage) { _, image in
                applyPhoto(image)
            }
            .onAppear {
                if let bet = session.betSetting {
                    betText = String(format: "%.2f", bet)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    photoIconButton(systemName: "camera.fill")
                }
                .buttonStyle(.plain)
                .disabled(!cameraAvailable)
                .opacity(cameraAvailable ? 1 : 0.4)
                .accessibilityLabel(language.t.bonusCameraA11y)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    photoIconButton(systemName: "photo.on.rectangle")
                }
                .accessibilityLabel(language.t.bonusLibraryA11y)
            }

            if let img = PhotoStore.image(data: photoData, path: photoPath) {
                HStack(spacing: 12) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button {
                        photoData = nil
                        photoPath = nil
                        photoItem = nil
                        cameraImage = nil
                    } label: {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundStyle(CTTheme.lose)
                            .frame(width: CTTheme.minTap, height: CTTheme.minTap)
                            .background(CTTheme.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.t.bonusDeletePhotoA11y)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func photoIconButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(CTTheme.gold)
            .frame(maxWidth: .infinity)
            .frame(minHeight: CTTheme.minTap)
            .background(CTTheme.felt.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func applyPhoto(_ image: UIImage?) {
        guard let image, let jpeg = PhotoStore.jpegData(from: image) else { return }
        photoData = jpeg
        photoPath = try? PhotoStore.saveJPEG(jpeg)
    }

    private func fieldLabel(_ title: String, _ value: String) -> some View {
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

    private func save() {
        let types = availableBonusTypes.filter { selected.contains($0.persistentModelID) }
        // Ne pas s’appuyer uniquement sur l’inverse `BonusEvent.session` : SwiftData peut
        // remplir la relation sans invalider l’observation SwiftUI de `session.bonuses`.
        let event = BonusEvent(
            winAmount: MoneyMath.toNumber(winText),
            betAmount: betText.isEmpty ? nil : MoneyMath.toNumber(betText),
            photoPath: photoPath,
            photoData: photoData,
            session: nil,
            types: types
        )
        context.insert(event)
        session.bonuses.append(event)
        try? context.save()
        dismiss()
    }
}

private struct FlowBonusChips: View {
    let types: [BonusType]
    @Binding var selected: Set<PersistentIdentifier>

    var body: some View {
        FlexibleChipWrap {
            ForEach(types) { type in
                BonusChip(type: type, selected: selected.contains(type.persistentModelID)) {
                    if selected.contains(type.persistentModelID) {
                        selected.remove(type.persistentModelID)
                    } else {
                        selected.insert(type.persistentModelID)
                    }
                }
            }
        }
    }
}

/// Simple wrapping layout for chips
struct FlexibleChipWrap<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Fallback: LazyVGrid works well enough for taps
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            content()
        }
    }
}
