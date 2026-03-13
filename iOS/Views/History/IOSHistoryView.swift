import SwiftUI
import Charts

struct IOSHistoryView: View {
    private static let mediumDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: ExerciseStore
    @State private var range: HistoryRange = .daily
    @State private var selectedExercise = ""
    @State private var selectedMetric: ProgressiveMetric = .maxWeight

    private var progressivePoints: [ProgressiveOverloadPoint] {
        store.progressiveOverloadPoints()
    }

    private var exerciseNames: [String] {
        Array(Set(progressivePoints.map(\.exerciseName))).sorted()
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
                    LazyVStack(spacing: 14) {
                        Picker("Range", selection: $range) {
                            ForEach(HistoryRange.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)

                        previousSessionCard
                        progressiveOverloadCard

                        LazyVStack(spacing: 10) {
                            ForEach(store.historyPoints(for: range)) { point in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(point.label)
                                            .font(.headline)
                                        Text("\(point.workoutCount) workouts • \(point.totalSets) sets • \(point.totalMinutes) min")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .liftWatchCardStyle(colorScheme: colorScheme, cornerRadius: 14)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(point.label)
                                .accessibilityValue("\(point.workoutCount) workouts, \(point.totalSets) sets, \(point.totalMinutes) minutes")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("History")
        }
    }

    private var previousSessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Previous Session")
                .font(.headline)

            if let previous = store.previousSession() {
                Text("\(dateText(previous.start)) - \(timeText(previous.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(previous.logs.prefix(5)) { log in
                    HStack {
                        Image(systemName: log.symbol)
                            .foregroundStyle(WorkoutColors.color(for: log))
                        Text(ExerciseNaming.displayName(name: log.name, symbol: log.symbol, category: log.category))
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }

                if previous.logs.count > 5 {
                    Text("+\(previous.logs.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No previous session yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liftWatchCardStyle(colorScheme: colorScheme, cornerRadius: 16)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private var progressiveOverloadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progressive Overload")
                .font(.headline)

            let points = progressivePoints

            if points.isEmpty {
                Text("No weightlifting progression data yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Exercise", selection: $selectedExercise) {
                    ForEach(exerciseNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    if selectedExercise.isEmpty {
                        selectedExercise = exerciseNames.first ?? ""
                    }
                }
                .onChange(of: exerciseNames) { _, names in
                    if !names.contains(selectedExercise) {
                        selectedExercise = names.first ?? ""
                    }
                }

                Picker("Metric", selection: $selectedMetric) {
                    ForEach(ProgressiveMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                let selected = points
                    .filter { $0.exerciseName == selectedExercise }
                    .sorted(by: { $0.workoutIndex < $1.workoutIndex })

                if selected.isEmpty {
                    Text("No data for selected exercise.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(selected) { point in
                        LineMark(
                            x: .value("Workout #", point.workoutIndex),
                            y: .value(yTitle, yValue(for: point))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.orange)

                        PointMark(
                            x: .value("Workout #", point.workoutIndex),
                            y: .value(yTitle, yValue(for: point))
                        )
                        .foregroundStyle(.orange)
                    }
                    .frame(height: 180)
                    .accessibilityLabel("\(selectedExercise) progression chart")
                    .accessibilityValue("Showing \(selected.count) workouts by \(selectedMetric.title.lowercased())")
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: max(2, selected.count))) { _ in
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }

                    if let last = selected.last {
                        Text("Workouts logged: \(selected.count) • Latest \(selectedMetric.title.lowercased()): \(formattedValue(for: last))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liftWatchCardStyle(colorScheme: colorScheme, cornerRadius: 16)
        .padding(.horizontal, 16)
    }

    private func dateText(_ date: Date) -> String {
        Self.mediumDateTimeFormatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        Self.shortTimeFormatter.string(from: date)
    }

    private var yTitle: String {
        let unit = store.settings.preferredWeightUnit.symbol
        return selectedMetric == .maxWeight ? "Max Weight (\(unit))" : "Volume (\(unit)-reps)"
    }

    private func yValue(for point: ProgressiveOverloadPoint) -> Double {
        selectedMetric == .maxWeight
            ? store.settings.preferredWeightUnit.fromKilograms(point.maxWeight)
            : store.settings.preferredWeightUnit.fromKilograms(point.volume)
    }

    private func formattedValue(for point: ProgressiveOverloadPoint) -> String {
        let unit = store.settings.preferredWeightUnit.symbol
        if selectedMetric == .maxWeight {
            let value = store.settings.preferredWeightUnit.fromKilograms(point.maxWeight)
            return value.formatted(.number.precision(.fractionLength(0...1))) + " " + unit
        }
        let value = store.settings.preferredWeightUnit.fromKilograms(point.volume)
        return value.formatted(.number.precision(.fractionLength(0...0))) + " " + unit + "-reps"
    }
}

#Preview {
    IOSHistoryView()
        .environmentObject(ExerciseStore())
}
