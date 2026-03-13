import CloudKit
import Foundation

@MainActor
final class CloudSyncManager: ObservableObject {
    private enum Keys {
        static let recordType = "LiftWatchState"
        static let recordName = "primary"
        static let payloadAsset = "payloadAsset"
        static let updatedAt = "updatedAt"
        static let sourceDevice = "sourceDevice"
        static let schemaVersion = "schemaVersion"
    }

    private struct RemoteSnapshot {
        let data: Data
        let updatedAt: Date
    }

    @Published private(set) var syncStatus = "Cloud idle"
    @Published private(set) var syncDetail = "Waiting for first sync."
    @Published private(set) var syncLevel: SyncLevel = .idle
    @Published private(set) var lastSuccessfulSyncAt: Date?

    private lazy var container: CKContainer = CKContainer.default()
    private let recordID = CKRecord.ID(recordName: Keys.recordName)
    private let deviceIdentifier = ProcessInfo.processInfo.hostName
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    private weak var store: ExerciseStore?
    private var uploadTask: Task<Void, Never>?
    private var isSyncing = false
    private var isApplyingRemote = false
    private var lastRemoteUpdatedAt: Date?
    private var lastLocalUploadAt: Date?

    func start(store: ExerciseStore) {
        self.store = store
        store.onStateDidPersist = { [weak self] in
            Task { @MainActor in
                self?.enqueueUpload()
            }
        }

        guard !isRunningTests else {
            setStatus(
                "Cloud disabled in tests",
                detail: "Cloud sync is skipped while unit tests are running.",
                level: .idle
            )
            return
        }

        setStatus("Cloud connecting...", detail: "Checking iCloud availability.", level: .syncing)
        Task {
            await syncNow(reason: "startup")
        }
    }

    func appDidBecomeActive() {
        guard !isRunningTests else { return }
        Task {
            await syncNow(reason: "foreground")
        }
    }

    func manualSync() {
        guard !isRunningTests else { return }
        Task {
            await syncNow(reason: "manual")
        }
    }

    private func enqueueUpload() {
        guard !isApplyingRemote else { return }

        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            try? await self?.uploadIfNeeded(reason: "local changes")
        }
    }

    private func syncNow(reason: String) async {
        guard !isSyncing else { return }
        guard let store else { return }

        isSyncing = true
        defer { isSyncing = false }

        setStatus("Cloud syncing...", detail: "Sync reason: \(reason).", level: .syncing)

        guard await ensureAccountAvailable() else { return }

        do {
            let remote = try await fetchRemoteSnapshot()

            if let remote, shouldApplyRemote(remoteUpdatedAt: remote.updatedAt, localUpdatedAt: store.lastMutationAt) {
                isApplyingRemote = true
                defer { isApplyingRemote = false }

                try store.importBackupData(remote.data)
                lastRemoteUpdatedAt = remote.updatedAt
                lastSuccessfulSyncAt = .now
                setStatus("Cloud downloaded", detail: "Fetched newer data from iCloud.", level: .success)
                return
            }

            try await uploadIfNeeded(reason: reason, remoteUpdatedAt: remote?.updatedAt)
        } catch {
            handleCloudError(error, context: "Cloud sync failed")
        }
    }

    private func uploadIfNeeded(reason: String, remoteUpdatedAt: Date? = nil) async throws {
        guard let store else { return }

        let localUpdatedAt = store.lastMutationAt
        let knownRemoteUpdatedAt = remoteUpdatedAt ?? lastRemoteUpdatedAt

        if let remoteAt = knownRemoteUpdatedAt, remoteAt > localUpdatedAt.addingTimeInterval(1) {
            setStatus("Cloud up to date", detail: "Remote data is newer; waiting for pull.", level: .idle)
            return
        }

        if let uploadedAt = lastLocalUploadAt, localUpdatedAt <= uploadedAt {
            setStatus("Cloud up to date", detail: "No new local changes to upload.", level: .idle)
            return
        }

        let data = try store.exportBackupData()
        try await saveRemoteSnapshot(data: data, updatedAt: localUpdatedAt)

        lastLocalUploadAt = localUpdatedAt
        lastRemoteUpdatedAt = localUpdatedAt
        lastSuccessfulSyncAt = .now
        setStatus("Cloud uploaded", detail: "Uploaded latest local data.", level: .success)
        _ = reason
    }

    private func shouldApplyRemote(remoteUpdatedAt: Date, localUpdatedAt: Date) -> Bool {
        remoteUpdatedAt > localUpdatedAt.addingTimeInterval(1)
    }

    private func ensureAccountAvailable() async -> Bool {
        do {
            let status = try await accountStatus()
            switch status {
            case .available:
                return true
            case .noAccount:
                setStatus("iCloud unavailable", detail: "Sign in to iCloud to enable cloud sync.", level: .warning)
                return false
            case .restricted:
                setStatus("iCloud restricted", detail: "This device cannot use iCloud account services.", level: .warning)
                return false
            case .couldNotDetermine:
                setStatus("iCloud unknown", detail: "Could not determine account status.", level: .warning)
                return false
            case .temporarilyUnavailable:
                setStatus("iCloud temporary issue", detail: "Try again shortly.", level: .warning)
                return false
            @unknown default:
                setStatus("iCloud unavailable", detail: "Unknown account status.", level: .warning)
                return false
            }
        } catch {
            handleCloudError(error, context: "Could not check iCloud account")
            return false
        }
    }

    private func fetchRemoteSnapshot() async throws -> RemoteSnapshot? {
        guard let record = try await fetchRecord() else { return nil }
        guard let updatedAt = record[Keys.updatedAt] as? Date else { return nil }

        if let asset = record[Keys.payloadAsset] as? CKAsset,
           let fileURL = asset.fileURL {
            let data = try Data(contentsOf: fileURL)
            return RemoteSnapshot(data: data, updatedAt: updatedAt)
        }

        return nil
    }

    private func saveRemoteSnapshot(data: Data, updatedAt: Date) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("liftwatch-cloud-\(UUID().uuidString).json")
        try data.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let record = (try await fetchRecord()) ?? CKRecord(recordType: Keys.recordType, recordID: recordID)
        record[Keys.payloadAsset] = CKAsset(fileURL: tempURL)
        record[Keys.updatedAt] = updatedAt as NSDate
        record[Keys.sourceDevice] = deviceIdentifier as NSString
        record[Keys.schemaVersion] = LiftWatchBackupEnvelope.currentSchemaVersion as NSNumber

        _ = try await save(record: record)
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func fetchRecord() async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            container.privateCloudDatabase.fetch(withRecordID: recordID) { record, error in
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    continuation.resume(returning: nil)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: record)
            }
        }
    }

    private func save(record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            container.privateCloudDatabase.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: saved ?? record)
            }
        }
    }

    private func handleCloudError(_ error: Error, context: String) {
        guard let ckError = error as? CKError else {
            setStatus(context, detail: error.localizedDescription, level: .warning)
            return
        }

        switch ckError.code {
        case .notAuthenticated:
            setStatus("iCloud not signed in", detail: "Sign in to iCloud to sync backups.", level: .warning)
        case .permissionFailure:
            setStatus(
                "Cloud permission issue",
                detail: "Enable iCloud + CloudKit capability for LiftWatch in Xcode signing settings.",
                level: .error
            )
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            setStatus("Cloud network issue", detail: ckError.localizedDescription, level: .warning)
        default:
            setStatus(context, detail: ckError.localizedDescription, level: .warning)
        }
    }

    private func setStatus(_ status: String, detail: String, level: SyncLevel) {
        syncStatus = status
        syncDetail = detail
        syncLevel = level
    }
}
