import Foundation

struct LiftPreset: Identifiable, Hashable {
    let name: String
    let symbol: String
    let targetMuscles: [String]

    var id: String { name }
}

enum WeightliftingCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case push
    case pull
    case legs
    case abs

    var id: Self { self }

    var title: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .abs: return "Abs"
        }
    }

    var symbol: String {
        switch self {
        case .push: return "arrow.up.circle.fill"
        case .pull: return "arrow.down.circle.fill"
        case .legs: return "figure.walk.circle.fill"
        case .abs: return "figure.core.training"
        }
    }
}

enum WeightliftingCatalog {
    static func presets(for category: WeightliftingCategory) -> [LiftPreset] {
        switch category {
        case .push:
            return [
                LiftPreset(name: "Incline press", symbol: "arrow.up.forward.circle.fill", targetMuscles: ["Upper chest", "Front delts", "Triceps"]),
                LiftPreset(name: "Decline press", symbol: "arrow.down.forward.circle.fill", targetMuscles: ["Lower chest", "Triceps"]),
                LiftPreset(name: "Chest press", symbol: "figure.strengthtraining.traditional", targetMuscles: ["Chest", "Front delts", "Triceps"]),
                LiftPreset(name: "Lat pushdown", symbol: "arrow.down.to.line", targetMuscles: ["Lats", "Triceps"]),
                LiftPreset(name: "Chest fly", symbol: "bird.fill", targetMuscles: ["Chest", "Front delts"]),
                LiftPreset(name: "Lateral raise", symbol: "arrow.left.and.right.circle.fill", targetMuscles: ["Lateral delts", "Upper traps"]),
                LiftPreset(name: "Overhead press", symbol: "arrow.up.and.down.circle.fill", targetMuscles: ["Shoulders", "Triceps", "Upper chest"]),
                LiftPreset(name: "Shoulder press", symbol: "figure.arms.open", targetMuscles: ["Delts", "Triceps"]),
                LiftPreset(name: "Pec fly", symbol: "sparkles.rectangle.stack", targetMuscles: ["Chest", "Front delts"])
            ]
        case .pull:
            return [
                LiftPreset(name: "Lat pulldown", symbol: "arrow.down.circle.fill", targetMuscles: ["Lats", "Biceps", "Mid back"]),
                LiftPreset(name: "Bicep curl", symbol: "dumbbell.fill", targetMuscles: ["Biceps", "Forearms"]),
                LiftPreset(name: "Hammer curl", symbol: "hammer.fill", targetMuscles: ["Brachialis", "Biceps", "Forearms"]),
                LiftPreset(name: "Bicep pull", symbol: "arrowshape.left.arrowshape.right.fill", targetMuscles: ["Biceps", "Upper back"]),
                LiftPreset(name: "Low row", symbol: "arrow.down.right.circle.fill", targetMuscles: ["Mid back", "Lats", "Biceps"]),
                LiftPreset(name: "High row", symbol: "arrow.up.right.circle.fill", targetMuscles: ["Rear delts", "Upper back", "Traps"]),
                LiftPreset(name: "Lateral row", symbol: "arrow.left.and.right.square.fill", targetMuscles: ["Lats", "Rhomboids", "Rear delts"]),
                LiftPreset(name: "Rear delt", symbol: "figure.mixed.cardio", targetMuscles: ["Rear delts", "Upper back"])
            ]
        case .legs:
            return [
                LiftPreset(name: "Hamstring curl", symbol: "figure.walk", targetMuscles: ["Hamstrings", "Calves"]),
                LiftPreset(name: "Squat", symbol: "figure.strengthtraining.functional", targetMuscles: ["Quads", "Glutes", "Core"]),
                LiftPreset(name: "Leg curl", symbol: "figure.run", targetMuscles: ["Hamstrings", "Glutes"]),
                LiftPreset(name: "Leg extension", symbol: "figure.step.training", targetMuscles: ["Quads"]),
                LiftPreset(name: "Hip adductor", symbol: "figure.flexibility", targetMuscles: ["Inner thighs", "Glutes"]),
                LiftPreset(name: "Glutes master", symbol: "figure.cooldown", targetMuscles: ["Glutes", "Hamstrings"]),
                LiftPreset(name: "Kegel", symbol: "circle.hexagongrid.fill", targetMuscles: ["Pelvic floor", "Core"]),
                LiftPreset(name: "Lower back", symbol: "figure.core.training", targetMuscles: ["Lower back", "Spinal erectors"]),
                LiftPreset(name: "Deadlift", symbol: "bolt.heart.fill", targetMuscles: ["Hamstrings", "Glutes", "Lower back"]),
                LiftPreset(name: "Lunges", symbol: "figure.mind.and.body", targetMuscles: ["Quads", "Glutes", "Hamstrings"])
            ]
        case .abs:
            return [
                LiftPreset(name: "Captain's chair", symbol: "chair.fill", targetMuscles: ["Lower abs", "Hip flexors"]),
                LiftPreset(name: "Oblique pulls", symbol: "arrow.triangle.pull", targetMuscles: ["Obliques", "Core"])
            ]
        }
    }

    static func preset(named name: String, in category: WeightliftingCategory) -> LiftPreset? {
        presets(for: category).first(where: { $0.name == name })
    }

    static var allPresets: [LiftPreset] {
        WeightliftingCategory.allCases.flatMap { presets(for: $0) }
    }
}
