import SwiftUI

struct IOSContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: ExerciseStore
    @EnvironmentObject private var sync: WatchSyncManager
    @EnvironmentObject private var cloud: CloudSyncManager
    @State private var isPresentingAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: backgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill((colorScheme == .dark ? Color.blue : Color(red: 0.39, green: 0.63, blue: 0.98)).opacity(0.22))
                    .frame(width: 260, height: 260)
                    .blur(radius: 8)
                    .offset(x: 140, y: -260)

                Circle()
                    .fill((colorScheme == .dark ? Color.green : Color(red: 0.17, green: 0.80, blue: 0.62)).opacity(0.2))
                    .frame(width: 240, height: 240)
                    .blur(radius: 10)
                    .offset(x: -150, y: 250)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summaryCard
                        syncStatusCard

                        if store.logs.isEmpty {
                            emptyStateCard
                        } else {
                            ForEach(store.logs) { log in
                                workoutCard(for: log)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("LiftWatch")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sync") {
                        sync.syncBidirectional()
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $isPresentingAdd) {
                AddExerciseView { log in
                    store.add(log)
                    sync.send(log: log)
                }
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 16) {
            statPill(title: "Total", value: "\(store.logs.count)")
            statPill(title: "Lifts", value: "\(store.logs.filter { $0.category == .weightlifting }.count)")
            statPill(title: "Cardio", value: "\(store.logs.filter { $0.category == .cardio }.count)")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.6), lineWidth: 1)
        )
    }

    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            syncRow(
                title: "Watch",
                status: sync.syncStatus,
                detail: sync.syncDetail,
                color: syncColor,
                icon: "applewatch"
            )
            syncRow(
                title: "Cloud",
                status: cloud.syncStatus,
                detail: cloud.syncDetail,
                color: cloudColor,
                icon: "icloud.fill"
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func syncRow(title: String, status: String, detail: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text("\(title): \(status)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                Spacer()
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func workoutCard(for log: ExerciseLog) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(workoutColor(for: log).opacity(0.14))
                Image(systemName: log.symbol)
                    .font(.title3)
                    .foregroundStyle(workoutColor(for: log))
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(ExerciseNaming.displayName(name: log.name, symbol: log.symbol, category: log.category))
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(categoryTag(for: log))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(workoutColor(for: log))
                    Spacer()
                    Button {
                        store.remove(id: log.id)
                        sync.sendAll()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
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
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
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
        switch log.category {
        case .weightlifting:
            let sets = log.sets ?? 0
            let reps = log.reps ?? 0
            let weight = (log.weight ?? 0).formatted(.number.precision(.fractionLength(0...1)))
            return "\(sets) sets • \(reps) reps • \(weight) lb"
        case .cardio:
            let minutes = log.minutes ?? 0
            if let pace = log.pace, !pace.isEmpty {
                return "\(minutes) min • Avg pace \(pace)"
            }
            return "\(minutes) min"
        }
    }

    private var backgroundGradient: [Color] {
        if colorScheme == .dark {
            return [Color(red: 0.07, green: 0.09, blue: 0.13), Color(red: 0.05, green: 0.12, blue: 0.19)]
        }
        return [Color(red: 0.93, green: 0.97, blue: 1.0), Color(red: 0.89, green: 0.93, blue: 0.99)]
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.88)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.75)
    }

    private var syncColor: Color {
        switch sync.syncLevel {
        case .idle: return .secondary
        case .syncing: return .orange
        case .success: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }

    private var cloudColor: Color {
        switch cloud.syncLevel {
        case .idle: return .secondary
        case .syncing: return .orange
        case .success: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }
}

#Preview {
    IOSContentView()
        .environmentObject(ExerciseStore())
        .environmentObject(WatchSyncManager())
        .environmentObject(CloudSyncManager())
}
