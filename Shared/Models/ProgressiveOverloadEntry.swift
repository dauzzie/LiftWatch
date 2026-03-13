import Foundation

struct ProgressiveOverloadEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let latestWeight: Double
    let previousWeight: Double
    let latestVolume: Double
    let previousVolume: Double
    let latestSessionDate: Date

    var weightDelta: Double { latestWeight - previousWeight }
    var volumeDelta: Double { latestVolume - previousVolume }
}

struct ProgressiveOverloadPoint: Identifiable, Hashable {
    let id = UUID()
    let exerciseName: String
    let symbol: String
    let workoutIndex: Int
    let sessionDate: Date
    let maxWeight: Double
    let volume: Double
}

enum ProgressiveMetric: String, CaseIterable, Identifiable {
    case maxWeight
    case volume

    var id: Self { self }

    var title: String {
        switch self {
        case .maxWeight: return "Max Weight"
        case .volume: return "Volume"
        }
    }
}
