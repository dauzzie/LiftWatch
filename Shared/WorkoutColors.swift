import SwiftUI

enum WorkoutColors {
    static func color(for log: ExerciseLog) -> Color {
        if log.category == .cardio {
            return Color(red: 0.11, green: 0.66, blue: 0.43)
        }

        switch log.weightliftingCategory {
        case .push:
            return Color(red: 0.97, green: 0.47, blue: 0.21)
        case .pull:
            return Color(red: 0.15, green: 0.48, blue: 0.93)
        case .legs:
            return Color(red: 0.43, green: 0.76, blue: 0.21)
        case .abs:
            return Color(red: 0.86, green: 0.22, blue: 0.39)
        case .none:
            return Color(red: 0.26, green: 0.56, blue: 0.96)
        }
    }
}
