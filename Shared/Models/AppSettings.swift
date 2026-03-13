import Foundation

struct AppSettings: Codable, Hashable {
    static let defaultMaxWeightKilograms = WeightUnit.pounds.toKilograms(500)
    static let minMaxWeightKilograms = WeightUnit.pounds.toKilograms(20)
    static let hardMaxWeightKilograms = WeightUnit.pounds.toKilograms(1_200)

    // Minutes from midnight local time. Default 3:00 AM.
    var cutoffMinutes: Int = 180
    var preferredWeightUnit: WeightUnit = .pounds
    var maxWeightKilograms: Double = AppSettings.defaultMaxWeightKilograms
    var planDays: [PlanDay] = PlanDay.defaultWeek
    var planAnchorDate: Date = .now
    var planShiftDays: Int = 0
    var planExerciseIDsByDay: [Int: [String]] = [:]
    var temporaryPlanByDate: [String: [PlanWorkoutType]] = [:]
    var temporaryExercisePlanByDate: [String: [TemporaryPlannedExercise]] = [:]
    var hiddenBasePlanDates: Set<String> = []
    var hiddenPlannedExerciseIDsByDate: [String: [String]] = [:]

    var cutoffHour: Int { cutoffMinutes / 60 }
    var cutoffMinute: Int { cutoffMinutes % 60 }

    var normalizedMaxWeightKilograms: Double {
        min(max(maxWeightKilograms, AppSettings.minMaxWeightKilograms), AppSettings.hardMaxWeightKilograms)
    }

    var maxWeightInPreferredUnit: Double {
        preferredWeightUnit.fromKilograms(normalizedMaxWeightKilograms)
    }

    var cutoffDateComponents: DateComponents {
        DateComponents(hour: cutoffHour, minute: cutoffMinute)
    }

    private static func normalizedCutoffMinutes(_ value: Int) -> Int {
        min(max(value, 0), 23 * 60 + 59)
    }

    private static func normalizedPlanDays(_ input: [PlanDay]) -> [PlanDay] {
        var days = input
        if days.isEmpty {
            days = PlanDay.defaultWeek
        }
        for index in days.indices {
            days[index].id = index
            days[index].label = PlanDay.defaultLabel(for: index)
        }
        return days
    }

    private enum CodingKeys: String, CodingKey {
        case cutoffMinutes
        case preferredWeightUnit
        case maxWeightKilograms
        case planDays
        case planAnchorDate
        case planShiftDays
        case planExerciseIDsByDay
        case temporaryPlanByDate
        case temporaryExercisePlanByDate
        case hiddenBasePlanDates
        case hiddenPlannedExerciseIDsByDate
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cutoffMinutes = AppSettings.normalizedCutoffMinutes(
            try container.decodeIfPresent(Int.self, forKey: .cutoffMinutes) ?? 180
        )
        preferredWeightUnit = try container.decodeIfPresent(WeightUnit.self, forKey: .preferredWeightUnit) ?? .pounds
        maxWeightKilograms = try container.decodeIfPresent(Double.self, forKey: .maxWeightKilograms) ?? AppSettings.defaultMaxWeightKilograms
        planDays = AppSettings.normalizedPlanDays(
            try container.decodeIfPresent([PlanDay].self, forKey: .planDays) ?? PlanDay.defaultWeek
        )
        planAnchorDate = try container.decodeIfPresent(Date.self, forKey: .planAnchorDate) ?? .now
        planShiftDays = try container.decodeIfPresent(Int.self, forKey: .planShiftDays) ?? 0
        planExerciseIDsByDay = try container.decodeIfPresent([Int: [String]].self, forKey: .planExerciseIDsByDay) ?? [:]
        temporaryPlanByDate = try container.decodeIfPresent([String: [PlanWorkoutType]].self, forKey: .temporaryPlanByDate) ?? [:]
        temporaryExercisePlanByDate = try container.decodeIfPresent([String: [TemporaryPlannedExercise]].self, forKey: .temporaryExercisePlanByDate) ?? [:]
        hiddenBasePlanDates = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenBasePlanDates) ?? []
        hiddenPlannedExerciseIDsByDate = try container.decodeIfPresent([String: [String]].self, forKey: .hiddenPlannedExerciseIDsByDate) ?? [:]
        maxWeightKilograms = normalizedMaxWeightKilograms
    }

    func encodedForPersistence() -> AppSettings {
        var copy = self
        copy.cutoffMinutes = AppSettings.normalizedCutoffMinutes(copy.cutoffMinutes)
        copy.planDays = AppSettings.normalizedPlanDays(copy.planDays)
        copy.maxWeightKilograms = copy.normalizedMaxWeightKilograms
        return copy
    }
}
