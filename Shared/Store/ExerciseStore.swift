import Foundation

@MainActor
final class ExerciseStore: ObservableObject {
    @Published private(set) var logs: [ExerciseLog] = []
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published private(set) var customExercises: [ExerciseDefinition] = []
    @Published private(set) var lastMutationAt: Date = .now
    @Published var settings: AppSettings = AppSettings() {
        didSet {
            guard !isHydratingState, !isMutatingSettingsInternally else { return }
            handleSettingsChanged()
        }
    }

    var onStateDidPersist: (() -> Void)?

    private struct PersistedState: Codable {
        var logs: [ExerciseLog]
        var sessions: [WorkoutSession]
        var customExercises: [ExerciseDefinition]
        var settings: AppSettings
        var lastSessionStart: Date

        init(
            logs: [ExerciseLog],
            sessions: [WorkoutSession],
            customExercises: [ExerciseDefinition],
            settings: AppSettings,
            lastSessionStart: Date
        ) {
            self.logs = logs
            self.sessions = sessions
            self.customExercises = customExercises
            self.settings = settings
            self.lastSessionStart = lastSessionStart
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            logs = try c.decodeIfPresent([ExerciseLog].self, forKey: .logs) ?? []
            sessions = try c.decodeIfPresent([WorkoutSession].self, forKey: .sessions) ?? []
            customExercises = try c.decodeIfPresent([ExerciseDefinition].self, forKey: .customExercises) ?? []
            settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
            lastSessionStart = try c.decodeIfPresent(Date.self, forKey: .lastSessionStart) ?? .now
        }
    }

    private let defaultsKey = "liftwatch.persisted.state.v3"
    private let legacyDefaultsKeyV2 = "liftwatch.persisted.state.v2"
    private let legacyDefaultsKeyV1 = "liftwatch.persisted.state.v1"

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var isHydratingState = false
    private var isMutatingSettingsInternally = false
    private var lastSessionStart: Date
    private var rolloverTask: Task<Void, Never>?
    private var cachedProgressiveEntries: (version: Date, data: [ProgressiveOverloadEntry])?
    private var cachedProgressivePoints: (version: Date, data: [ProgressiveOverloadPoint])?
    private var cachedAvailableSymbols: (version: Date, data: [String])?
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter
    }()
    private let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()
    private let planDayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let now = Date()
        self.lastSessionStart = now

        load()
        rollSessionIfNeeded(now: now)
        scheduleRolloverTask()
    }

    func add(_ log: ExerciseLog) {
        rollSessionIfNeeded(now: .now, persistChanges: false)
        logs.removeAll { existing in
            logDuplicateKey(for: existing) == logDuplicateKey(for: log)
        }
        logs.insert(log, at: 0)
        persist()
    }

    func addAll(_ incoming: [ExerciseLog]) {
        rollSessionIfNeeded(now: .now, persistChanges: false)
        logs = deduplicatedLogsKeepingLatest(logs + incoming)
        persist()
    }

    func replaceAll(with incoming: [ExerciseLog]) {
        rollSessionIfNeeded(now: .now, persistChanges: false)
        logs = deduplicatedLogsKeepingLatest(incoming)
        persist()
    }

    func remove(id: UUID) {
        logs.removeAll(where: { $0.id == id })
        persist()
    }

    func updateWeightliftingLog(
        id: UUID,
        reps: Int,
        sets: Int,
        weight: Double,
        weightUnit: WeightUnit
    ) {
        guard let index = logs.firstIndex(where: { $0.id == id }) else { return }
        guard logs[index].category == .weightlifting else { return }

        let clampedReps = min(max(reps, 1), 100)
        let clampedSets = min(max(sets, 1), 20)
        let maxWeightInUnit = weightUnit.fromKilograms(settings.normalizedMaxWeightKilograms)
        let clampedWeight = min(max(weight, 0), maxWeightInUnit)

        logs[index].reps = clampedReps
        logs[index].sets = clampedSets
        logs[index].weight = clampedWeight
        logs[index].weightUnit = weightUnit
        persist()
    }

    func moveLoggedExerciseToTomorrow(_ log: ExerciseLog, now: Date = .now) {
        let tomorrowKey = planDayKey(for: nextSessionStart(after: currentSessionStart(now: now)))
        let workout: PlanWorkoutType
        switch log.category {
        case .cardio:
            workout = .cardio
        case .weightlifting:
            switch log.weightliftingCategory {
            case .push: workout = .push
            case .pull: workout = .pull
            case .legs: workout = .legs
            case .abs: workout = .abs
            case .none: workout = .push
            }
        }
        let exerciseID = planExerciseID(for: log)
        let duplicateKey = plannedExerciseDuplicateKey(name: log.name)

        mutateSettings { settings in
            var target = settings.temporaryExercisePlanByDate[tomorrowKey] ?? []
            let exists = target.contains { plannedExerciseDuplicateKey(name: $0.exerciseName) == duplicateKey }
            if !exists {
                target.append(
                    TemporaryPlannedExercise(
                        workout: workout,
                        exerciseID: exerciseID,
                        exerciseName: log.name,
                        exerciseSymbol: log.symbol
                    )
                )
            }
            settings.temporaryExercisePlanByDate[tomorrowKey] = target
        }
    }

    func clear() {
        logs = []
        persist()
    }

    func appDidBecomeActive() {
        rollSessionIfNeeded(now: .now, persistChanges: true)
        scheduleRolloverTask()
    }

    func updateCutoff(to minutes: Int) {
        mutateSettings { settings in
            settings.cutoffMinutes = min(max(minutes, 0), 23 * 60 + 59)
        }
    }

    func updatePreferredWeightUnit(to unit: WeightUnit) {
        mutateSettings { settings in
            settings.preferredWeightUnit = unit
        }
    }

    func updateMaxWeightLimit(_ value: Double, in unit: WeightUnit) {
        let normalized = min(
            max(unit.toKilograms(value), AppSettings.minMaxWeightKilograms),
            AppSettings.hardMaxWeightKilograms
        )
        mutateSettings { settings in
            settings.maxWeightKilograms = normalized
        }
    }

    func updatePlanDay(at index: Int, workout: PlanWorkoutType) {
        guard settings.planDays.indices.contains(index) else { return }
        mutateSettings { settings in
            settings.planDays[index].workout = workout
        }
    }

    func shiftPlan(by days: Int) {
        guard !settings.planDays.isEmpty else { return }
        mutateSettings { settings in
            settings.planShiftDays += days
        }
    }

    func shiftPlanSoTodayMatchesDay(at index: Int, now: Date = .now) {
        guard let currentIndex = currentPlanDayIndex(now: now),
              settings.planDays.indices.contains(index)
        else { return }
        let delta = index - currentIndex
        guard delta != 0 else { return }
        mutateSettings { settings in
            settings.planShiftDays += delta
        }
    }

    func movePlanDayUp(at index: Int) {
        movePlanDay(from: index, to: index - 1)
    }

    func movePlanDayDown(at index: Int) {
        movePlanDay(from: index, to: index + 1)
    }

    func resetPlanAnchorToCurrentSessionDay(now: Date = .now) {
        let sessionStart = currentSessionStart(now: now)
        mutateSettings { settings in
            settings.planAnchorDate = sessionStart
            settings.planShiftDays = 0
        }
    }

    func updatePlanExercises(dayIndex: Int, exerciseIDs: [String]) {
        guard settings.planDays.indices.contains(dayIndex) else { return }
        let uniqueIDs = uniquePreservingOrder(exerciseIDs)
        mutateSettings { settings in
            settings.planExerciseIDsByDay[dayIndex] = uniqueIDs
        }
    }

    func currentPlanDay(now: Date = .now) -> PlanDay {
        let days = settings.planDays.isEmpty ? PlanDay.defaultWeek : settings.planDays
        let index = currentPlanDayIndex(now: now) ?? 0
        return days[index]
    }

    func currentPlanDayIndex(now: Date = .now) -> Int? {
        let days = settings.planDays.isEmpty ? PlanDay.defaultWeek : settings.planDays
        guard !days.isEmpty else { return nil }
        let activeSessionStart = currentSessionStart(now: now)
        let calendar = Calendar.autoupdatingCurrent
        let anchorStart = calendar.startOfDay(for: settings.planAnchorDate)
        let sessionStart = calendar.startOfDay(for: activeSessionStart)
        let elapsed = calendar.dateComponents([.day], from: anchorStart, to: sessionStart).day ?? 0
        return positiveModulo(elapsed + settings.planShiftDays, days.count)
    }

    func suggestedAddDefaults(now: Date = .now) -> AddExerciseDefaults? {
        let day = currentPlanDay(now: now)
        let preferredExercise = plannedExercisesForCurrentDay(now: now).first
        switch day.workout {
        case .push:
            return AddExerciseDefaults(
                workoutType: .weightlifting,
                weightliftingCategory: .push,
                preferredExerciseID: preferredExercise?.exerciseID
            )
        case .pull:
            return AddExerciseDefaults(
                workoutType: .weightlifting,
                weightliftingCategory: .pull,
                preferredExerciseID: preferredExercise?.exerciseID
            )
        case .legs:
            return AddExerciseDefaults(
                workoutType: .weightlifting,
                weightliftingCategory: .legs,
                preferredExerciseID: preferredExercise?.exerciseID
            )
        case .abs:
            return AddExerciseDefaults(
                workoutType: .weightlifting,
                weightliftingCategory: .abs,
                preferredExerciseID: preferredExercise?.exerciseID
            )
        case .cardio:
            return AddExerciseDefaults(
                workoutType: .cardio,
                weightliftingCategory: nil,
                preferredExerciseID: preferredExercise?.exerciseID
            )
        case .rest:
            return nil
        }
    }

    func plannedWorkoutsForCurrentDay(now: Date = .now) -> [PlannedWorkoutItem] {
        let sessionStart = currentSessionStart(now: now)
        return plannedWorkouts(forSessionStart: sessionStart)
    }

    func plannedWorkoutsForTomorrow(now: Date = .now) -> [PlannedWorkoutItem] {
        let tomorrowStart = nextSessionStart(after: currentSessionStart(now: now))
        return plannedWorkouts(forSessionStart: tomorrowStart)
    }

    func plannedExercisesForCurrentDay(now: Date = .now) -> [PlannedExerciseItem] {
        plannedExercises(forSessionStart: currentSessionStart(now: now))
    }

    func plannedExercisesForTomorrow(now: Date = .now) -> [PlannedExerciseItem] {
        plannedExercises(forSessionStart: nextSessionStart(after: currentSessionStart(now: now)))
    }

    func exercises(for planWorkout: PlanWorkoutType) -> [ExerciseDefinition] {
        switch planWorkout {
        case .push:
            return weightliftingExercises(for: .push)
        case .pull:
            return weightliftingExercises(for: .pull)
        case .legs:
            return weightliftingExercises(for: .legs)
        case .abs:
            return weightliftingExercises(for: .abs)
        case .cardio:
            return cardioExercises()
        case .rest:
            return []
        }
    }

    func planExercises(for dayIndex: Int) -> [ExerciseDefinition] {
        guard settings.planDays.indices.contains(dayIndex) else { return [] }
        let all = allPlanSelectableExercises()
        let allByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let ids = uniquePreservingOrder(settings.planExerciseIDsByDay[dayIndex] ?? [])
        return ids.compactMap { allByID[$0] }
    }

    private func plannedWorkouts(forSessionStart sessionStart: Date) -> [PlannedWorkoutItem] {
        let dayKey = planDayKey(for: sessionStart)
        let base = planDay(forSessionStart: sessionStart).workout
        var items: [PlannedWorkoutItem] = []

        if base != .rest, !settings.hiddenBasePlanDates.contains(dayKey) {
            items.append(
                PlannedWorkoutItem(
                    id: "\(dayKey)-base-\(base.rawValue)",
                    workout: base,
                    source: .base,
                    dayKey: dayKey
                )
            )
        }

        let extras = settings.temporaryPlanByDate[dayKey] ?? []
        items += extras.enumerated().map { index, workout in
            PlannedWorkoutItem(
                id: "\(dayKey)-extra-\(index)-\(workout.rawValue)",
                workout: workout,
                source: .extra,
                dayKey: dayKey
            )
        }

        return items
    }

    private func plannedExercises(forSessionStart sessionStart: Date) -> [PlannedExerciseItem] {
        let dayKey = planDayKey(for: sessionStart)
        let hiddenIDs = Set(settings.hiddenPlannedExerciseIDsByDate[dayKey] ?? [])
        var items: [PlannedExerciseItem] = []
        var seenExerciseKeys: Set<String> = []

        let workoutItems = plannedWorkouts(forSessionStart: sessionStart)
        for workoutItem in workoutItems {
            switch workoutItem.source {
            case .base:
                guard let dayIndex = planDayIndex(forSessionStart: sessionStart) else { continue }
                let configured = planExercises(for: dayIndex)
                let exercises = configured.isEmpty ? exercises(for: workoutItem.workout) : configured
                for exercise in exercises {
                    let key = plannedExerciseDuplicateKey(name: exercise.name)
                    guard !seenExerciseKeys.contains(key) else { continue }
                    let id = "\(dayKey)-base-\(workoutItem.workout.rawValue)-\(exercise.id)"
                    guard !hiddenIDs.contains(id) else { continue }
                    seenExerciseKeys.insert(key)
                    items.append(
                        PlannedExerciseItem(
                            id: id,
                            dayKey: dayKey,
                            workout: workoutItem.workout,
                            source: .base,
                            exerciseID: exercise.id,
                            exerciseName: exercise.name,
                            exerciseSymbol: exercise.symbol
                        )
                    )
                }
            case .extra:
                break
            }
        }

        let exerciseExtras = settings.temporaryExercisePlanByDate[dayKey] ?? []
        for (index, extra) in exerciseExtras.enumerated() {
            let key = plannedExerciseDuplicateKey(name: extra.exerciseName)
            guard !seenExerciseKeys.contains(key) else { continue }
            let id = "\(dayKey)-extra-ex-\(index)-\(extra.workout.rawValue)-\(extra.exerciseID)"
            guard !hiddenIDs.contains(id) else { continue }
            seenExerciseKeys.insert(key)
            items.append(
                PlannedExerciseItem(
                    id: id,
                    dayKey: dayKey,
                    workout: extra.workout,
                    source: .extraExercise,
                    exerciseID: extra.exerciseID,
                    exerciseName: extra.exerciseName,
                    exerciseSymbol: extra.exerciseSymbol
                )
            )
        }

        let legacyWorkoutExtras = settings.temporaryPlanByDate[dayKey] ?? []
        for (index, workout) in legacyWorkoutExtras.enumerated() {
            let fallback = exercises(for: workout).first
            let exerciseID = fallback?.id ?? "legacy-\(workout.rawValue)"
            let exerciseName = fallback?.name ?? workout.title
            let exerciseSymbol = fallback?.symbol ?? workout.symbol
            let key = plannedExerciseDuplicateKey(name: exerciseName)
            guard !seenExerciseKeys.contains(key) else { continue }
            let id = "\(dayKey)-extra-legacy-\(index)-\(workout.rawValue)-\(exerciseID)"
            guard !hiddenIDs.contains(id) else { continue }
            seenExerciseKeys.insert(key)
            items.append(
                PlannedExerciseItem(
                    id: id,
                    dayKey: dayKey,
                    workout: workout,
                    source: .extraWorkoutLegacy,
                    exerciseID: exerciseID,
                    exerciseName: exerciseName,
                    exerciseSymbol: exerciseSymbol
                )
            )
        }

        return items
    }

    func markPlannedWorkoutDone(_ item: PlannedWorkoutItem) {
        removePlannedWorkout(item)
    }

    func skipPlannedWorkout(_ item: PlannedWorkoutItem, rescheduleToTomorrow: Bool, now: Date = .now) {
        if rescheduleToTomorrow {
            let tomorrowKey = planDayKey(for: nextSessionStart(after: currentSessionStart(now: now)))
            mutateSettings { settings in
                var target = settings.temporaryPlanByDate[tomorrowKey] ?? []
                target.append(item.workout)
                settings.temporaryPlanByDate[tomorrowKey] = target
            }
        }
        removePlannedWorkout(item)
    }

    func markPlannedExerciseDone(_ item: PlannedExerciseItem) {
        removePlannedExercise(item)
    }

    func skipPlannedExercise(_ item: PlannedExerciseItem, rescheduleToTomorrow: Bool, now: Date = .now) {
        if rescheduleToTomorrow {
            let tomorrowKey = planDayKey(for: nextSessionStart(after: currentSessionStart(now: now)))
            let duplicateKey = plannedExerciseDuplicateKey(name: item.exerciseName)
            mutateSettings { settings in
                var target = settings.temporaryExercisePlanByDate[tomorrowKey] ?? []
                let exists = target.contains { plannedExerciseDuplicateKey(name: $0.exerciseName) == duplicateKey }
                if !exists {
                    target.append(
                        TemporaryPlannedExercise(
                            workout: item.workout,
                            exerciseID: item.exerciseID,
                            exerciseName: item.exerciseName,
                            exerciseSymbol: item.exerciseSymbol
                        )
                    )
                }
                settings.temporaryExercisePlanByDate[tomorrowKey] = target
            }
        }
        removePlannedExercise(item)
    }

    func movePlannedExerciseToNextDay(_ item: PlannedExerciseItem) {
        guard let sourceDate = planDayKeyFormatter.date(from: item.dayKey),
              let targetDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: sourceDate)
        else { return }

        let targetKey = planDayKey(for: targetDate)
        removePlannedExercise(item)
        let duplicateKey = plannedExerciseDuplicateKey(name: item.exerciseName)
        mutateSettings { settings in
            var target = settings.temporaryExercisePlanByDate[targetKey] ?? []
            let exists = target.contains { plannedExerciseDuplicateKey(name: $0.exerciseName) == duplicateKey }
            if !exists {
                target.append(
                    TemporaryPlannedExercise(
                        workout: item.workout,
                        exerciseID: item.exerciseID,
                        exerciseName: item.exerciseName,
                        exerciseSymbol: item.exerciseSymbol
                    )
                )
            }
            settings.temporaryExercisePlanByDate[targetKey] = target
        }
    }

    func previousSession() -> WorkoutSession? {
        sessions.first
    }

    func historyPoints(for range: HistoryRange, now: Date = .now) -> [WorkoutHistoryPoint] {
        let calendar = Calendar.autoupdatingCurrent
        let combinedSessions = sessions + [WorkoutSession(start: currentSessionStart(now: now), end: now, logs: logs)]

        switch range {
        case .daily:
            let sorted = combinedSessions.sorted(by: { $0.start > $1.start }).prefix(7)
            return sorted.map { session in
                WorkoutHistoryPoint(
                    label: dayLabel(for: session.start),
                    workoutCount: session.logs.count,
                    totalSets: session.logs.compactMap(\.sets).reduce(0, +),
                    totalMinutes: session.logs.compactMap(\.minutes).reduce(0, +)
                )
            }
        case .weekly:
            var buckets: [Date: [ExerciseLog]] = [:]
            for session in combinedSessions {
                guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: session.start)?.start else { continue }
                buckets[weekStart, default: []].append(contentsOf: session.logs)
            }
            return buckets
                .sorted(by: { $0.key > $1.key })
                .prefix(8)
                .map { start, logs in
                    WorkoutHistoryPoint(
                        label: weekLabel(start: start),
                        workoutCount: logs.count,
                        totalSets: logs.compactMap(\.sets).reduce(0, +),
                        totalMinutes: logs.compactMap(\.minutes).reduce(0, +)
                    )
                }
        case .monthly:
            var buckets: [DateComponents: [ExerciseLog]] = [:]
            for session in combinedSessions {
                let components = calendar.dateComponents([.year, .month], from: session.start)
                buckets[components, default: []].append(contentsOf: session.logs)
            }
            return buckets
                .sorted {
                    let l = ($0.key.year ?? 0, $0.key.month ?? 0)
                    let r = ($1.key.year ?? 0, $1.key.month ?? 0)
                    return l > r
                }
                .prefix(6)
                .map { key, logs in
                    let date = calendar.date(from: key) ?? now
                    return WorkoutHistoryPoint(
                        label: monthLabel(for: date),
                        workoutCount: logs.count,
                        totalSets: logs.compactMap(\.sets).reduce(0, +),
                        totalMinutes: logs.compactMap(\.minutes).reduce(0, +)
                    )
                }
        }
    }

    func weightliftingExercises(for category: WeightliftingCategory) -> [ExerciseDefinition] {
        let builtin = BuiltinExerciseCatalog.weightliftingDefinitions(for: category)
        let custom = customExercises.filter { $0.category == .weightlifting && $0.weightliftingCategory == category }
        return builtin + custom
    }

    func cardioExercises() -> [ExerciseDefinition] {
        let builtin = BuiltinExerciseCatalog.cardioDefinitions()
        let custom = customExercises.filter { $0.category == .cardio }
        return builtin + custom
    }

    func allWeightliftingExercises() -> [ExerciseDefinition] {
        WeightliftingCategory.allCases.flatMap { weightliftingExercises(for: $0) }
    }

    func progressiveOverloadEntries(now: Date = .now) -> [ProgressiveOverloadEntry] {
        if let cache = cachedProgressiveEntries, cache.version == lastMutationAt {
            return cache.data
        }

        struct SessionSnapshot {
            let date: Date
            let logs: [ExerciseLog]
        }

        let current = SessionSnapshot(date: now, logs: logs)
        let archived = sessions.map { SessionSnapshot(date: $0.end, logs: $0.logs) }
        let snapshots = (archived + [current]).sorted(by: { $0.date < $1.date })

        struct Metric {
            let date: Date
            let weight: Double
            let volume: Double
            let symbol: String
        }

        var metricsByExercise: [String: [Metric]] = [:]

        for snapshot in snapshots {
            let lifts = snapshot.logs.filter { $0.category == .weightlifting }
            let grouped = Dictionary(grouping: lifts, by: { ExerciseNaming.displayName(name: $0.name, symbol: $0.symbol, category: $0.category) })

            for (exerciseName, exerciseLogs) in grouped {
                let maxWeight = exerciseLogs.compactMap(\.weightKilograms).max() ?? 0
                let totalVolume = exerciseLogs.reduce(0.0) { partial, log in
                    let reps = Double(log.reps ?? 0)
                    let sets = Double(log.sets ?? 1)
                    let weight = log.weightKilograms ?? 0
                    return partial + (weight * reps * sets)
                }
                let symbol = exerciseLogs.first?.symbol ?? "dumbbell.fill"

                metricsByExercise[exerciseName, default: []].append(
                    Metric(date: snapshot.date, weight: maxWeight, volume: totalVolume, symbol: symbol)
                )
            }
        }

        var results: [ProgressiveOverloadEntry] = []
        for (name, metrics) in metricsByExercise {
            let sorted = metrics.sorted(by: { $0.date < $1.date })
            guard let latest = sorted.last else { continue }
            let previous = sorted.count >= 2 ? sorted[sorted.count - 2] : nil
            results.append(
                ProgressiveOverloadEntry(
                    id: name.lowercased().replacingOccurrences(of: " ", with: "-"),
                    name: name,
                    symbol: latest.symbol,
                    latestWeight: latest.weight,
                    previousWeight: previous?.weight ?? 0,
                    latestVolume: latest.volume,
                    previousVolume: previous?.volume ?? 0,
                    latestSessionDate: latest.date
                )
            )
        }

        let sortedResults = results.sorted(by: { $0.latestSessionDate > $1.latestSessionDate })
        cachedProgressiveEntries = (lastMutationAt, sortedResults)
        return sortedResults
    }

    func progressiveOverloadPoints(now: Date = .now) -> [ProgressiveOverloadPoint] {
        if let cache = cachedProgressivePoints, cache.version == lastMutationAt {
            return cache.data
        }

        struct SessionSnapshot {
            let date: Date
            let logs: [ExerciseLog]
        }

        let current = SessionSnapshot(date: now, logs: logs)
        let archived = sessions.map { SessionSnapshot(date: $0.end, logs: $0.logs) }
        let snapshots = (archived + [current]).sorted(by: { $0.date < $1.date })

        var points: [ProgressiveOverloadPoint] = []
        var indexByExercise: [String: Int] = [:]

        for snapshot in snapshots {
            let lifts = snapshot.logs.filter { $0.category == .weightlifting }
            let grouped = Dictionary(grouping: lifts, by: { ExerciseNaming.displayName(name: $0.name, symbol: $0.symbol, category: $0.category) })

            for (exerciseName, exerciseLogs) in grouped {
                let maxWeight = exerciseLogs.compactMap(\.weightKilograms).max() ?? 0
                let volume = exerciseLogs.reduce(0.0) { partial, log in
                    let reps = Double(log.reps ?? 0)
                    let sets = Double(log.sets ?? 1)
                    let weight = log.weightKilograms ?? 0
                    return partial + (weight * reps * sets)
                }
                let nextIndex = (indexByExercise[exerciseName] ?? 0) + 1
                indexByExercise[exerciseName] = nextIndex

                points.append(
                    ProgressiveOverloadPoint(
                        exerciseName: exerciseName,
                        symbol: exerciseLogs.first?.symbol ?? "dumbbell.fill",
                        workoutIndex: nextIndex,
                        sessionDate: snapshot.date,
                        maxWeight: maxWeight,
                        volume: volume
                    )
                )
            }
        }

        let sortedPoints = points.sorted {
            if $0.exerciseName == $1.exerciseName { return $0.workoutIndex < $1.workoutIndex }
            return $0.exerciseName < $1.exerciseName
        }
        cachedProgressivePoints = (lastMutationAt, sortedPoints)
        return sortedPoints
    }

    func addCustomExercise(
        name: String,
        symbol: String,
        category: ExerciseCategory,
        weightliftingCategory: WeightliftingCategory?,
        targetMuscles: [String]
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let definition = ExerciseDefinition(
            id: "custom-\(UUID().uuidString)",
            name: trimmed,
            symbol: symbol,
            category: category,
            weightliftingCategory: category == .weightlifting ? weightliftingCategory : nil,
            targetMuscles: targetMuscles,
            isCustom: true
        )

        customExercises.append(definition)
        persist()
    }

    func removeCustomExercise(id: String) {
        customExercises.removeAll(where: { $0.id == id })
        persist()
    }

    func availableCustomSymbols() -> [String] {
        if let cache = cachedAvailableSymbols, cache.version == lastMutationAt {
            return cache.data
        }
        let used = Set(BuiltinExerciseCatalog.allSymbols + customExercises.map(\.symbol))
        let symbols = SymbolLibrary.unusedSymbols(existing: Array(used))
        cachedAvailableSymbols = (lastMutationAt, symbols)
        return symbols
    }

    func exportBackupData() throws -> Data {
        let payload = LiftWatchBackupPayload(
            logs: logs,
            sessions: sessions,
            customExercises: customExercises,
            settings: settings,
            lastSessionStart: lastSessionStart
        )
        let envelope = LiftWatchBackupEnvelope(payload: payload)
        guard let data = try? encoder.encode(envelope) else {
            throw BackupError.encodeFailed
        }
        return data
    }

    func importBackupData(_ data: Data) throws {
        if let envelope = try? decoder.decode(LiftWatchBackupEnvelope.self, from: data) {
            guard envelope.schemaVersion <= LiftWatchBackupEnvelope.currentSchemaVersion else {
                throw BackupError.unsupportedSchema(envelope.schemaVersion)
            }
            applyBackupPayload(envelope.payload)
            return
        }

        // Migration fallback: allow importing legacy persisted-state blobs.
        if let legacyState = try? decoder.decode(PersistedState.self, from: data) {
            applyBackupPayload(
                LiftWatchBackupPayload(
                    logs: legacyState.logs,
                    sessions: legacyState.sessions,
                    customExercises: legacyState.customExercises,
                    settings: legacyState.settings,
                    lastSessionStart: legacyState.lastSessionStart
                )
            )
            return
        }

        throw BackupError.invalidFile
    }

    private func applyBackupPayload(_ payload: LiftWatchBackupPayload) {
        isHydratingState = true
        defer { isHydratingState = false }

        logs = payload.logs.sorted(by: { $0.createdAt > $1.createdAt })
        sessions = payload.sessions.sorted(by: { $0.end > $1.end })
        customExercises = payload.customExercises
        settings = payload.settings.encodedForPersistence()
        lastSessionStart = payload.lastSessionStart

        rollSessionIfNeeded(now: .now, persistChanges: false)
        persist()
        scheduleRolloverTask()
    }

    private func rollSessionIfNeeded(now: Date, persistChanges: Bool = true) {
        let sessionStart = currentSessionStart(now: now)

        guard sessionStart > lastSessionStart else { return }

        if !logs.isEmpty {
            let archived = WorkoutSession(start: lastSessionStart, end: sessionStart, logs: logs)
            sessions.insert(archived, at: 0)
            logs = []
        }

        lastSessionStart = sessionStart
        if persistChanges {
            persist()
        }
    }

    private func handleSettingsChanged() {
        rollSessionIfNeeded(now: .now, persistChanges: false)
        persist()
        scheduleRolloverTask()
    }

    private func mutateSettings(_ mutation: (inout AppSettings) -> Void) {
        var next = settings
        mutation(&next)
        guard next != settings else { return }
        isMutatingSettingsInternally = true
        settings = next
        isMutatingSettingsInternally = false
        handleSettingsChanged()
    }

    private func currentSessionStart(now: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: now)
        let cutoffMinutes = min(max(settings.cutoffMinutes, 0), 23 * 60 + 59)
        let cutoffToday = calendar.date(byAdding: .minute, value: cutoffMinutes, to: startOfDay) ?? startOfDay
        if now >= cutoffToday {
            return cutoffToday
        }
        return calendar.date(byAdding: .day, value: -1, to: cutoffToday) ?? cutoffToday
    }

    private func nextSessionStart(after date: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let currentStart = currentSessionStart(now: date)
        return calendar.date(byAdding: .day, value: 1, to: currentStart) ?? date.addingTimeInterval(86_400)
    }

    private func scheduleRolloverTask() {
        rolloverTask?.cancel()

        let nextStart = nextSessionStart(after: .now)
        let interval = max(1, nextStart.timeIntervalSinceNow)

        rolloverTask = Task { [weak self] in
            let nanos = UInt64(interval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            await MainActor.run {
                self?.rollSessionIfNeeded(now: .now)
                self?.scheduleRolloverTask()
            }
        }
    }

    private func persist() {
        let sanitizedSettings = prunedSettingsForPersistence(from: settings)
        let payload = LiftWatchBackupPayload(
            logs: logs,
            sessions: sessions,
            customExercises: customExercises,
            settings: sanitizedSettings,
            lastSessionStart: lastSessionStart
        )
        let envelope = LiftWatchBackupEnvelope(payload: payload)

        guard let data = try? encoder.encode(envelope) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        lastMutationAt = .now
        onStateDidPersist?()
    }

    private func load() {
        isHydratingState = true
        defer { isHydratingState = false }

        if let data = UserDefaults.standard.data(forKey: defaultsKey) {
            if let envelope = try? decoder.decode(LiftWatchBackupEnvelope.self, from: data) {
                applyDecodedPayload(envelope.payload)
                return
            }
            if let state = try? decoder.decode(PersistedState.self, from: data) {
                applyDecodedPayload(
                    LiftWatchBackupPayload(
                        logs: state.logs,
                        sessions: state.sessions,
                        customExercises: state.customExercises,
                        settings: state.settings,
                        lastSessionStart: state.lastSessionStart
                    )
                )
                persist()
                return
            }
        }

        if let data = UserDefaults.standard.data(forKey: legacyDefaultsKeyV2),
           let legacy = try? decoder.decode(PersistedState.self, from: data) {
            applyDecodedPayload(
                LiftWatchBackupPayload(
                    logs: legacy.logs,
                    sessions: legacy.sessions,
                    customExercises: legacy.customExercises,
                    settings: legacy.settings,
                    lastSessionStart: legacy.lastSessionStart
                )
            )
            persist()
            return
        }

        if let data = UserDefaults.standard.data(forKey: legacyDefaultsKeyV1),
           let legacy = try? decoder.decode(PersistedState.self, from: data) {
            applyDecodedPayload(
                LiftWatchBackupPayload(
                    logs: legacy.logs,
                    sessions: legacy.sessions,
                    customExercises: [],
                    settings: legacy.settings,
                    lastSessionStart: legacy.lastSessionStart
                )
            )
            persist()
            return
        }

        lastSessionStart = currentSessionStart(now: .now)
    }

    private func applyDecodedPayload(_ payload: LiftWatchBackupPayload) {
        logs = payload.logs.sorted(by: { $0.createdAt > $1.createdAt })
        sessions = payload.sessions.sorted(by: { $0.end > $1.end })
        customExercises = payload.customExercises
        settings = payload.settings.encodedForPersistence()
        lastSessionStart = payload.lastSessionStart
    }

    private func dayLabel(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func weekLabel(start: Date) -> String {
        let end = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(shortDateFormatter.string(from: start)) - \(shortDateFormatter.string(from: end))"
    }

    private func monthLabel(for date: Date) -> String {
        monthFormatter.string(from: date)
    }

    private func positiveModulo(_ value: Int, _ modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        let remainder = value % modulo
        return remainder >= 0 ? remainder : remainder + modulo
    }

    private func planDay(forSessionStart sessionStart: Date) -> PlanDay {
        let days = settings.planDays.isEmpty ? PlanDay.defaultWeek : settings.planDays
        let index = planDayIndex(forSessionStart: sessionStart) ?? 0
        return days[index]
    }

    private func planDayIndex(forSessionStart sessionStart: Date) -> Int? {
        let days = settings.planDays.isEmpty ? PlanDay.defaultWeek : settings.planDays
        guard !days.isEmpty else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let anchorStart = calendar.startOfDay(for: settings.planAnchorDate)
        let targetStart = calendar.startOfDay(for: sessionStart)
        let elapsed = calendar.dateComponents([.day], from: anchorStart, to: targetStart).day ?? 0
        return positiveModulo(elapsed + settings.planShiftDays, days.count)
    }

    private func planDayKey(for date: Date) -> String {
        planDayKeyFormatter.string(from: date)
    }

    private func movePlanDay(from sourceIndex: Int, to destinationIndex: Int) {
        guard settings.planDays.indices.contains(sourceIndex),
              settings.planDays.indices.contains(destinationIndex),
              sourceIndex != destinationIndex
        else { return }

        mutateSettings { settings in
            guard settings.planDays.indices.contains(sourceIndex),
                  settings.planDays.indices.contains(destinationIndex)
            else { return }

            let sourceWorkout = settings.planDays[sourceIndex].workout
            settings.planDays[sourceIndex].workout = settings.planDays[destinationIndex].workout
            settings.planDays[destinationIndex].workout = sourceWorkout

            let sourceExerciseIDs = settings.planExerciseIDsByDay[sourceIndex]
            let destinationExerciseIDs = settings.planExerciseIDsByDay[destinationIndex]
            settings.planExerciseIDsByDay[sourceIndex] = destinationExerciseIDs
            settings.planExerciseIDsByDay[destinationIndex] = sourceExerciseIDs
        }
    }

    private func removePlannedWorkout(_ item: PlannedWorkoutItem) {
        switch item.source {
        case .base:
            mutateSettings { settings in
                settings.hiddenBasePlanDates.insert(item.dayKey)
            }
        case .extra:
            mutateSettings { settings in
                guard var extras = settings.temporaryPlanByDate[item.dayKey], !extras.isEmpty else { return }
                if let index = extras.firstIndex(of: item.workout) {
                    extras.remove(at: index)
                } else {
                    extras.removeLast()
                }
                if extras.isEmpty {
                    settings.temporaryPlanByDate[item.dayKey] = nil
                } else {
                    settings.temporaryPlanByDate[item.dayKey] = extras
                }
            }
        }
    }

    private func removePlannedExercise(_ item: PlannedExerciseItem) {
        switch item.source {
        case .base:
            mutateSettings { settings in
                var hidden = settings.hiddenPlannedExerciseIDsByDate[item.dayKey] ?? []
                if !hidden.contains(item.id) {
                    hidden.append(item.id)
                }
                settings.hiddenPlannedExerciseIDsByDate[item.dayKey] = hidden
            }
        case .extraExercise:
            mutateSettings { settings in
                guard var extras = settings.temporaryExercisePlanByDate[item.dayKey], !extras.isEmpty else { return }
                if let index = extras.firstIndex(where: { extra in
                    extra.workout == item.workout && extra.exerciseID == item.exerciseID
                }) {
                    extras.remove(at: index)
                } else {
                    extras.removeLast()
                }
                if extras.isEmpty {
                    settings.temporaryExercisePlanByDate[item.dayKey] = nil
                } else {
                    settings.temporaryExercisePlanByDate[item.dayKey] = extras
                }
            }
        case .extraWorkoutLegacy:
            mutateSettings { settings in
                guard var extras = settings.temporaryPlanByDate[item.dayKey], !extras.isEmpty else { return }
                if let index = extras.firstIndex(of: item.workout) {
                    extras.remove(at: index)
                } else {
                    extras.removeLast()
                }
                if extras.isEmpty {
                    settings.temporaryPlanByDate[item.dayKey] = nil
                } else {
                    settings.temporaryPlanByDate[item.dayKey] = extras
                }
            }
        }
    }

    private func prunedSettingsForPersistence(from value: AppSettings) -> AppSettings {
        var result = value
        let todayKey = planDayKey(for: currentSessionStart(now: .now))
        guard let todayDate = planDayKeyFormatter.date(from: todayKey) else { return result }
        let cutoffDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -14, to: todayDate) ?? todayDate

        result.temporaryPlanByDate = result.temporaryPlanByDate.filter { key, _ in
            guard let date = planDayKeyFormatter.date(from: key) else { return false }
            return date >= cutoffDate
        }

        result.temporaryExercisePlanByDate = result.temporaryExercisePlanByDate.filter { key, _ in
            guard let date = planDayKeyFormatter.date(from: key) else { return false }
            return date >= cutoffDate
        }

        result.hiddenBasePlanDates = Set(result.hiddenBasePlanDates.filter { key in
            guard let date = planDayKeyFormatter.date(from: key) else { return false }
            return date >= cutoffDate
        })

        result.hiddenPlannedExerciseIDsByDate = result.hiddenPlannedExerciseIDsByDate.filter { key, value in
            guard let date = planDayKeyFormatter.date(from: key), date >= cutoffDate else { return false }
            return !value.isEmpty
        }

        var cleanedPlanIDs: [Int: [String]] = [:]
        let validAll = Set(allPlanSelectableExercises().map(\.id))
        for (dayIndex, ids) in result.planExerciseIDsByDay {
            guard result.planDays.indices.contains(dayIndex) else { continue }
            let filtered = uniquePreservingOrder(ids.filter { validAll.contains($0) })
            if !filtered.isEmpty {
                cleanedPlanIDs[dayIndex] = filtered
            }
        }
        result.planExerciseIDsByDay = cleanedPlanIDs
        return result
    }

    func allPlanSelectableExercises() -> [ExerciseDefinition] {
        WeightliftingCategory.allCases.flatMap { weightliftingExercises(for: $0) } + cardioExercises()
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        unique.reserveCapacity(values.count)
        for value in values where !seen.contains(value) {
            seen.insert(value)
            unique.append(value)
        }
        return unique
    }

    private func deduplicatedLogsKeepingLatest(_ input: [ExerciseLog]) -> [ExerciseLog] {
        let sorted = input.sorted(by: { $0.createdAt > $1.createdAt })
        var seen: Set<String> = []
        var unique: [ExerciseLog] = []
        unique.reserveCapacity(sorted.count)
        for log in sorted {
            let key = logDuplicateKey(for: log)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(log)
        }
        return unique
    }

    private func logDuplicateKey(for log: ExerciseLog) -> String {
        let nameKey = plannedExerciseDuplicateKey(name: log.name)
        if log.category == .cardio {
            return "cardio|\(nameKey)"
        }
        return "weight|\(log.weightliftingCategory?.rawValue ?? "uncategorized")|\(nameKey)"
    }

    private func plannedExerciseDuplicateKey(name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func planExerciseID(for log: ExerciseLog) -> String {
        if let match = allPlanSelectableExercises().first(where: { definition in
            definition.name.caseInsensitiveCompare(log.name) == .orderedSame &&
                definition.category == log.category &&
                (log.category == .cardio || definition.weightliftingCategory == log.weightliftingCategory)
        }) {
            return match.id
        }
        return "name-\(plannedExerciseDuplicateKey(name: log.name))"
    }
}
