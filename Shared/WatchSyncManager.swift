import Foundation
import WatchConnectivity

enum SyncLevel {
    case idle
    case syncing
    case success
    case warning
    case error
}

@MainActor
final class WatchSyncManager: NSObject, ObservableObject {
    private enum PayloadKey {
        static let logs = "logs"
        static let syncRequest = "syncRequest"
        static let isSnapshot = "isSnapshot"
    }

    @Published private(set) var syncStatus = "Idle"
    @Published private(set) var syncDetail = ""
    @Published private(set) var syncLevel: SyncLevel = .idle
    @Published private(set) var lastSuccessfulSyncAt: Date?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private weak var store: ExerciseStore?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var pendingPayload: [String: Any]?
    private var isRequestInFlight = false
    private var lastActivationSyncAttemptAt: Date?

    func start(store: ExerciseStore) {
        self.store = store

        guard let session else {
            setStatus("WatchConnectivity unavailable", detail: "Device does not support watch sync.", level: .warning)
            return
        }

        session.delegate = self
        session.activate()
        setStatus("Connecting...", detail: "Initializing watch session.", level: .syncing)
    }

    func appDidBecomeActive() {
        guard shouldAttemptForegroundSync else { return }
        lastActivationSyncAttemptAt = .now
        syncBidirectional()
    }

    func send(log: ExerciseLog) {
        send(logs: [log], isSnapshot: false)
    }

    func sendAll() {
        guard let store else { return }
        send(logs: store.logs, isSnapshot: true)
    }

    func syncBidirectional() {
        sendAll()
        requestPeerLogs()
    }

    private var shouldAttemptForegroundSync: Bool {
        guard let last = lastActivationSyncAttemptAt else { return true }
        return Date().timeIntervalSince(last) > 2
    }

    private func send(logs: [ExerciseLog], isSnapshot: Bool) {
        guard let data = try? encoder.encode(logs) else {
            setStatus("Sync encode failed", detail: "Could not encode logs.", level: .error)
            return
        }

        pendingPayload = [PayloadKey.logs: data, PayloadKey.isSnapshot: isSnapshot]
        flushPendingSync()
    }

    private func flushPendingSync() {
        guard let session, let payload = pendingPayload else { return }

        guard isConnectionReady(session) else {
            setStatus(unavailableTitle(for: session), detail: unavailableDetail(for: session), level: .warning)
            return
        }

        guard session.activationState == .activated else {
            setStatus("Connecting...", detail: "Waiting for watch session activation.", level: .syncing)
            session.activate()
            return
        }

        setStatus("Syncing...", detail: "Sending local changes.", level: .syncing)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.deliverFallback(payload)
                    self?.setStatus("Sync queued", detail: error.localizedDescription, level: .warning)
                }
            }
            pendingPayload = nil
            lastSuccessfulSyncAt = .now
            setStatus("Synced", detail: "Local changes delivered.", level: .success)
            return
        }

        deliverFallback(payload)
        pendingPayload = nil
        setStatus("Sync queued", detail: "Watch currently unreachable. Will deliver in background.", level: .warning)
    }

    private func requestPeerLogs() {
        guard let session else { return }
        guard !isRequestInFlight else { return }

        guard isConnectionReady(session) else {
            setStatus(unavailableTitle(for: session), detail: unavailableDetail(for: session), level: .warning)
            return
        }

        let request: [String: Any] = [PayloadKey.syncRequest: true]

        guard session.activationState == .activated else {
            setStatus("Connecting...", detail: "Waiting for watch session activation.", level: .syncing)
            session.activate()
            session.transferUserInfo(request)
            return
        }

        isRequestInFlight = true

        if session.isReachable {
            setStatus("Requesting peer logs...", detail: "Fetching latest logs from paired device.", level: .syncing)
            session.sendMessage(request) { [weak self] reply in
                Task { @MainActor in
                    self?.isRequestInFlight = false
                    self?.mergeLogs(from: reply)
                }
            } errorHandler: { [weak self] error in
                session.transferUserInfo(request)
                Task { @MainActor in
                    self?.isRequestInFlight = false
                    self?.setStatus("Sync request queued", detail: error.localizedDescription, level: .warning)
                }
            }
        } else {
            session.transferUserInfo(request)
            isRequestInFlight = false
            setStatus("Sync request queued", detail: "Device unreachable, queued via background transfer.", level: .warning)
        }
    }

    private func deliverFallback(_ payload: [String: Any]) {
        guard let session else { return }

        do {
            try session.updateApplicationContext(payload)
        } catch {
            setStatus("Context sync failed", detail: error.localizedDescription, level: .warning)
        }

        session.transferUserInfo(payload)
    }

    private func mergeLogs(from payload: [String: Any]) {
        guard let data = payload[PayloadKey.logs] as? Data else { return }
        guard let incoming = try? decoder.decode([ExerciseLog].self, from: data) else {
            setStatus("Sync decode failed", detail: "Received invalid payload.", level: .error)
            return
        }
        let isSnapshot = payload[PayloadKey.isSnapshot] as? Bool ?? false

        if isSnapshot {
            store?.replaceAll(with: incoming)
        } else {
            store?.addAll(incoming)
        }

        lastSuccessfulSyncAt = .now
        setStatus("Synced", detail: "Latest logs merged.", level: .success)
    }

    private func payloadForCurrentLogs() -> [String: Any]? {
        guard let store else { return nil }
        guard let data = try? encoder.encode(store.logs) else { return nil }
        return [PayloadKey.logs: data, PayloadKey.isSnapshot: true]
    }

    private func handleSyncRequestIfNeeded(from payload: [String: Any]) -> Bool {
        guard payload[PayloadKey.syncRequest] as? Bool == true else { return false }
        guard let store else { return true }
        send(logs: store.logs, isSnapshot: true)
        return true
    }

    private func isConnectionReady(_ session: WCSession) -> Bool {
#if os(iOS)
        return session.isPaired && session.isWatchAppInstalled
#else
        return session.isCompanionAppInstalled
#endif
    }

    private func unavailableTitle(for session: WCSession) -> String {
#if os(iOS)
        if !session.isPaired { return "Watch not paired" }
        if !session.isWatchAppInstalled { return "Watch app not installed" }
        return "Watch unavailable"
#else
        if !session.isCompanionAppInstalled { return "iPhone app not installed" }
        return "iPhone unavailable"
#endif
    }

    private func unavailableDetail(for session: WCSession) -> String {
#if os(iOS)
        if !session.isPaired { return "Pair an Apple Watch with this iPhone to enable sync." }
        if !session.isWatchAppInstalled { return "Install LiftWatch on the paired Watch." }
        return "Open both iPhone and Watch apps at least once."
#else
        if !session.isCompanionAppInstalled { return "Install LiftWatch on paired iPhone." }
        return "Open the iPhone app to re-establish sync."
#endif
    }

    private func setStatus(_ status: String, detail: String, level: SyncLevel) {
        syncStatus = status
        syncDetail = detail
        syncLevel = level
    }
}

extension WatchSyncManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                setStatus("Sync error", detail: error.localizedDescription, level: .error)
            } else {
                setStatus("Connected", detail: "Watch session activated.", level: .success)
            }
            appDidBecomeActive()
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            setStatus("Sync inactive", detail: "Session became inactive.", level: .warning)
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        Task { @MainActor in
            setStatus("Reconnecting...", detail: "Watch session deactivated, reactivating.", level: .syncing)
            appDidBecomeActive()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            if isConnectionReady(session) {
                setStatus("Watch connected", detail: "Sync ready.", level: .success)
                appDidBecomeActive()
            } else {
                setStatus(unavailableTitle(for: session), detail: unavailableDetail(for: session), level: .warning)
            }
        }
    }
#endif

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if handleSyncRequestIfNeeded(from: message) {
                return
            }
            mergeLogs(from: message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            if message[PayloadKey.syncRequest] as? Bool == true {
                replyHandler(payloadForCurrentLogs() ?? [:])
                return
            }
            mergeLogs(from: message)
            replyHandler(payloadForCurrentLogs() ?? [:])
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            if handleSyncRequestIfNeeded(from: applicationContext) {
                return
            }
            mergeLogs(from: applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            if handleSyncRequestIfNeeded(from: userInfo) {
                return
            }
            mergeLogs(from: userInfo)
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        Task { @MainActor in
            if let error {
                setStatus("Background sync failed", detail: error.localizedDescription, level: .warning)
            } else {
                lastSuccessfulSyncAt = .now
                setStatus("Synced", detail: "Background transfer completed.", level: .success)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable {
                setStatus("Reachable", detail: "Live sync channel available.", level: .success)
            } else {
                setStatus("Unreachable", detail: "Falling back to background sync.", level: .warning)
            }
            flushPendingSync()
        }
    }
}
