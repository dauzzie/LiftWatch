import SwiftUI

struct WatchAddExerciseView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var workoutType: ExerciseCategory = .weightlifting
    @State private var weightliftCategory: WeightliftingCategory = .push
    @State private var selectedLiftName = "Incline press"

    @State private var reps = 8
    @State private var weight = 135.0
    @State private var sets = 3

    @State private var selectedCardioName = "Run"
    @State private var minutes = 20
    @State private var pace = ""

    let onSave: (ExerciseLog) -> Void

    private var liftPresets: [LiftPreset] {
        WeightliftingCatalog.presets(for: weightliftCategory)
    }

    private var cardioOptions: [ExerciseDefinition] {
        BuiltinExerciseCatalog.cardioDefinitions()
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $workoutType) {
                    Text("Lift").tag(ExerciseCategory.weightlifting)
                    Text("Cardio").tag(ExerciseCategory.cardio)
                }

                if workoutType == .weightlifting {
                    Picker("Category", selection: $weightliftCategory) {
                        ForEach(WeightliftingCategory.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    Picker("Exercise", selection: $selectedLiftName) {
                        ForEach(liftPresets) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                    }

                    if let preset = WeightliftingCatalog.preset(named: selectedLiftName, in: weightliftCategory) {
                        Text("Targets: \(preset.targetMuscles.joined(separator: ", "))")
                            .font(.caption2)
                    }

                    compactNumberRow(symbol: "repeat", accessibilityLabel: "Reps", value: $reps, range: 1...100)
                    compactNumberRow(symbol: "square.stack.3d.up.fill", accessibilityLabel: "Sets", value: $sets, range: 1...20)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wt: \(weight.formatted(.number.precision(.fractionLength(0...1)))) lb")
                            .font(.caption2)
                        Slider(value: $weight, in: 0...1000, step: 2.5)
                    }
                } else {
                    Picker("Exercise", selection: $selectedCardioName) {
                        ForEach(cardioOptions) { exercise in
                            Text(exercise.name).tag(exercise.name)
                        }
                    }

                    compactNumberRow(symbol: "clock.fill", accessibilityLabel: "Minutes", value: $minutes, range: 1...300)
                    TextField("Pace (opt, e.g. 8:30/mi)", text: $pace)
                        .font(.footnote)
                }

                Button("Save") {
                    let trimmedPace = pace.trimmingCharacters(in: .whitespacesAndNewlines)

                    let log: ExerciseLog
                    if workoutType == .weightlifting {
                        let selectedPreset = WeightliftingCatalog.preset(named: selectedLiftName, in: weightliftCategory)
                            ?? liftPresets.first
                            ?? LiftPreset(name: "Incline press", symbol: "arrow.up.forward.circle.fill", targetMuscles: ["Upper chest", "Front delts", "Triceps"])

                        log = ExerciseLog(
                            name: selectedPreset.name,
                            symbol: selectedPreset.symbol,
                            category: .weightlifting,
                            weightliftingCategory: weightliftCategory,
                            reps: reps,
                            weight: weight,
                            sets: sets,
                            targetMuscles: selectedPreset.targetMuscles
                        )
                    } else {
                        let selected = cardioOptions.first(where: { $0.name == selectedCardioName }) ?? cardioOptions.first
                        log = ExerciseLog(
                            name: selected?.name ?? "Run",
                            symbol: selected?.symbol ?? "figure.run",
                            category: .cardio,
                            targetMuscles: selected?.targetMuscles,
                            minutes: minutes,
                            pace: trimmedPace.isEmpty ? nil : trimmedPace
                        )
                    }

                    onSave(log)
                    dismiss()
                }
            }
            .navigationTitle("New Workout")
            .onChange(of: weightliftCategory) { _, newValue in
                selectedLiftName = WeightliftingCatalog.presets(for: newValue).first?.name ?? ""
            }
            .onAppear {
                selectedCardioName = cardioOptions.first?.name ?? "Run"
            }
        }
    }

    private func compactNumberRow(
        symbol: String,
        accessibilityLabel: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(accessibilityLabel)
            Spacer()
            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Text("\(value.wrappedValue)")
                .font(.footnote.monospacedDigit())
                .frame(minWidth: 24)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    WatchAddExerciseView(onSave: { _ in })
}
