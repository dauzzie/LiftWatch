import Foundation

@MainActor
final class ExerciseStore: ObservableObject {
    @Published private(set) var logs: [ExerciseLog] = []
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published private(set) var customExercises: [ExerciseDefinition] = []
    @Published var settings: AppSettings = AppSettings() {
        didSet {
            guard !isHydratingState else { return }
            persist()
            rollSessionIfNeeded(now: .now)
            scheduleRolloverTask()
        }
    }

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

    private let defaultsKey = "liftwatch.persisted.state.v2"
    private let legacyDefaultsKey = "liftwatch.persisted.state.v1"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var isHydratingState = false
    private var lastSessionStart: Date
    private var rolloverTask: Task<Void, Never>?

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
        rollSessionIfNeeded(now: .now)
        logs.insert(log, at: 0)
        persist()
    }

    func addAll(_ incoming: [ExerciseLog]) {
        rollSessionIfNeeded(now: .now)
        let merged = Set(logs).union(incoming)
        logs = merged.sorted(by: { $0.createdAt > $1.createdAt })
        persist()
    }

    func replaceAll(with incoming: [ExerciseLog]) {
        rollSessionIfNeeded(now: .now)
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
        rollSessionIfNeeded(now: .now)
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

    private func rollSessionIfNeeded(now: Date) {
        let sessionStart = currentSessionStart(now: now)

        guard sessionStart > lastSessionStart else { return }

        if !logs.isEmpty {
            let archived = WorkoutSession(start: lastSessionStart, end: sessionStart, logs: logs)
            sessions.insert(archived, at: 0)
            logs = []
        }

        lastSessionStart = sessionStart
        persist()
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
        let state = PersistedState(
            logs: logs,
            sessions: sessions,
            customExercises: customExercises,
            settings: settings,
            lastSessionStart: lastSessionStart
        )

        guard let data = try? encoder.encode(state) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        isHydratingState = true
        defer { isHydratingState = false }

        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let state = try? decoder.decode(PersistedState.self, from: data) {
            logs = state.logs.sorted(by: { $0.createdAt > $1.createdAt })
            sessions = state.sessions.sorted(by: { $0.end > $1.end })
            customExercises = state.customExercises
            settings = state.settings
            lastSessionStart = state.lastSessionStart
            return
        }

        if let legacyData = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let legacy = try? decoder.decode(PersistedState.self, from: legacyData) {
            logs = legacy.logs.sorted(by: { $0.createdAt > $1.createdAt })
            sessions = legacy.sessions.sorted(by: { $0.end > $1.end })
            customExercises = []
            settings = legacy.settings
            lastSessionStart = legacy.lastSessionStart
            persist()
            return
        }

        lastSessionStart = currentSessionStart(now: .now)
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }

    private func weekLabel(start: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let end = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}
