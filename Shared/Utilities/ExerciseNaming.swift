import Foundation

enum ExerciseNaming {
    static func displayName(name: String, symbol: String, category: ExerciseCategory) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackName(from: symbol) }

        if category == .cardio, looksLikeSymbolToken(trimmed) {
            if let matched = BuiltinExerciseCatalog.cardioDefinitions().first(where: { $0.symbol == symbol }) {
                return matched.name
            }
            return fallbackName(from: trimmed)
        }

        return trimmed
    }

    private static func looksLikeSymbolToken(_ value: String) -> Bool {
        value.contains(".") || value.contains("_")
    }

    private static func fallbackName(from token: String) -> String {
        token
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
