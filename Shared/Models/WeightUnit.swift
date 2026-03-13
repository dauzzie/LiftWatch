import Foundation

enum WeightUnit: String, Codable, CaseIterable, Hashable, Identifiable {
    case pounds
    case kilograms

    var id: Self { self }

    var symbol: String {
        switch self {
        case .pounds: return "lb"
        case .kilograms: return "kg"
        }
    }

    var title: String {
        switch self {
        case .pounds: return "Pounds"
        case .kilograms: return "Kilograms"
        }
    }

    func toKilograms(_ value: Double) -> Double {
        switch self {
        case .pounds:
            return value * 0.453_592_37
        case .kilograms:
            return value
        }
    }

    func fromKilograms(_ kilograms: Double) -> Double {
        switch self {
        case .pounds:
            return kilograms / 0.453_592_37
        case .kilograms:
            return kilograms
        }
    }
}
