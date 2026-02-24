import SwiftUI

@main
struct BinfluencerApp: App {
    @StateObject private var binStore = BinStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(binStore)
        }
    }
}
