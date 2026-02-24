import SwiftUI

struct ContentView: View {
    @EnvironmentObject var binStore: BinStore
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var groupedCollections: [(BinType, BinCollection)] {
        var seen = Set<BinType>()
        return binStore.collections.compactMap { collection in
            guard !seen.contains(collection.binType) else { return nil }
            seen.insert(collection.binType)
            return (collection.binType, collection)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if !binStore.isConfigured {
                    setupPrompt
                } else if isLoading && binStore.collections.isEmpty {
                    ProgressView()
                        .tint(.green)
                } else if let error = errorMessage, binStore.collections.isEmpty {
                    errorView(error)
                } else {
                    mainContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Binfluencer")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.5))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: BoroughPickerView()) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.green)
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .refreshable { await loadCollections() }
        }
        .preferredColorScheme(.dark)
        .task {
            if binStore.isConfigured {
                await loadCollections()
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let borough = binStore.selectedBorough {
                    Text(borough.displayName.uppercased())
                        .font(.caption)
                        .fontWeight(.medium)
                        .tracking(2)
                        .foregroundStyle(.green)
                        .padding(.top, 24)
                }

                if let next = groupedCollections.first {
                    nextCollectionCard(next.0, next.1)
                        .padding(.top, 32)
                }

                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(height: 2)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)

                VStack(spacing: 16) {
                    ForEach(groupedCollections, id: \.1.id) { binType, collection in
                        collectionRow(binType, collection)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

                if isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.white.opacity(0.3))
                        Text("Updating...")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: - Next Collection Card

    private func nextCollectionCard(_ binType: BinType, _ collection: BinCollection) -> some View {
        VStack(spacing: 12) {
            Text(collection.dayLabel)
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            HStack(spacing: 8) {
                Image(systemName: binType.icon)
                    .font(.caption)
                Text(binType.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(2)
            }
            .foregroundStyle(binType.color)

            if collection.daysUntil == 0 {
                Text("Put your bins out!")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            } else if collection.daysUntil == 1 {
                Text("Put your bins out tonight")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Collection Row

    private func collectionRow(_ binType: BinType, _ collection: BinCollection) -> some View {
        HStack {
            Image(systemName: binType.icon)
                .font(.body)
                .foregroundStyle(binType.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(binType.displayName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text(collection.rawType)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(collection.dayLabel)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(collection.isUrgent ? binType.color : .white.opacity(0.7))
                if collection.daysUntil > 0 {
                    Text("\(collection.daysUntil)d")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Setup Prompt

    private var setupPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green.opacity(0.6))

            Text("Set up your borough")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))

            Text("Select your London borough and enter your address details to see your bin collection schedule.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            NavigationLink(destination: BoroughPickerView()) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.green)
                    )
            }
        }
        .padding(32)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.title)
                .foregroundStyle(.white.opacity(0.3))
            Text(error)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadCollections() } }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.green)
        }
        .padding()
    }

    // MARK: - Data Loading

    private func loadCollections() async {
        guard let borough = binStore.selectedBorough else { return }

        isLoading = true
        errorMessage = nil

        do {
            let collections = try await BinCollectionService.shared.fetchCollections(
                borough: borough,
                postcode: binStore.postcode,
                uprn: binStore.uprn.isEmpty ? nil : binStore.uprn,
                houseNumber: binStore.houseNumber.isEmpty ? nil : binStore.houseNumber
            )
            binStore.collections = collections
            binStore.updateLastFetch()
        } catch is CancellationError {
            // Ignore
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
