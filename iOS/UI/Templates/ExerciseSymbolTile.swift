import SwiftUI

struct ExerciseSymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 50

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.14))
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}
