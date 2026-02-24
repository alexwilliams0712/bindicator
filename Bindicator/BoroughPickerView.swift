import SwiftUI

struct BoroughPickerView: View {
    @EnvironmentObject var binStore: BinStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedBorough: Borough?
    @State private var postcode: String = ""
    @State private var uprn: String = ""
    @State private var houseNumber: String = ""
    @State private var isSaving = false

    private var canSave: Bool {
        guard let borough = selectedBorough, borough.isSupported else { return false }
        switch borough.inputRequirement {
        case .uprn: return !uprn.isEmpty
        case .postcodeAndUPRN: return !postcode.isEmpty && !uprn.isEmpty
        case .postcodeAndNumber: return !postcode.isEmpty
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 28) {
                        boroughSection

                        if let borough = selectedBorough, borough.isSupported {
                            if borough.inputRequirement.needsPostcode {
                                postcodeSection
                            }
                            if borough.inputRequirement.needsUPRN {
                                uprnSection
                            }
                            if borough.inputRequirement.needsHouseNumber {
                                houseNumberSection
                            }

                            helpSection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }

                saveButton
            }
        }
        .navigationTitle("Set Location")
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            selectedBorough = binStore.selectedBorough
            postcode = binStore.postcode
            uprn = binStore.uprn
            houseNumber = binStore.houseNumber
        }
    }

    // MARK: - Borough Section

    private var boroughSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("BOROUGH")
                .foregroundStyle(.white.opacity(0.4))

            HStack {
                Image(systemName: "building.2")
                    .foregroundStyle(.green)
                    .frame(width: 20)

                Menu {
                    Section("Supported") {
                        ForEach(Borough.supported) { borough in
                            Button(borough.displayName) {
                                withAnimation { selectedBorough = borough }
                            }
                        }
                    }
                    Section("Coming Soon") {
                        ForEach(Borough.unsupported) { borough in
                            Button(borough.displayName) {}
                                .disabled(true)
                        }
                    }
                } label: {
                    if let borough = selectedBorough {
                        Text(borough.displayName)
                            .foregroundStyle(.white)
                    } else {
                        Text("Select a borough")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(.white.opacity(0.3))
                        .font(.caption)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
            )

            if let borough = selectedBorough, !borough.isSupported {
                Text("\(borough.displayName) requires browser automation and is not yet supported in the app.")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.7))
            }
        }
    }

    // MARK: - Input Sections

    private var postcodeSection: some View {
        inputSection(
            label: "POSTCODE",
            icon: "mappin",
            placeholder: "e.g. N1 2AB",
            text: $postcode,
            contentType: .postalCode,
            capitalization: .characters
        )
    }

    private var uprnSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("UPRN")
                .foregroundStyle(.white.opacity(0.4))

            HStack {
                Image(systemName: "number")
                    .foregroundStyle(.green)
                    .frame(width: 20)

                TextField("e.g. 100023456789", text: $uprn)
                    .keyboardType(.numberPad)
                    .foregroundStyle(.white)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
            )

            Text("Your UPRN is a 12-digit number. Find it at FindMyAddress.co.uk")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    private var houseNumberSection: some View {
        inputSection(
            label: "HOUSE NUMBER / NAME",
            icon: "house",
            placeholder: "e.g. 42 or Flat 3",
            text: $houseNumber,
            contentType: .streetAddressLine1,
            capitalization: .words
        )
    }

    private func inputSection(
        label: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType,
        capitalization: TextInputAutocapitalization
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(label)
                .foregroundStyle(.white.opacity(0.4))

            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.green)
                    .frame(width: 20)

                TextField(placeholder, text: text)
                    .textContentType(contentType)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    // MARK: - Help Section

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("HELP")
                .foregroundStyle(.white.opacity(0.4))

            if selectedBorough?.inputRequirement.needsUPRN == true {
                Text("Your UPRN (Unique Property Reference Number) identifies your specific address. You can find it by searching for your address at FindMyAddress.co.uk or on your council tax bill.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
            } else {
                Text("Enter your postcode and house number to look up your bin collection schedule.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button { save() } label: {
            HStack {
                Spacer()
                if isSaving {
                    ProgressView().tint(.white)
                } else if let borough = selectedBorough, canSave {
                    Text("Save \(borough.displayName)")
                } else {
                    Text("Save")
                }
                Spacer()
            }
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canSave ? Color.green : Color.white.opacity(0.08))
            )
        }
        .disabled(!canSave || isSaving)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .tracking(1.5)
    }

    private func save() {
        guard let borough = selectedBorough else { return }
        isSaving = true
        binStore.selectedBorough = borough
        binStore.postcode = postcode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        binStore.uprn = uprn.trimmingCharacters(in: .whitespacesAndNewlines)
        binStore.houseNumber = houseNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = false
        dismiss()
    }
}
