import SwiftUI

extension View {
    func liftWatchPanel(_ material: Material = .thinMaterial, cornerRadius: CGFloat = 14) -> some View {
        background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
