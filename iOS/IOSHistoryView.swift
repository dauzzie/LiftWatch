import SwiftUI

struct IOSHistoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: ExerciseStore
    @State private var range: HistoryRange = .daily

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
                        Text(log.name)
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

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.9)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    IOSHistoryView()
        .environmentObject(ExerciseStore())
}
