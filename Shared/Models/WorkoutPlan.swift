import Foundation

enum PlanWorkoutType: String, Codable, CaseIterable, Identifiable {
    case push
    case pull
    case legs
    case abs
    case cardio
    case rest

    var id: Self { self }

    var title: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .abs: return "Abs"
        case .cardio: return "Cardio"
        case .rest: return "Rest"
        }
    }

    var symbol: String {
        switch self {
        case .push: return WeightliftingCategory.push.symbol
        case .pull: return WeightliftingCategory.pull.symbol
        case .legs: return WeightliftingCategory.legs.symbol
        case .abs: return WeightliftingCategory.abs.symbol
        case .cardio: return "figure.run.circle.fill"
        case .rest: return "bed.double.fill"
        }
    }
}

struct PlanDay: Codable, Hashable, Identifiable {
    var id: Int
    var label: String
    var workout: PlanWorkoutType

    static func defaultLabel(for index: Int) -> String {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard labels.indices.contains(index) else { return "Day \(index + 1)" }
        return labels[index]
    }

    static var defaultWeek: [PlanDay] {
        [
            PlanDay(id: 0, label: defaultLabel(for: 0), workout: .push),
            PlanDay(id: 1, label: defaultLabel(for: 1), workout: .pull),
            PlanDay(id: 2, label: defaultLabel(for: 2), workout: .legs),
            PlanDay(id: 3, label: defaultLabel(for: 3), workout: .abs),
            PlanDay(id: 4, label: defaultLabel(for: 4), workout: .cardio),
            PlanDay(id: 5, label: defaultLabel(for: 5), workout: .rest),
            PlanDay(id: 6, label: defaultLabel(for: 6), workout: .rest)
        ]
    }
}

struct AddExerciseDefaults {
    var workoutType: ExerciseCategory
    var weightliftingCategory: WeightliftingCategory?
    var preferredExerciseID: String?
    var plannedExerciseIDs: [String]? = nil
}

enum PlannedWorkoutSource: Hashable {
    case base
    case extra
}

struct PlannedWorkoutItem: Identifiable, Hashable {
    let id: String
    let workout: PlanWorkoutType
    let source: PlannedWorkoutSource
    let dayKey: String
}

struct TemporaryPlannedExercise: Codable, Hashable {
    var workout: PlanWorkoutType
    var exerciseID: String
    var exerciseName: String
    var exerciseSymbol: String
}

enum PlannedExerciseSource: Hashable {
    case base
    case extraExercise
    case extraWorkoutLegacy
}

struct PlannedExerciseItem: Identifiable, Hashable {
    let id: String
    let dayKey: String
    let workout: PlanWorkoutType
    let source: PlannedExerciseSource
    let exerciseID: String
    let exerciseName: String
    let exerciseSymbol: String
}
