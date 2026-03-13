import SwiftUI

extension SyncLevel {
    var tintColor: Color {
        switch self {
        case .idle: return .secondary
        case .syncing: return .orange
        case .success: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }
}
