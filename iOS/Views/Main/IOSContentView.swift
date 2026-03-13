import SwiftUI
import UIKit

struct IOSContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: ExerciseStore
    @EnvironmentObject private var sync: WatchSyncManager
    @EnvironmentObject private var cloud: CloudSyncManager
    @State private var isPresentingAdd = false
    @State private var addDefaults: AddExerciseDefaults?
    @State private var pendingDidntDoLog: ExerciseLog?
    @State private var pendingDidntDoPlannedItem: PlannedExerciseItem?
    @State private var editingLog: ExerciseLog?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: LiftWatchTheme.backgroundGradient(for: colorScheme, style: .main),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                List {
                    Section {
                        summaryCard
                        if shouldShowPlanCard {
                            planCard
                        }
                        syncStatusCard
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    if store.logs.isEmpty {
                        Section {
                            emptyStateCard
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } else {
                        Section {
                            ForEach(store.logs) { log in
                                workoutCard(for: log)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            store.remove(id: log.id)
                                            sync.scheduleSnapshotSync()
                                        } label: {
                                            Label("Did", systemImage: "checkmark.circle.fill")
                                        }
                                        .tint(.green)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            pendingDidntDoLog = log
                                        } label: {
                                            Label("Didn't Do", systemImage: "xmark.circle.fill")
                                        }
                                    }
                            }
                        }
                    }

                    if !todaysPlannedExercises.isEmpty {
                        Section("Today's Planned Exercises") {
                            ForEach(todaysPlannedExercises) { item in
                                plannedExerciseCard(item)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            store.markPlannedExerciseDone(item)
                                            sync.scheduleSnapshotSync()
                                        } label: {
                                            Label("Did", systemImage: "checkmark.circle.fill")
                                        }
                                        .tint(.green)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            pendingDidntDoPlannedItem = item
                                        } label: {
                                            Label("Didn't Do", systemImage: "xmark.circle.fill")
                                        }
                                    }
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("LiftWatch")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        sync.syncBidirectional()
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Sync workouts")
                    .accessibilityHint("Synchronizes workouts with your Apple Watch and cloud.")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Add workout")
                    .accessibilityHint("Opens the new workout form.")
                }
            }
            .sheet(isPresented: $isPresentingAdd) {
                AddExerciseView(defaults: addDefaults ?? store.suggestedAddDefaults()) { log in
                    store.add(log)
                    sync.send(log: log)
                }
                .onDisappear {
                    addDefaults = nil
                }
            }
            .sheet(item: $editingLog) { log in
                EditWeightliftingEntryView(
                    log: log,
                    preferredUnit: store.settings.preferredWeightUnit,
                    maxWeightInUnit: store.settings.preferredWeightUnit.fromKilograms(store.settings.normalizedMaxWeightKilograms)
                ) { reps, sets, weight in
                    store.updateWeightliftingLog(
                        id: log.id,
                        reps: reps,
                        sets: sets,
                        weight: weight,
                        weightUnit: store.settings.preferredWeightUnit
                    )
                    sync.scheduleSnapshotSync()
                }
            }
            .confirmationDialog(
                "Move this exercise to tomorrow?",
                isPresented: Binding(
                    get: { pendingDidntDoLog != nil || pendingDidntDoPlannedItem != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDidntDoLog = nil
                            pendingDidntDoPlannedItem = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Move to Tomorrow") {
                    if let item = pendingDidntDoPlannedItem {
                        store.skipPlannedExercise(item, rescheduleToTomorrow: true)
                        sync.scheduleSnapshotSync()
                        pendingDidntDoPlannedItem = nil
                        return
                    }
                    guard let log = pendingDidntDoLog else { return }
                    store.moveLoggedExerciseToTomorrow(log)
                    store.remove(id: log.id)
                    sync.scheduleSnapshotSync()
                    pendingDidntDoLog = nil
                }
                Button("Remove", role: .destructive) {
                    if let item = pendingDidntDoPlannedItem {
                        store.markPlannedExerciseDone(item)
                        sync.scheduleSnapshotSync()
                        pendingDidntDoPlannedItem = nil
                        return
                    }
                    guard let log = pendingDidntDoLog else { return }
                    store.remove(id: log.id)
                    sync.scheduleSnapshotSync()
                    pendingDidntDoLog = nil
                }
            } message: {
                Text("Move this to tomorrow, remove it, or keep it in today's list.")
            }
        }
    }

    private var summaryCard: some View {
        let total = store.logs.count
        let lifts = store.logs.reduce(0) { $0 + ($1.category == .weightlifting ? 1 : 0) }
        let cardio = total - lifts

        return HStack(spacing: 16) {
            statPill(title: "Total", value: "\(total)")
            statPill(title: "Lifts", value: "\(lifts)")
            statPill(title: "Cardio", value: "\(cardio)")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .liftWatchPanel(.ultraThinMaterial, cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout totals")
        .accessibilityValue("\(total) total, \(lifts) weightlifting, \(cardio) cardio")
    }

    private var syncStatusCard: some View {
        HStack(spacing: 8) {
            compactSyncPill(title: "Watch", status: sync.syncStatus, color: syncColor, icon: "applewatch")
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            } label: {
                compactSyncPill(title: "Cloud", status: cloud.syncStatus, color: cloudColor, icon: "icloud.fill")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens iPhone Settings.")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liftWatchPanel(.ultraThinMaterial, cornerRadius: 14)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var planCard: some View {
        let plan = store.currentPlanDay()
        let planned = todaysPlannedExercises
        return HStack(spacing: 10) {
            Image(systemName: plan.workout.symbol)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Plan: \(plan.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(plan.workout.title)
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            Button("Load Plan") {
                addDefaults = defaultsForPlannedExercises(planned)
                isPresentingAdd = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(planned.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liftWatchPanel(.ultraThinMaterial, cornerRadius: 14)
        .overlay(alignment: .bottomLeading) {
            if !planned.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(planned.prefix(6)) { item in
                            Button {
                                addDefaults = AddExerciseDefaults(
                                    workoutType: item.workout == .cardio ? .cardio : .weightlifting,
                                    weightliftingCategory: category(for: item.workout),
                                    preferredExerciseID: item.exerciseID,
                                    plannedExerciseIDs: planned.map(\.exerciseID)
                                )
                                isPresentingAdd = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: item.exerciseSymbol)
                                    Text(item.exerciseName)
                                        .lineLimit(1)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(item.exerciseName)")
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.bottom, -34)
            }
        }
        .padding(.bottom, planned.isEmpty ? 0 : 30)
    }

    private func plannedExerciseCard(_ item: PlannedExerciseItem) -> some View {
        HStack(spacing: 12) {
            ExerciseSymbolTile(symbol: item.exerciseSymbol, tint: .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.exerciseName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.workout.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .liftWatchCardStyle(colorScheme: colorScheme, cornerRadius: 18)
    }

    private func compactSyncPill(title: String, status: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text("\(title): \(status)")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) sync")
        .accessibilityValue(status)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.blue)
            Text("No Workouts Yet")
                .font(.headline)
            Text("Add your first lift or cardio session on iPhone or Apple Watch.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .liftWatchCardStyle(colorScheme: colorScheme, cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }

    private func workoutCard(for log: ExerciseLog) -> some View {
        HStack(spacing: 12) {
            ExerciseSymbolTile(symbol: log.symbol, tint: workoutColor(for: log))

            VStack(alignment: .leading, spacing: 4) {
                Text(ExerciseNaming.displayName(name: log.name, symbol: log.symbol, category: log.category))
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if log.category == .weightlifting, let category = log.weightliftingCategory {
                        Label(category.title, systemImage: category.symbol)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(workoutColor(for: log))
                    } else {
                        Text(categoryTag(for: log))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(workoutColor(for: log))
                    }
                    Spacer()
                    if log.category == .weightlifting {
                        Button {
                            editingLog = log
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("Edit reps, sets, and weight")
                    }
                }

                Text(summary(for: log))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let muscles = log.targetMuscles, !muscles.isEmpty {
                    Text("Targets: \(muscles.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .liftWatchCardStyle(colorScheme: colorScheme, cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ExerciseNaming.displayName(name: log.name, symbol: log.symbol, category: log.category))
        .accessibilityValue(summary(for: log))
        .accessibilityHint(accessibilityHint(for: log))
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func workoutColor(for log: ExerciseLog) -> Color {
        WorkoutColors.color(for: log)
    }

    private func categoryTag(for log: ExerciseLog) -> String {
        if log.category == .cardio {
            return "Cardio"
        }
        return log.weightliftingCategory?.title ?? "Weightlifting"
    }

    private func summary(for log: ExerciseLog) -> String {
        ExerciseLogSummaryFormatter.summary(
            for: log,
            preferredUnit: store.settings.preferredWeightUnit,
            style: .iOS
        )
    }

    private func accessibilityHint(for log: ExerciseLog) -> String {
        let targets = log.targetMuscles?.isEmpty == false ? "Targets \(log.targetMuscles?.joined(separator: ", ") ?? ""). " : ""
        return "\(targets)Swipe right for did, or swipe left for didn't do."
    }

    private func category(for workout: PlanWorkoutType) -> WeightliftingCategory? {
        switch workout {
        case .push: return .push
        case .pull: return .pull
        case .legs: return .legs
        case .abs: return .abs
        case .cardio, .rest: return nil
        }
    }

    private var todaysPlannedExercises: [PlannedExerciseItem] {
        store.plannedExercisesForCurrentDay()
    }

    private var shouldShowPlanCard: Bool {
        store.currentPlanDay().workout != .rest || !todaysPlannedExercises.isEmpty
    }

    private func defaultsForPlannedExercises(_ items: [PlannedExerciseItem]) -> AddExerciseDefaults? {
        guard let first = items.first else { return nil }
        return AddExerciseDefaults(
            workoutType: first.workout == .cardio ? .cardio : .weightlifting,
            weightliftingCategory: category(for: first.workout),
            preferredExerciseID: first.exerciseID,
            plannedExerciseIDs: items.map(\.exerciseID)
        )
    }

    private var syncColor: Color { sync.syncLevel.tintColor }

    private var cloudColor: Color { cloud.syncLevel.tintColor }
}

private struct EditWeightliftingEntryView: View {
    let log: ExerciseLog
    let preferredUnit: WeightUnit
    let maxWeightInUnit: Double
    let onSave: (Int, Int, Double) -> Void

    @State private var reps: Int
    @State private var sets: Int
    @State private var weight: Double

    init(
        log: ExerciseLog,
        preferredUnit: WeightUnit,
        maxWeightInUnit: Double,
        onSave: @escaping (Int, Int, Double) -> Void
    ) {
        self.log = log
        self.preferredUnit = preferredUnit
        self.maxWeightInUnit = max(0, maxWeightInUnit)
        self.onSave = onSave

        let startingReps = min(max(log.reps ?? 8, 1), 100)
        let startingSets = min(max(log.sets ?? 3, 1), 20)
        let startingWeight = min(
            max(log.weight(in: preferredUnit) ?? 0, 0),
            max(0, maxWeightInUnit)
        )

        _reps = State(initialValue: startingReps)
        _sets = State(initialValue: startingSets)
        _weight = State(initialValue: startingWeight)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                stepperRow(title: "Reps", value: $reps, range: 1...100)
                stepperRow(title: "Sets", value: $sets, range: 1...20)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Weight")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(weight.formatted(.number.precision(.fractionLength(0...1)))) \(preferredUnit.symbol)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $weight,
                        in: 0...max(1, maxWeightInUnit),
                        step: preferredUnit == .pounds ? 0.5 : 0.25
                    )
                }
                .padding(12)
                .liftWatchPanel(.thinMaterial, cornerRadius: 14)

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                onSave(reps, sets, weight)
            }
        }
        .presentationDetents([.medium])
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(value.wrappedValue)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
        .padding(12)
        .liftWatchPanel(.thinMaterial, cornerRadius: 14)
    }
}

#Preview {
    IOSContentView()
        .environmentObject(ExerciseStore())
        .environmentObject(WatchSyncManager())
        .environmentObject(CloudSyncManager())
}
