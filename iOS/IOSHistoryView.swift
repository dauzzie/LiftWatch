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

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.08, green: 0.10, blue: 0.14), Color(red: 0.06, green: 0.12, blue: 0.20)]
                        : [Color(red: 0.95, green: 0.98, blue: 1.0), Color(red: 0.90, green: 0.95, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        Picker("Range", selection: $range) {
                            ForEach(HistoryRange.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)

                        previousSessionCard
                        progressiveOverloadCard

                        VStack(spacing: 10) {
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
                                .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var progressiveOverloadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progressive Overload")
                .font(.headline)

            let points = store.progressiveOverloadPoints()
            let exerciseNames = Array(Set(points.map(\.exerciseName))).sorted()

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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.9)
    }

    private func dateText(_ date: Date) -> String {
        Self.mediumDateTimeFormatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        Self.shortTimeFormatter.string(from: date)
    }

    private var yTitle: String {
        selectedMetric == .maxWeight ? "Max Weight (lb)" : "Volume"
    }

    private func yValue(for point: ProgressiveOverloadPoint) -> Double {
        selectedMetric == .maxWeight ? point.maxWeight : point.volume
    }

    private func formattedValue(for point: ProgressiveOverloadPoint) -> String {
        if selectedMetric == .maxWeight {
            return point.maxWeight.formatted(.number.precision(.fractionLength(0...1))) + " lb"
        }
        return point.volume.formatted(.number.precision(.fractionLength(0...0)))
    }
}

#Preview {
    IOSHistoryView()
        .environmentObject(ExerciseStore())
}
