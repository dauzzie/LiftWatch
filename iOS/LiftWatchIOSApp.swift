import SwiftUI

@main
struct LiftWatchIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = ExerciseStore()
    @StateObject private var sync = WatchSyncManager()
    @StateObject private var cloud = CloudSyncManager()
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    var body: some Scene {
        WindowGroup {
            IOSTabView()
                .environmentObject(store)
                .environmentObject(sync)
                .environmentObject(cloud)
                .task {
                    sync.start(store: store)
                    if !isRunningTests {
                        cloud.start(store: store)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        store.appDidBecomeActive()
                        sync.sendAll()
                        if !isRunningTests {
                            cloud.appDidBecomeActive()
                        }
                    }
                }
        }
    }
}
