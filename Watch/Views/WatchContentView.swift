import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var store: ExerciseStore
    @EnvironmentObject private var sync: WatchSyncManager
    @State private var isPresentingAdd = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    isPresentingAdd = true
                } label: {
                    Label("Log Workout", systemImage: "plus.circle.fill")
                }
                .accessibilityHint("Opens the new workout form.")

                VStack(alignment: .leading, spacing: 2) {
                    Text(sync.syncStatus)
                        .font(.caption2)
                        .foregroundStyle(syncColor)
                    if !sync.syncDetail.isEmpty {
                        Text(sync.syncDetail)
                            .font(.caption2)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sync status")
                .accessibilityValue(sync.syncStatus)
                .accessibilityHint(sync.syncDetail)

                ForEach(store.logs) { log in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(
                                ExerciseNaming.displayName(name: log.name, symbol: log.symbol, category: log.category),
                                systemImage: log.symbol
                            )
                                .font(.subheadline)
                                .foregroundStyle(WorkoutColors.color(for: log))
                                .lineLimit(2)
                            Text(summary(for: log))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Button {
                            store.remove(id: log.id)
                            sync.sendAll()
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete workout")
                        .accessibilityHint("Removes this workout entry.")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sync.syncBidirectional()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityLabel("Sync workouts")
                    .accessibilityHint("Synchronizes workouts with iPhone.")
                }
            }
            .sheet(isPresented: $isPresentingAdd) {
                WatchAddExerciseView { log in
                    store.add(log)
                    sync.send(log: log)
                }
            }
        }
    }

    private func summary(for log: ExerciseLog) -> String {
        ExerciseLogSummaryFormatter.summary(
            for: log,
            preferredUnit: store.settings.preferredWeightUnit,
            style: .watch
        )
    }

    private var syncColor: Color { sync.syncLevel.tintColor }
}

#Preview {
    WatchContentView()
        .environmentObject(ExerciseStore())
        .environmentObject(WatchSyncManager())
}
