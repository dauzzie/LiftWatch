import SwiftUI

struct WatchAddExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ExerciseStore

    @State private var workoutType: ExerciseCategory = .weightlifting
    @State private var weightliftCategory: WeightliftingCategory = .push
    @State private var selectedLiftName = "Incline press"

    @State private var reps = 8
    @State private var weight = 135.0
    @State private var sets = 3
    @State private var didInitializeWeight = false

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

    private var preferredWeightUnit: WeightUnit {
        store.settings.preferredWeightUnit
    }

    private var maxWeightForInput: Double {
        preferredWeightUnit.fromKilograms(store.settings.normalizedMaxWeightKilograms)
    }

    private var weightSliderStep: Double {
        preferredWeightUnit == .pounds ? 2.5 : 1.0
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
                            Label(item.title, systemImage: item.symbol).tag(item)
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
                        Text("Wt: \(weight.formatted(.number.precision(.fractionLength(0...1)))) \(preferredWeightUnit.symbol)")
                            .font(.caption2)
                        Slider(value: $weight, in: 0...maxWeightForInput, step: weightSliderStep)
                            .accessibilityLabel("Weight")
                            .accessibilityValue("\(weight.formatted(.number.precision(.fractionLength(0...1)))) \(preferredWeightUnit.title.lowercased())")
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
                        .accessibilityLabel("Pace")
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
                            weightUnit: preferredWeightUnit,
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
                .accessibilityHint("Saves this workout to your log.")
            }
            .navigationTitle("New Workout")
            .onChange(of: weightliftCategory) { _, newValue in
                selectedLiftName = WeightliftingCatalog.presets(for: newValue).first?.name ?? ""
            }
            .onAppear {
                selectedCardioName = cardioOptions.first?.name ?? "Run"
                if !didInitializeWeight {
                    let defaultKilograms = WeightUnit.pounds.toKilograms(135)
                    weight = min(preferredWeightUnit.fromKilograms(defaultKilograms), maxWeightForInput)
                    didInitializeWeight = true
                } else {
                    weight = min(weight, maxWeightForInput)
                }
            }
            .onChange(of: preferredWeightUnit) { oldUnit, newUnit in
                let kilograms = oldUnit.toKilograms(weight)
                weight = min(newUnit.fromKilograms(kilograms), maxWeightForInput)
            }
            .onChange(of: store.settings.maxWeightKilograms) { _, _ in
                weight = min(weight, maxWeightForInput)
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
            .accessibilityLabel("Decrease \(accessibilityLabel)")

            Text("\(value.wrappedValue)")
                .font(.footnote.monospacedDigit())
                .frame(minWidth: 24)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue("\(value.wrappedValue)")

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase \(accessibilityLabel)")
        }
    }
}

#Preview {
    WatchAddExerciseView(onSave: { _ in })
        .environmentObject(ExerciseStore())
}
