import SwiftUI

@main
struct LiftWatchWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = ExerciseStore()
    @StateObject private var sync = WatchSyncManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
                .environmentObject(sync)
                .task {
                    sync.start(store: store)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        store.appDidBecomeActive()
                        sync.appDidBecomeActive()
                    }
                }
        }
    }
}
