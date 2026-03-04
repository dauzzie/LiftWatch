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

                Text(sync.syncStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(store.logs) { log in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(log.name, systemImage: log.symbol)
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
                    }
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
        switch log.category {
        case .weightlifting:
            let setsText = "\(log.sets ?? 0)x\(log.reps ?? 0)"
            let weightText = (log.weight ?? 0).formatted(.number.precision(.fractionLength(0...1))) + "lb"
            let group = log.weightliftingCategory?.title ?? "Lift"
            return "\(group) • \(setsText) @ \(weightText)"
        case .cardio:
            let minutesText = "\(log.minutes ?? 0)m"
            if let pace = log.pace, !pace.isEmpty {
                return "\(minutesText) • Avg \(pace)"
            }
            return minutesText
        }
    }
}

#Preview {
    WatchContentView()
        .environmentObject(ExerciseStore())
        .environmentObject(WatchSyncManager())
}
