import SwiftUI

struct AddExerciseView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ExerciseStore

    @State private var workoutType: ExerciseCategory = .weightlifting
    @State private var weightliftCategory: WeightliftingCategory = .push
    @State private var selectedWeightExerciseID = ""
    @State private var selectedCardioExerciseID = ""
    @State private var isShowingWeightExercisePicker = false
    @State private var isShowingCardioExercisePicker = false

    @State private var reps = 8
    @State private var weight = 135.0
    @State private var sets = 3
    @State private var didInitializeWeight = false
    @State private var didApplyInitialDefaults = false

    @State private var minutes = 20
    @State private var pace = ""

    private let initialDefaults: AddExerciseDefaults?
    let onSave: (ExerciseLog) -> Void

    init(defaults: AddExerciseDefaults? = nil, onSave: @escaping (ExerciseLog) -> Void) {
        self.initialDefaults = defaults
        self.onSave = onSave
    }

    private var weightliftExercises: [ExerciseDefinition] {
        let all = store.weightliftingExercises(for: weightliftCategory)
        guard let plannedExerciseIDSet else { return all }
        return all.filter { plannedExerciseIDSet.contains($0.id) }
    }

    private var cardioExercises: [ExerciseDefinition] {
        let all = store.cardioExercises()
        guard let plannedExerciseIDSet else { return all }
        return all.filter { plannedExerciseIDSet.contains($0.id) }
    }

    private var plannedExerciseIDSet: Set<String>? {
        guard let ids = initialDefaults?.plannedExerciseIDs, !ids.isEmpty else { return nil }
        return Set(ids)
    }

    private var selectedWeightExercise: ExerciseDefinition? {
        weightliftExercises.first(where: { $0.id == selectedWeightExerciseID })
    }

    private var selectedCardioExercise: ExerciseDefinition? {
        cardioExercises.first(where: { $0.id == selectedCardioExerciseID })
    }

    private var selectedWeightExerciseName: String {
        selectedWeightExercise?.name ?? "Choose exercise"
    }

    private var selectedCardioExerciseName: String {
        selectedCardioExercise?.name ?? "Choose exercise"
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
            ZStack {
                LinearGradient(
                    colors: LiftWatchTheme.backgroundGradient(for: colorScheme),
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
                applyInitialDefaultsIfNeeded()
                ensureSelectionDefaults()
                if !didInitializeWeight {
                    let defaultKilograms = WeightUnit.pounds.toKilograms(135)
                    weight = min(preferredWeightUnit.fromKilograms(defaultKilograms), maxWeightForInput)
                    didInitializeWeight = true
                } else {
                    weight = min(weight, maxWeightForInput)
                }
            }
            .onChange(of: weightliftCategory) { _, _ in
                ensureWeightSelection()
            }
            .onChange(of: workoutType) { _, _ in
                ensureSelectionDefaults()
            }
            .onChange(of: preferredWeightUnit) { oldUnit, newUnit in
                let kilograms = oldUnit.toKilograms(weight)
                weight = min(newUnit.fromKilograms(kilograms), maxWeightForInput)
            }
            .onChange(of: store.settings.maxWeightKilograms) { _, _ in
                weight = min(weight, maxWeightForInput)
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("Dismisses the new workout form.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
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
                                weightUnit: preferredWeightUnit,
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
                    } label: {
                        Label("Save", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isSaveDisabled)
                    .accessibilityHint("Saves this workout to your log.")
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
        .liftWatchCardStyle(colorScheme: colorScheme)
        .accessibilityElement(children: .combine)
    }

    private var typePickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workout Type")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                selectionChip(
                    title: "Weightlifting",
                    systemImage: "dumbbell.fill",
                    isSelected: workoutType == .weightlifting,
                    tint: .orange
                ) {
                    workoutType = .weightlifting
                }

                selectionChip(
                    title: "Cardio",
                    systemImage: "figure.run",
                    isSelected: workoutType == .cardio,
                    tint: .green
                ) {
                    workoutType = .cardio
                }
            }
        }
        .padding(14)
        .liftWatchCardStyle(colorScheme: colorScheme)
        .accessibilityElement(children: .contain)
    }

    private var weightliftCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Category")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WeightliftingCategory.allCases) { item in
                            selectionChip(
                                title: item.title,
                                systemImage: item.symbol,
                                isSelected: weightliftCategory == item,
                                tint: .orange
                            ) {
                                weightliftCategory = item
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Exercise")
                Button {
                    isShowingWeightExercisePicker = true
                } label: {
                    HStack(spacing: 8) {
                        if let exercise = selectedWeightExercise {
                            Image(systemName: exercise.symbol)
                                .foregroundStyle(.orange)
                            Text(exercise.name)
                                .foregroundStyle(.primary)
                        } else {
                            Text("Choose exercise")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Exercise")
                .accessibilityValue(selectedWeightExerciseName)
            }
        }
        .font(.subheadline)
        .padding(14)
        .liftWatchCardStyle(colorScheme: colorScheme)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $isShowingWeightExercisePicker) {
            NavigationStack {
                List(weightliftExercises) { exercise in
                    Button {
                        selectedWeightExerciseID = exercise.id
                        isShowingWeightExercisePicker = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: exercise.symbol)
                                .foregroundStyle(.orange)
                            Text(exercise.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedWeightExerciseID == exercise.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .navigationTitle("Select Exercise")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { isShowingWeightExercisePicker = false }
                    }
                }
            }
        }
    }

    private var liftMetricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("Reps: \(reps)", value: $reps, in: 1...100)
            Stepper("Sets: \(sets)", value: $sets, in: 1...20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Weight: \(weight.formatted(.number.precision(.fractionLength(0...1)))) \(preferredWeightUnit.symbol)")
                    .font(.subheadline)
                Slider(value: $weight, in: 0...maxWeightForInput, step: weightSliderStep)
                    .tint(.orange)
                    .accessibilityLabel("Weight")
                    .accessibilityValue("\(weight.formatted(.number.precision(.fractionLength(0...1)))) \(preferredWeightUnit.title.lowercased())")
            }
        }
        .padding(14)
        .liftWatchCardStyle(colorScheme: colorScheme)
    }

    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Exercise")
                Button {
                    isShowingCardioExercisePicker = true
                } label: {
                    HStack(spacing: 8) {
                        if let exercise = selectedCardioExercise {
                            Image(systemName: exercise.symbol)
                                .foregroundStyle(.green)
                            Text(exercise.name)
                                .foregroundStyle(.primary)
                        } else {
                            Text("Choose exercise")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Cardio exercise")
                .accessibilityValue(selectedCardioExerciseName)
            }

            Stepper("Duration: \(minutes) min", value: $minutes, in: 1...300)

            TextField("Pace (optional, e.g. 8:30/mi)", text: $pace)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Pace")
        }
        .padding(14)
        .liftWatchCardStyle(colorScheme: colorScheme)
        .sheet(isPresented: $isShowingCardioExercisePicker) {
            NavigationStack {
                List(cardioExercises) { exercise in
                    Button {
                        selectedCardioExerciseID = exercise.id
                        isShowingCardioExercisePicker = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: exercise.symbol)
                                .foregroundStyle(.green)
                            Text(exercise.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedCardioExerciseID == exercise.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .navigationTitle("Select Cardio")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { isShowingCardioExercisePicker = false }
                    }
                }
            }
        }
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
        .liftWatchCardStyle(colorScheme: colorScheme)
        .accessibilityElement(children: .combine)
    }

    private func selectionChip(
        title: String,
        systemImage: String,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
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

    private func applyInitialDefaultsIfNeeded() {
        guard !didApplyInitialDefaults else { return }
        didApplyInitialDefaults = true
        guard let initialDefaults else { return }
        workoutType = initialDefaults.workoutType
        if let category = initialDefaults.weightliftingCategory {
            weightliftCategory = category
        }
        if let exerciseID = initialDefaults.preferredExerciseID {
            if workoutType == .weightlifting {
                selectedWeightExerciseID = exerciseID
                if selectedWeightExercise == nil {
                    for category in WeightliftingCategory.allCases {
                        if store.weightliftingExercises(for: category).contains(where: { $0.id == exerciseID }) {
                            weightliftCategory = category
                            selectedWeightExerciseID = exerciseID
                            break
                        }
                    }
                }
            } else {
                selectedCardioExerciseID = exerciseID
            }
        }
    }

}

#Preview {
    AddExerciseView(onSave: { _ in })
        .environmentObject(ExerciseStore())
}
