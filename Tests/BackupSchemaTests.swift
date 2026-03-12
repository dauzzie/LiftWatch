import XCTest
@testable import LiftWatchIOSç

final class BackupSchemaTests: XCTestCase {
    func testBackupEnvelopeDefaultSchemaVersion() {
        let payload = LiftWatchBackupPayload(
            logs: [],
            sessions: [],
            customExercises: [],
            settings: AppSettings(),
            lastSessionStart: .now
        )

        let envelope = LiftWatchBackupEnvelope(payload: payload)
        XCTAssertEqual(envelope.schemaVersion, LiftWatchBackupEnvelope.currentSchemaVersion)
    }

    @MainActor
    func testImportRejectsFutureSchemaVersion() throws {
        let payload = LiftWatchBackupPayload(
            logs: [],
            sessions: [],
            customExercises: [],
            settings: AppSettings(),
            lastSessionStart: .now
        )

        let envelope = LiftWatchBackupEnvelope(
            schemaVersion: LiftWatchBackupEnvelope.currentSchemaVersion + 10,
            payload: payload
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        let store = ExerciseStore()

        XCTAssertThrowsError(try store.importBackupData(data)) { error in
            guard case BackupError.unsupportedSchema = error else {
                XCTFail("Expected unsupportedSchema error, got \(error)")
                return
            }
        }
    }
}
