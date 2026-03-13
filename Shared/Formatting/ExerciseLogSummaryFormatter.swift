import Foundation

enum ExerciseLogSummaryStyle {
    case iOS
    case watch
}

enum ExerciseLogSummaryFormatter {
    static func summary(for log: ExerciseLog, preferredUnit: WeightUnit, style: ExerciseLogSummaryStyle) -> String {
        switch log.category {
        case .weightlifting:
            let sets = log.sets ?? 0
            let reps = log.reps ?? 0
            let displayWeight = (log.weight(in: preferredUnit) ?? 0).formatted(.number.precision(.fractionLength(0...1)))

            switch style {
            case .iOS:
                return "\(sets) sets • \(reps) reps • \(displayWeight) \(preferredUnit.symbol)"
            case .watch:
                let setsText = "\(sets)x\(reps)"
                let group = log.weightliftingCategory?.title ?? "Lift"
                return "\(group) • \(setsText) @ \(displayWeight)\(preferredUnit.symbol)"
            }

        case .cardio:
            let minutes = log.minutes ?? 0
            switch style {
            case .iOS:
                if let pace = log.pace, !pace.isEmpty {
                    return "\(minutes) min • Avg pace \(pace)"
                }
                return "\(minutes) min"
            case .watch:
                if let pace = log.pace, !pace.isEmpty {
                    return "\(minutes)m • Avg \(pace)"
                }
                return "\(minutes)m"
            }
        }
    }
}
