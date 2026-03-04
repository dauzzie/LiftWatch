import Foundation
import WatchConnectivity

@MainActor
final class WatchSyncManager: NSObject, ObservableObject {
    private enum PayloadKey {
        static let logs = "logs"
        static let syncRequest = "syncRequest"
        static let isSnapshot = "isSnapshot"
    }

    @Published private(set) var syncStatus = "Idle"

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private weak var store: ExerciseStore?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var pendingPayload: [String: Any]?

    func start(store: ExerciseStore) {
        self.store = store

        guard let session else {
            syncStatus = "WatchConnectivity unavailable"
            return
        }

        session.delegate = self
        session.activate()
    }

    func appDidBecomeActive() {
        requestPeerLogs()
        flushPendingSync()
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

    private func send(logs: [ExerciseLog], isSnapshot: Bool) {
        guard let data = try? encoder.encode(logs) else {
            syncStatus = "Sync encode failed"
            return
        }

        pendingPayload = [PayloadKey.logs: data, PayloadKey.isSnapshot: isSnapshot]
        flushPendingSync()
    }

    private func flushPendingSync() {
        guard let session, let payload = pendingPayload else { return }

        guard isConnectionReady(session) else {
            syncStatus = unavailableMessage(for: session)
            return
        }

        guard session.activationState == .activated else {
            syncStatus = "Connecting..."
            session.activate()
            return
        }

        syncStatus = "Syncing..."

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.deliverFallback(payload)
                }
            }
            pendingPayload = nil
            syncStatus = "Synced"
            return
        }

        deliverFallback(payload)
        pendingPayload = nil
        syncStatus = "Queued sync"
    }

    private func requestPeerLogs() {
        guard let session else { return }

        guard isConnectionReady(session) else {
            syncStatus = unavailableMessage(for: session)
            return
        }

        let request: [String: Any] = [PayloadKey.syncRequest: true]

        guard session.activationState == .activated else {
            syncStatus = "Connecting..."
            session.activate()
            session.transferUserInfo(request)
            return
        }

        if session.isReachable {
            syncStatus = "Requesting peer logs..."
            session.sendMessage(request) { [weak self] reply in
                Task { @MainActor in
                    self?.mergeLogs(from: reply)
                    self?.syncStatus = "Synced"
                }
            } errorHandler: { [weak self] _ in
                session.transferUserInfo(request)
                Task { @MainActor in
                    self?.syncStatus = "Queued sync request"
                }
            }
        } else {
            session.transferUserInfo(request)
            syncStatus = "Queued sync request"
        }
    }

    private func deliverFallback(_ payload: [String: Any]) {
        try? session?.updateApplicationContext(payload)
        session?.transferUserInfo(payload)
    }

    private func mergeLogs(from payload: [String: Any]) {
        guard let data = payload[PayloadKey.logs] as? Data else { return }
        guard let incoming = try? decoder.decode([ExerciseLog].self, from: data) else { return }
        let isSnapshot = payload[PayloadKey.isSnapshot] as? Bool ?? false

        if isSnapshot {
            store?.replaceAll(with: incoming)
        } else {
            store?.addAll(incoming)
        }
        syncStatus = "Synced"
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

    private func unavailableMessage(for session: WCSession) -> String {
#if os(iOS)
        if !session.isPaired {
            return "Watch not paired"
        }
        if !session.isWatchAppInstalled {
            return "Watch app not installed"
        }
        return "Watch unavailable"
#else
        if !session.isCompanionAppInstalled {
            return "iPhone app not installed"
        }
        return "iPhone unavailable"
#endif
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
                syncStatus = "Sync error: \(error.localizedDescription)"
            }
            appDidBecomeActive()
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        Task { @MainActor in
            appDidBecomeActive()
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

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            appDidBecomeActive()
        }
    }
}
