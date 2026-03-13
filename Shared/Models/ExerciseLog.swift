import Foundation

enum ExerciseCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case weightlifting
    case cardio

    var id: Self { self }
}

struct ExerciseLog: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var symbol: String
    var category: ExerciseCategory
    var weightliftingCategory: WeightliftingCategory?
    var reps: Int?
    var weight: Double?
    var weightUnit: WeightUnit?
    var sets: Int?
    var targetMuscles: [String]?
    var minutes: Int?
    var pace: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        category: ExerciseCategory,
        weightliftingCategory: WeightliftingCategory? = nil,
        reps: Int? = nil,
        weight: Double? = nil,
        weightUnit: WeightUnit? = .pounds,
        sets: Int? = nil,
        targetMuscles: [String]? = nil,
        minutes: Int? = nil,
        pace: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.category = category
        self.weightliftingCategory = weightliftingCategory
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.sets = sets
        self.targetMuscles = targetMuscles
        self.minutes = minutes
        self.pace = pace
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, category, weightliftingCategory, reps, weight, weightUnit, sets, targetMuscles, minutes, pace, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        category = try container.decodeIfPresent(ExerciseCategory.self, forKey: .category) ?? .weightlifting
        weightliftingCategory = try container.decodeIfPresent(WeightliftingCategory.self, forKey: .weightliftingCategory)
        reps = try container.decodeIfPresent(Int.self, forKey: .reps)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        weightUnit = try container.decodeIfPresent(WeightUnit.self, forKey: .weightUnit) ?? .pounds
        sets = try container.decodeIfPresent(Int.self, forKey: .sets)
        targetMuscles = try container.decodeIfPresent([String].self, forKey: .targetMuscles)
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        pace = try container.decodeIfPresent(String.self, forKey: .pace)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    var resolvedWeightUnit: WeightUnit {
        weightUnit ?? .pounds
    }

    var weightKilograms: Double? {
        guard let weight else { return nil }
        return resolvedWeightUnit.toKilograms(weight)
    }

    func weight(in unit: WeightUnit) -> Double? {
        guard let weightKilograms else { return nil }
        return unit.fromKilograms(weightKilograms)
    }
}
