import Foundation

@MainActor
final class ExerciseStore: ObservableObject {
    @Published private(set) var logs: [ExerciseLog] = []
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published private(set) var customExercises: [ExerciseDefinition] = []
    @Published private(set) var lastMutationAt: Date = .now
    @Published var settings: AppSettings = AppSettings() {
        didSet {
            guard !isHydratingState else { return }
            rollSessionIfNeeded(now: .now, persistChanges: false)
            persist()
            scheduleRolloverTask()
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
    private var lastSessionStart: Date
    private var rolloverTask: Task<Void, Never>?
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
        logs.insert(log, at: 0)
        persist()
    }

    func addAll(_ incoming: [ExerciseLog]) {
        rollSessionIfNeeded(now: .now, persistChanges: false)
        let merged = Set(logs).union(incoming)
        logs = merged.sorted(by: { $0.createdAt > $1.createdAt })
        persist()
    }

    func replaceAll(with incoming: [ExerciseLog]) {
        rollSessionIfNeeded(now: .now, persistChanges: false)
        logs = Array(Set(incoming)).sorted(by: { $0.createdAt > $1.createdAt })
        persist()
    }

    func remove(id: UUID) {
        logs.removeAll(where: { $0.id == id })
        persist()
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
        settings.cutoffMinutes = min(max(minutes, 0), 23 * 60 + 59)
    }

    func previousSession() -> WorkoutSession? {
        sessions.sorted(by: { $0.end > $1.end }).first
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
                let maxWeight = exerciseLogs.compactMap(\.weight).max() ?? 0
                let totalVolume = exerciseLogs.reduce(0.0) { partial, log in
                    let reps = Double(log.reps ?? 0)
                    let sets = Double(log.sets ?? 1)
                    let weight = log.weight ?? 0
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

        return results.sorted(by: { $0.latestSessionDate > $1.latestSessionDate })
    }

    func progressiveOverloadPoints(now: Date = .now) -> [ProgressiveOverloadPoint] {
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
                let maxWeight = exerciseLogs.compactMap(\.weight).max() ?? 0
                let volume = exerciseLogs.reduce(0.0) { partial, log in
                    let reps = Double(log.reps ?? 0)
                    let sets = Double(log.sets ?? 1)
                    let weight = log.weight ?? 0
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

        return points.sorted {
            if $0.exerciseName == $1.exerciseName { return $0.workoutIndex < $1.workoutIndex }
            return $0.exerciseName < $1.exerciseName
        }
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
        let used = Set(BuiltinExerciseCatalog.allSymbols + customExercises.map(\.symbol))
        return SymbolLibrary.unusedSymbols(existing: Array(used))
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
        settings = payload.settings
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

    private func currentSessionStart(now: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: now)
        let cutoffToday = calendar.date(byAdding: .minute, value: settings.cutoffMinutes, to: startOfDay) ?? startOfDay
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
        let payload = LiftWatchBackupPayload(
            logs: logs,
            sessions: sessions,
            customExercises: customExercises,
            settings: settings,
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
        settings = payload.settings
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
}
