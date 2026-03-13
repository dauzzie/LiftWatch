import Foundation

struct ExerciseDefinition: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var symbol: String
    var category: ExerciseCategory
    var weightliftingCategory: WeightliftingCategory?
    var targetMuscles: [String]
    var isCustom: Bool

    init(
        id: String,
        name: String,
        symbol: String,
        category: ExerciseCategory,
        weightliftingCategory: WeightliftingCategory? = nil,
        targetMuscles: [String] = [],
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.category = category
        self.weightliftingCategory = weightliftingCategory
        self.targetMuscles = targetMuscles
        self.isCustom = isCustom
    }
}

enum BuiltinExerciseCatalog {
    private static let cachedWeightliftingByCategory: [WeightliftingCategory: [ExerciseDefinition]] = {
        Dictionary(uniqueKeysWithValues: WeightliftingCategory.allCases.map { category in
            let items = WeightliftingCatalog.presets(for: category).map { preset in
                ExerciseDefinition(
                    id: "builtin-weight-\(category.rawValue)-\(preset.name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                    name: preset.name,
                    symbol: preset.symbol,
                    category: .weightlifting,
                    weightliftingCategory: category,
                    targetMuscles: preset.targetMuscles,
                    isCustom: false
                )
            }
            return (category, items)
        })
    }()

    private static let cachedCardio: [ExerciseDefinition] = [
        ExerciseDefinition(id: "builtin-cardio-run", name: "Run", symbol: "figure.run", category: .cardio, targetMuscles: ["Cardiovascular", "Legs"], isCustom: false),
        ExerciseDefinition(id: "builtin-cardio-walk", name: "Walk", symbol: "figure.walk", category: .cardio, targetMuscles: ["Cardiovascular", "Legs"], isCustom: false),
        ExerciseDefinition(id: "builtin-cardio-cycle", name: "Cycling", symbol: "figure.outdoor.cycle", category: .cardio, targetMuscles: ["Cardiovascular", "Quads", "Glutes"], isCustom: false),
        ExerciseDefinition(id: "builtin-cardio-row", name: "Rowing", symbol: "figure.rower", category: .cardio, targetMuscles: ["Cardiovascular", "Back", "Legs"], isCustom: false),
        ExerciseDefinition(id: "builtin-cardio-hiit", name: "HIIT", symbol: "flame.fill", category: .cardio, targetMuscles: ["Cardiovascular", "Full body"], isCustom: false)
    ]

    static func weightliftingDefinitions(for category: WeightliftingCategory) -> [ExerciseDefinition] {
        cachedWeightliftingByCategory[category] ?? []
    }

    static func cardioDefinitions() -> [ExerciseDefinition] {
        cachedCardio
    }

    static var allSymbols: [String] {
        let weightSymbols = WeightliftingCategory.allCases.flatMap { weightliftingDefinitions(for: $0) }.map(\.symbol)
        let cardioSymbols = cardioDefinitions().map(\.symbol)
        return weightSymbols + cardioSymbols
    }
}
