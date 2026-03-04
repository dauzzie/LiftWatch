import SwiftUI

struct IOSSettingsView: View {
    @EnvironmentObject private var store: ExerciseStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Day Reset") {
                    DatePicker(
                        "Reset Time",
                        selection: Binding(
                            get: { cutoffDate },
                            set: { store.updateCutoff(to: minutesSinceMidnight(for: $0)) }
                        ),
                        displayedComponents: .hourAndMinute
                    )

                    Text("Workouts are active from this time to the next day at the same time. At reset, current logs move to history and the active list clears.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Library") {
                    NavigationLink("Manage Custom Exercises") {
                        IOSExerciseLibraryView()
                    }
                    NavigationLink("Weightlifting Similarity Table") {
                        IOSWorkoutSimilarityView()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var cutoffDate: Date {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .minute, value: store.settings.cutoffMinutes, to: start) ?? now
    }

    private func minutesSinceMidnight(for date: Date) -> Int {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

#Preview {
    IOSSettingsView()
        .environmentObject(ExerciseStore())
}
