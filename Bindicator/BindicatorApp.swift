import SwiftUI

@main
struct BindicatorApp: App {
    @StateObject private var binStore = BinStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(binStore)
        }
    }
}
