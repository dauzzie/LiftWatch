import SwiftUI

struct IOSTabView: View {
    var body: some View {
        TabView {
            IOSContentView()
                .tabItem {
                    Label("Workouts", systemImage: "list.bullet.rectangle")
                }

            IOSHistoryView()
                .tabItem {
                    Label("History", systemImage: "chart.bar.fill")
                }

            IOSSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

#Preview {
    IOSTabView()
        .environmentObject(ExerciseStore())
        .environmentObject(WatchSyncManager())
        .environmentObject(CloudSyncManager())
}
