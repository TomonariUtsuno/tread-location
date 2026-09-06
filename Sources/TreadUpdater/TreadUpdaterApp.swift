import SwiftUI

@main
struct TreadUpdaterApp: App {
    @StateObject private var store = DraftStore()

    var body: some Scene {
        WindowGroup("Tread Updater") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1_120, minHeight: 720)
        }
    }
}
