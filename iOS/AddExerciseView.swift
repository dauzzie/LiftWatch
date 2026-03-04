import SwiftUI

struct AddExerciseView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ExerciseStore

    @State private var workoutType: ExerciseCategory = .weightlifting
    @State private var weightliftCategory: WeightliftingCategory = .push
    @State private var selectedWeightExerciseID = ""
    @State private var selectedCardioExerciseID = ""

    @State private var reps = 8
    @State private var weight = 135.0
    @State private var sets = 3

    @State private var minutes = 20
    @State private var pace = ""

    let onSave: (ExerciseLog) -> Void

    private var weightliftExercises: [ExerciseDefinition] {
        store.weightliftingExercises(for: weightliftCategory)
    }

    private var cardioExercises: [ExerciseDefinition] {
        store.cardioExercises()
    }

    private var selectedWeightExercise: ExerciseDefinition? {
        weightliftExercises.first(where: { $0.id == selectedWeightExerciseID })
    }

    private var selectedCardioExercise: ExerciseDefinition? {
        cardioExercises.first(where: { $0.id == selectedCardioExerciseID })
    }

    private var selectedTargetsText: String {
        switch workoutType {
        case .weightlifting:
            let targets = selectedWeightExercise?.targetMuscles ?? []
            return targets.isEmpty ? "Targets: Not specified" : "Targets: \(targets.joined(separator: ", "))"
        case .cardio:
            let targets = selectedCardioExercise?.targetMuscles ?? ["Cardiovascular conditioning"]
            return "Targets: \(targets.joined(separator: ", "))"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: backgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        headerCard
                        typePickerCard

                        if workoutType == .weightlifting {
                            weightliftCard
                            liftMetricsCard
                        } else {
                            cardioCard
                        }

                        targetInfoCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("New Workout")
            .onAppear {
                ensureSelectionDefaults()
            }
            .onChange(of: weightliftCategory) { _, _ in
                ensureWeightSelection()
            }
            .onChange(of: workoutType) { _, _ in
                ensureSelectionDefaults()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedPace = pace.trimmingCharacters(in: .whitespacesAndNewlines)

                        let log: ExerciseLog
                        if workoutType == .weightlifting {
                            guard let exercise = selectedWeightExercise else { return }
                            log = ExerciseLog(
                                name: exercise.name,
                                symbol: exercise.symbol,
                                category: .weightlifting,
                                weightliftingCategory: weightliftCategory,
                                reps: reps,
                                weight: weight,
                                sets: sets,
                                targetMuscles: exercise.targetMuscles
                            )
                        } else {
                            guard let exercise = selectedCardioExercise else { return }
                            log = ExerciseLog(
                                name: exercise.name,
                                symbol: exercise.symbol,
                                category: .cardio,
                                targetMuscles: exercise.targetMuscles,
                                minutes: minutes,
                                pace: trimmedPace.isEmpty ? nil : trimmedPace
                            )
                        }

                        onSave(log)
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: workoutType == .weightlifting ? "dumbbell.fill" : "figure.run")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(workoutType == .weightlifting ? Color.orange : Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(workoutType == .weightlifting ? "Strength Session" : "Cardio Session")
                    .font(.headline)
                Text("Choose exercise, log metrics, then save")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .cardStyle(colorScheme: colorScheme)
    }

    private var typePickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workout Type")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Type", selection: $workoutType) {
                Text("Weightlifting").tag(ExerciseCategory.weightlifting)
                Text("Cardio").tag(ExerciseCategory.cardio)
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .cardStyle(colorScheme: colorScheme)
    }

    private var weightliftCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Category")
                Picker("Category", selection: $weightliftCategory) {
                    ForEach(WeightliftingCategory.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Exercise")
                Picker("Exercise", selection: $selectedWeightExerciseID) {
                    ForEach(weightliftExercises) { exercise in
                        Label(exercise.name, systemImage: exercise.symbol).tag(exercise.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .font(.subheadline)
        .padding(14)
        .cardStyle(colorScheme: colorScheme)
    }

    private var liftMetricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("Reps: \(reps)", value: $reps, in: 1...100)
            Stepper("Sets: \(sets)", value: $sets, in: 1...20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Weight: \(weight.formatted(.number.precision(.fractionLength(0...1)))) lb")
                    .font(.subheadline)
                Slider(value: $weight, in: 0...1000, step: 2.5)
                    .tint(.orange)
            }
        }
        .padding(14)
        .cardStyle(colorScheme: colorScheme)
    }

    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Exercise")
                Picker("Cardio Exercise", selection: $selectedCardioExerciseID) {
                    ForEach(cardioExercises) { exercise in
                        Label(exercise.name, systemImage: exercise.symbol).tag(exercise.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Stepper("Duration: \(minutes) min", value: $minutes, in: 1...300)

            TextField("Pace (optional, e.g. 8:30/mi)", text: $pace)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
        }
        .padding(14)
        .cardStyle(colorScheme: colorScheme)
    }

    private var targetInfoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Muscle Focus")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(selectedTargetsText)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardStyle(colorScheme: colorScheme)
    }

    private var isSaveDisabled: Bool {
        if workoutType == .weightlifting {
            return selectedWeightExercise == nil
        }
        return selectedCardioExercise == nil
    }

    private func ensureSelectionDefaults() {
        ensureWeightSelection()
        if selectedCardioExercise == nil {
            selectedCardioExerciseID = cardioExercises.first?.id ?? ""
        }
    }

    private func ensureWeightSelection() {
        if selectedWeightExercise == nil {
            selectedWeightExerciseID = weightliftExercises.first?.id ?? ""
        }
    }

    private var backgroundGradient: [Color] {
        if colorScheme == .dark {
            return [Color(red: 0.08, green: 0.10, blue: 0.14), Color(red: 0.06, green: 0.12, blue: 0.20)]
        }
        return [Color(red: 0.95, green: 0.98, blue: 1.0), Color(red: 0.90, green: 0.95, blue: 1.0)]
    }
}

private extension View {
    func cardStyle(colorScheme: ColorScheme) -> some View {
        self
            .background(
                colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.9),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.8), lineWidth: 1)
            )
    }
}

#Preview {
    AddExerciseView(onSave: { _ in })
        .environmentObject(ExerciseStore())
}
