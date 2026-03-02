import SwiftUI

struct BoroughPickerView: View {
    @EnvironmentObject var binStore: BinStore
    @Environment(\.dismiss) var dismiss
    @State private var postcode: String = ""
    @State private var houseNumber: String = ""
    @State private var isSaving = false

    // Borough detection state
    @State private var detectedBorough: Borough?
    @State private var isDetectingBorough = false
    @State private var boroughError: String?

    // Address lookup state
    @State private var isLoadingAddresses = false
    @State private var addresses: [Address] = []
    @State private var selectedAddress: Address?
    @State private var addressLookupError: String?

    private var postcodeIsValid: Bool {
        let trimmed = postcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return false }
        let pattern = #"^[A-Za-z]{1,2}\d[A-Za-z\d]?\s*\d[A-Za-z]{2}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private var canSave: Bool {
        guard let borough = detectedBorough, borough.isSupported else { return false }
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
                        postcodeSection

                        if postcodeIsValid {
                            lookupButton
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if let error = boroughError {
                            boroughErrorSection(error)
                        }

                        if let borough = detectedBorough {
                            boroughInfoSection(borough)

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
                    .animation(.easeInOut(duration: 0.3), value: postcodeIsValid)
                }

                saveButton
            }
        }
        .navigationTitle("Set Location")
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            detectedBorough = binStore.selectedBorough
            postcode = binStore.postcode
            houseNumber = binStore.houseNumber
            if !binStore.uprn.isEmpty {
                selectedAddress = Address(uprn: binStore.uprn, address: "Previously saved address")
            }
        }
    }

    // MARK: - Postcode Section

    private var postcodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("POSTCODE")
                .foregroundStyle(.white.opacity(0.4))

            HStack {
                Image(systemName: "mappin")
                    .foregroundStyle(.green)
                    .frame(width: 20)

                TextField("e.g. N1 2AB", text: $postcode)
                    .textContentType(.postalCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .onSubmit { Task { await detectBorough() } }
                    .onChange(of: postcode) { _, _ in
                        // Reset detected borough when postcode changes
                        detectedBorough = nil
                        boroughError = nil
                        addresses = []
                        selectedAddress = nil
                        addressLookupError = nil
                    }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    // MARK: - Lookup Button

    private var lookupButton: some View {
        Button {
            Task { await detectBorough() }
        } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.green)
                    .frame(width: 20)

                if isDetectingBorough {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text("Looking up postcode...")
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
        .disabled(postcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDetectingBorough)
    }

    // MARK: - Borough Error

    private func boroughErrorSection(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(error)
                .font(.caption2)
                .foregroundStyle(.orange.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Borough Info

    private func boroughInfoSection(_ borough: Borough) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "building.2")
                .foregroundStyle(.green)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("BOROUGH")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.3))
                Text(borough.displayName)
                    .foregroundStyle(.white)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.08))
        )
    }

    // MARK: - House Number Section

    private var houseNumberSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("HOUSE NUMBER / NAME")
                .foregroundStyle(.white.opacity(0.4))

            HStack {
                Image(systemName: "house")
                    .foregroundStyle(.green)
                    .frame(width: 20)

                TextField("e.g. 42 or Flat 3", text: $houseNumber)
                    .textContentType(.streetAddressLine1)
                    .textInputAutocapitalization(.words)
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

    // MARK: - Address Lookup Section

    private var addressLookupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("YOUR ADDRESS")
                .foregroundStyle(.white.opacity(0.4))

            // Loading indicator while fetching addresses
            if isLoadingAddresses {
                HStack {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text("Searching addresses...")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))
                )
            }

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

    // MARK: - Help Section

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("HELP")
                .foregroundStyle(.white.opacity(0.4))

            if detectedBorough?.inputRequirement.needsAddressSelection == true {
                Text("Your borough was detected automatically. Select your address from the list above to set up your bin collection schedule.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
            } else {
                Text("Your borough was detected automatically. Enter your house number to look up your bin collection schedule.")
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
                } else if let borough = detectedBorough, canSave {
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

    private func detectBorough() async {
        let cleanPostcode = postcode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanPostcode.isEmpty else { return }

        isDetectingBorough = true
        boroughError = nil
        detectedBorough = nil
        addresses = []
        selectedAddress = nil
        addressLookupError = nil

        do {
            let borough = try await AddressLookupService.shared.lookupBorough(postcode: cleanPostcode)
            detectedBorough = borough

            // Automatically fetch addresses for boroughs that need address selection
            if borough.inputRequirement.needsAddressSelection {
                await findAddresses(borough: borough, postcode: cleanPostcode)
            }
        } catch {
            boroughError = error.localizedDescription
        }

        isDetectingBorough = false
    }

    private func findAddresses(borough: Borough, postcode: String) async {
        isLoadingAddresses = true
        addressLookupError = nil

        do {
            let results = try await AddressLookupService.shared.lookupAddresses(
                postcode: postcode,
                borough: borough
            )
            addresses = results
            if results.isEmpty {
                addressLookupError = "No addresses found for this postcode. Check the postcode and try again."
            } else if results.count == 1 {
                selectedAddress = results.first
            }
        } catch {
            addressLookupError = "Could not look up addresses: \(error.localizedDescription)"
        }

        isLoadingAddresses = false
    }

    private func save() {
        guard let borough = detectedBorough else { return }
        isSaving = true

        binStore.selectedBorough = borough
        binStore.postcode = postcode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        binStore.houseNumber = houseNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        if let address = selectedAddress {
            binStore.uprn = address.uprn
        } else {
            binStore.uprn = ""
        }

        isSaving = false
        dismiss()
    }
}
