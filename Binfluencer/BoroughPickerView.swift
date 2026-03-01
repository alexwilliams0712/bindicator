import SwiftUI

struct BoroughPickerView: View {
    @EnvironmentObject var binStore: BinStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedBorough: Borough?
    @State private var postcode: String = ""
    @State private var houseNumber: String = ""
    @State private var isSaving = false

    // Address lookup state
    @State private var isLoadingAddresses = false
    @State private var addresses: [Address] = []
    @State private var selectedAddress: Address?
    @State private var addressLookupError: String?

    private var canSave: Bool {
        guard let borough = selectedBorough, borough.isSupported else { return false }
        switch borough.inputRequirement {
        case .postcodeAndAddressSelect:
            return !postcode.isEmpty && selectedAddress != nil
        case .postcodeAndNumber:
            return !postcode.isEmpty
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
                            postcodeSection

                            if borough.inputRequirement.needsAddressSelection {
                                addressLookupSection
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
            houseNumber = binStore.houseNumber
            // If there's a stored UPRN, try to pre-select it
            if !binStore.uprn.isEmpty {
                selectedAddress = Address(uprn: binStore.uprn, address: "Previously saved address")
            }
        }
        .onChange(of: selectedBorough) { _, _ in
            // Reset address lookup when borough changes
            addresses = []
            selectedAddress = nil
            addressLookupError = nil
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

    // MARK: - Address Lookup Section

    private var addressLookupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("YOUR ADDRESS")
                .foregroundStyle(.white.opacity(0.4))

            // Find Address button
            Button {
                Task { await findAddresses() }
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.green)
                        .frame(width: 20)

                    if isLoadingAddresses {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                        Text("Searching...")
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        Text("Find my address")
                            .foregroundStyle(.white)
                    }

                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))
                )
            }
            .disabled(postcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingAddresses)

            // Error message
            if let error = addressLookupError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.7))
            }

            // Address picker (shown after lookup)
            if !addresses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(addresses.count) address\(addresses.count == 1 ? "" : "es") found")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.25))

                    HStack {
                        Image(systemName: "house")
                            .foregroundStyle(.green)
                            .frame(width: 20)

                        Menu {
                            ForEach(addresses) { address in
                                Button(address.address) {
                                    withAnimation { selectedAddress = address }
                                }
                            }
                        } label: {
                            if let address = selectedAddress, address.address != "Previously saved address" {
                                Text(address.address)
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            } else {
                                Text("Select your address")
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
                            .fill(selectedAddress != nil
                                  ? Color.green.opacity(0.08)
                                  : Color.white.opacity(0.06))
                    )
                }
            }

            // Selected address confirmation
            if let address = selectedAddress, address.address != "Previously saved address" {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(address.address)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
        }
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

            if selectedBorough?.inputRequirement.needsAddressSelection == true {
                Text("Enter your postcode and tap \"Find my address\" to see a list of addresses. Select yours to set up your bin collection schedule.")
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

    private func findAddresses() async {
        guard let borough = selectedBorough else { return }
        let cleanPostcode = postcode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanPostcode.isEmpty else { return }

        isLoadingAddresses = true
        addressLookupError = nil
        addresses = []
        selectedAddress = nil

        do {
            let results = try await AddressLookupService.shared.lookupAddresses(
                postcode: cleanPostcode,
                borough: borough
            )
            addresses = results
            if results.isEmpty {
                addressLookupError = "No addresses found for this postcode. Check the postcode and try again."
            } else if results.count == 1 {
                // Auto-select if there's only one result
                selectedAddress = results.first
            }
        } catch {
            addressLookupError = "Could not look up addresses: \(error.localizedDescription)"
        }

        isLoadingAddresses = false
    }

    private func save() {
        guard let borough = selectedBorough else { return }
        isSaving = true

        binStore.selectedBorough = borough
        binStore.postcode = postcode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        binStore.houseNumber = houseNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        // Store the UPRN from the selected address (for boroughs that need it)
        if let address = selectedAddress {
            binStore.uprn = address.uprn
        } else {
            binStore.uprn = ""
        }

        isSaving = false
        dismiss()
    }
}
