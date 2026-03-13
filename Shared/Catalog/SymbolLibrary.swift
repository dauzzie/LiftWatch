import Foundation

enum SymbolLibrary {
    static let defaultCardioSymbols: [String] = [
        "figure.run",
        "figure.walk",
        "figure.outdoor.cycle",
        "heart.fill",
        "flame.fill"
    ]

    // Fallback/unused symbols intended for custom exercises.
    static let extendedSymbols: [String] = [
        "hare.fill", "tortoise.fill", "bolt.fill", "drop.fill", "leaf.fill", "snowflake",
        "figure.yoga", "figure.hiking", "figure.badminton", "figure.climbing", "figure.soccer",
        "figure.basketball", "figure.tennis", "figure.volleyball", "figure.golf", "figure.boxing",
        "figure.elliptical", "figure.roll", "figure.strengthtraining.functional", "figure.highintensity.intervaltraining",
        "heart.circle.fill", "star.fill", "sun.max.fill", "moon.fill", "brain.head.profile",
        "lungs.fill", "waveform.path.ecg", "timer", "clock.arrow.circlepath", "shield.lefthalf.filled",
        "target", "scope", "hexagon.fill", "triangle.fill", "capsule.fill", "barbell",
        "dumbbell", "figure.core.training", "figure.play", "figure.mixed.cardio", "figure.cooldown"
    ]

    static func unusedSymbols(existing: [String]) -> [String] {
        let used = Set(existing)
        return extendedSymbols.filter { !used.contains($0) }
    }
}
