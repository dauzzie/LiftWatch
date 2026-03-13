import SwiftUI

struct IOSPlanView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: ExerciseStore
    @State private var editorDayIndex: Int?
    @State private var isShowingTomorrowSheet = false

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
                    VStack(spacing: 12) {
                        let todayPlan = store.currentPlanDay()
                        let todayIndex = store.currentPlanDayIndex() ?? 0
                        let tomorrowItems = store.plannedExercisesForTomorrow()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: todayPlan.workout.symbol)
                                    .foregroundStyle(.orange)
                                Text("Today: \(todayPlan.label) • \(todayPlan.workout.title)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }

                            HStack(spacing: 8) {
                                Button {
                                    store.shiftPlan(by: -1)
                                } label: {
                                    Label("Back", systemImage: "arrow.left")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    store.shiftPlan(by: 1)
                                } label: {
                                    Label("Forward", systemImage: "arrow.right")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Spacer()

                                Button("Reset") {
                                    store.resetPlanAnchorToCurrentSessionDay()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .liftWatchPanel(.thinMaterial, cornerRadius: 14)

                        HStack(spacing: 8) {
                            previewCard(
                                title: "Today",
                                icon: "sun.max.fill",
                                items: store.plannedExercisesForCurrentDay(),
                                emptyText: "No exercises"
                            )
                            previewCard(
                                title: "Tomorrow",
                                icon: "moon.stars.fill",
                                items: store.plannedExercisesForTomorrow(),
                                emptyText: "No exercises"
                            )
                        }

                        if !tomorrowItems.isEmpty {
                            Button {
                                isShowingTomorrowSheet = true
                            } label: {
                                Label("View All Tomorrow Exercises", systemImage: "list.bullet.rectangle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Weekly Pattern")
                                .font(.headline)
                            Text("Tap a day to make it today's workout slot.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(Array(store.settings.planDays.enumerated()), id: \.element.id) { index, day in
                                HStack(spacing: 8) {
                                    Image(systemName: day.workout.symbol)
                                        .foregroundStyle(.orange)
                                    Text(day.label)
                                        .font(.subheadline.weight(.semibold))
                                    Text(day.workout.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(store.planExercises(for: index).count) ex")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    Button {
                                        store.movePlanDayUp(at: index)
                                    } label: {
                                        Image(systemName: "arrow.up")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(index == 0)

                                    Button {
                                        store.movePlanDayDown(at: index)
                                    } label: {
                                        Image(systemName: "arrow.down")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(index == store.settings.planDays.count - 1)

                                    Menu {
                                        ForEach(PlanWorkoutType.allCases) { workout in
                                            Button {
                                                store.updatePlanDay(at: index, workout: workout)
                                            } label: {
                                                Label(workout.title, systemImage: workout.symbol)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "slider.horizontal.3")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button {
                                        editorDayIndex = index
                                    } label: {
                                        Image(systemName: "list.bullet")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(index == todayIndex ? Color.orange.opacity(0.14) : Color.clear)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    store.shiftPlanSoTodayMatchesDay(at: index)
                                }
                            }
                        }
                        .padding(12)
                        .liftWatchPanel(.thinMaterial, cornerRadius: 14)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("Plan")
            .sheet(item: Binding(
                get: { editorDayIndex.map(PlanDayEditorToken.init(index:)) },
                set: { editorDayIndex = $0?.index }
            )) { token in
                PlanDayEditorView(dayIndex: token.index)
                    .environmentObject(store)
            }
            .sheet(isPresented: $isShowingTomorrowSheet) {
                TomorrowExercisesSheet()
                    .environmentObject(store)
            }
        }
    }

    private func previewCard(title: String, icon: String, items: [PlannedExerciseItem], emptyText: String) -> some View {
        let sortedItems = items.sorted { lhs, rhs in
            let lhsPriority = previewPriority(for: lhs.source)
            let rhsPriority = previewPriority(for: rhs.source)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.exerciseName < rhs.exerciseName
        }
        let visibleItems = Array(sortedItems.prefix(5))
        let hiddenCount = max(0, sortedItems.count - visibleItems.count)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleItems) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.exerciseSymbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.exerciseName)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if item.source == .extraExercise || item.source == .extraWorkoutLegacy {
                            Text("Moved")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if hiddenCount > 0 {
                    Text("+\(hiddenCount) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liftWatchPanel(.thinMaterial, cornerRadius: 12)
    }

    private func previewPriority(for source: PlannedExerciseSource) -> Int {
        switch source {
        case .extraExercise, .extraWorkoutLegacy:
            return 0
        case .base:
            return 1
        }
    }
}

private struct TomorrowExercisesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ExerciseStore

    private var items: [PlannedExerciseItem] {
        store.plannedExercisesForTomorrow()
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("No exercises scheduled for tomorrow.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.exerciseSymbol)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.exerciseName)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.workout.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Move +1d") {
                                store.movePlannedExerciseToNextDay(item)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button(role: .destructive) {
                                store.markPlannedExerciseDone(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .accessibilityLabel("Delete exercise")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.markPlannedExerciseDone(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tomorrow")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PlanDayEditorToken: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct PlanDayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ExerciseStore

    let dayIndex: Int
    @State private var selectedExerciseIDs: Set<String> = []

    private var day: PlanDay? {
        guard store.settings.planDays.indices.contains(dayIndex) else { return nil }
        return store.settings.planDays[dayIndex]
    }

    private var workout: PlanWorkoutType {
        day?.workout ?? .rest
    }

    private var availableExercises: [ExerciseDefinition] {
        store.allPlanSelectableExercises()
    }

    private var selectedExercises: [ExerciseDefinition] {
        availableExercises.filter { selectedExerciseIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let day {
                    Section("Day") {
                        HStack(spacing: 10) {
                            Image(systemName: day.workout.symbol)
                                .foregroundStyle(.orange)
                            Text(day.label)
                            Spacer()
                            Text(day.workout.title)
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    Section("Workout Type") {
                        Picker("Workout Type", selection: Binding(
                            get: { workout },
                            set: { newValue in
                                store.updatePlanDay(at: dayIndex, workout: newValue)
                                store.updatePlanExercises(dayIndex: dayIndex, exerciseIDs: orderedSelectedExerciseIDs())
                            }
                        )) {
                            ForEach(PlanWorkoutType.allCases) { item in
                                Label(item.title, systemImage: item.symbol).tag(item)
                            }
                        }
                    }

                    Section("Selected Exercises") {
                        if workout == .rest {
                            Text("Rest day has no exercise list.")
                                .foregroundStyle(.secondary)
                        } else if selectedExercises.isEmpty {
                            Text("No exercises selected yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(selectedExercises) { exercise in
                                HStack(spacing: 10) {
                                    Image(systemName: exercise.symbol)
                                        .foregroundStyle(.orange)
                                    Text(exercise.name)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(role: .destructive) {
                                        toggle(exerciseID: exercise.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }

                    Section("Exercise Library") {
                        if workout == .rest {
                            Text("Rest day has no exercise list.")
                                .foregroundStyle(.secondary)
                        } else if availableExercises.isEmpty {
                            Text("No exercises available for this workout type.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availableExercises) { exercise in
                                Button {
                                    toggle(exerciseID: exercise.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: exercise.symbol)
                                            .foregroundStyle(.orange)
                                        Text(exercise.name)
                                            .lineLimit(1)
                                        Spacer()
                                        if selectedExerciseIDs.contains(exercise.id) {
                                            Text("Added")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        } else {
                                            Image(systemName: "plus.circle")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Day")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                let existing = store.planExercises(for: dayIndex).map(\.id)
                selectedExerciseIDs = Set(existing)
            }
        }
    }

    private func toggle(exerciseID: String) {
        if selectedExerciseIDs.contains(exerciseID) {
            selectedExerciseIDs.remove(exerciseID)
        } else {
            selectedExerciseIDs.insert(exerciseID)
        }
        store.updatePlanExercises(dayIndex: dayIndex, exerciseIDs: orderedSelectedExerciseIDs())
    }

    private func orderedSelectedExerciseIDs() -> [String] {
        store.allPlanSelectableExercises().map(\.id).filter { selectedExerciseIDs.contains($0) }
    }
}

#Preview {
    IOSPlanView()
        .environmentObject(ExerciseStore())
}
