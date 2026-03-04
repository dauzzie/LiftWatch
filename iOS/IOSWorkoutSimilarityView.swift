import SwiftUI

struct IOSWorkoutSimilarityView: View {
    @EnvironmentObject private var store: ExerciseStore

    private struct RowData: Identifiable {
        let id: String
        let exercise: ExerciseDefinition
        let similarText: String
    }

    var body: some View {
        List {
            sectionHeader

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Label(row.exercise.name, systemImage: row.exercise.symbol)
                            .font(.headline)
                            .lineLimit(2)
                        Spacer()
                        Text(row.exercise.weightliftingCategory?.title ?? "Lift")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    tableLine(title: "Muscles", value: musclesText(for: row.exercise))
                    tableLine(title: "Similar", value: row.similarText)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Workout Table")
    }

    private var rows: [RowData] {
        let all = store.allWeightliftingExercises()
        return all.map { exercise in
            RowData(
                id: exercise.id,
                exercise: exercise,
                similarText: similarExercisesText(for: exercise, within: all)
            )
        }
    }

    private func musclesText(for exercise: ExerciseDefinition) -> String {
        if exercise.targetMuscles.isEmpty {
            return "Not specified"
        }
        return exercise.targetMuscles.joined(separator: ", ")
    }

    private func similarExercisesText(for exercise: ExerciseDefinition, within all: [ExerciseDefinition]) -> String {
        let base = Set(exercise.targetMuscles.map { $0.lowercased() })
        guard !base.isEmpty else { return "No muscle overlap data" }

        let candidates = all
            .filter { $0.id != exercise.id }
            .map { other -> (name: String, overlap: Int) in
                let otherSet = Set(other.targetMuscles.map { $0.lowercased() })
                return (other.name, base.intersection(otherSet).count)
            }
            .filter { $0.overlap > 0 }
            .sorted { lhs, rhs in
                if lhs.overlap == rhs.overlap {
                    return lhs.name < rhs.name
                }
                return lhs.overlap > rhs.overlap
            }

        guard !candidates.isEmpty else { return "No close overlap" }
        return candidates.prefix(3).map { $0.name }.joined(separator: ", ")
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Exercise Similarity Table")
                .font(.headline)
            Text("Compare workouts by target muscle groups.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }

    private func tableLine(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    NavigationStack {
        IOSWorkoutSimilarityView()
            .environmentObject(ExerciseStore())
    }
}
