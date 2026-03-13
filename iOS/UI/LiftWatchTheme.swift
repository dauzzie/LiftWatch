import SwiftUI

enum LiftWatchGradientStyle {
    case standard
    case main
}

enum LiftWatchTheme {
    static func backgroundGradient(for colorScheme: ColorScheme, style: LiftWatchGradientStyle = .standard) -> [Color] {
        switch style {
        case .standard:
            if colorScheme == .dark {
                return [Color(red: 0.08, green: 0.10, blue: 0.14), Color(red: 0.06, green: 0.12, blue: 0.20)]
            }
            return [Color(red: 0.95, green: 0.98, blue: 1.0), Color(red: 0.90, green: 0.95, blue: 1.0)]
        case .main:
            if colorScheme == .dark {
                return [Color(red: 0.07, green: 0.09, blue: 0.13), Color(red: 0.05, green: 0.12, blue: 0.19)]
            }
            return [Color(red: 0.93, green: 0.97, blue: 1.0), Color(red: 0.89, green: 0.93, blue: 0.99)]
        }
    }

    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.90)
    }

    static func cardStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.80)
    }
}

extension View {
    func liftWatchCardStyle(colorScheme: ColorScheme, cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                LiftWatchTheme.cardBackground(for: colorScheme),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LiftWatchTheme.cardStroke(for: colorScheme), lineWidth: 1)
            )
    }
}
