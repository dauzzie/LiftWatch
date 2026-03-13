import Foundation

struct WorkoutSession: Identifiable, Codable, Hashable {
    let id: UUID
    let start: Date
    let end: Date
    let logs: [ExerciseLog]

    init(id: UUID = UUID(), start: Date, end: Date, logs: [ExerciseLog]) {
        self.id = id
        self.start = start
        self.end = end
        self.logs = logs
    }
}

struct WorkoutHistoryPoint: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let workoutCount: Int
    let totalSets: Int
    let totalMinutes: Int
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: Self { self }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}
