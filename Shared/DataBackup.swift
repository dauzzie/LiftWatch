import Foundation

struct LiftWatchBackupEnvelope: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var payload: LiftWatchBackupPayload

    init(
        schemaVersion: Int = LiftWatchBackupEnvelope.currentSchemaVersion,
        exportedAt: Date = .now,
        payload: LiftWatchBackupPayload
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.payload = payload
    }
}

struct LiftWatchBackupPayload: Codable {
    var logs: [ExerciseLog]
    var sessions: [WorkoutSession]
    var customExercises: [ExerciseDefinition]
    var settings: AppSettings
    var lastSessionStart: Date
}

enum BackupError: LocalizedError {
    case encodeFailed
    case invalidFile
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "Could not encode backup data."
        case .invalidFile:
            return "Selected file is not a valid LiftWatch backup."
        case .unsupportedSchema(let version):
            return "Backup schema version \(version) is not supported by this app build."
        }
    }
}
