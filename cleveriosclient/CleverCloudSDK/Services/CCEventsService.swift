import Foundation
import Combine

// MARK: - Connection State
public enum CCConnectionState: Equatable, Sendable {
    case disconnected
    case polling
    case failed(String)
}

// MARK: - Event Models
//
// Concrete, `Sendable` value crossing the Combine boundary into AppState. The raw `[String: Any]`
// JSON payload is parsed on the producer side (`handleIncomingText`) into the only fields any
// consumer reads — `appId` and `state` — so no non-Sendable dictionary travels across threads.
public struct CCPlatformEvent: Sendable {
    public let id: String
    public let timestamp: Date
    public let type: String
    /// Application this event refers to (from the deployment payload's `id`/`appId`).
    public let appId: String?
    /// Deployment state, e.g. WIP / OK / FAIL / CANCELLED.
    public let state: String?

    public init(id: String, timestamp: Date, type: String, appId: String?, state: String?) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.appId = appId
        self.state = state
    }
}

// MARK: - Events Service (WebSocket)
//
// Live event stream from Clever Cloud over WebSocket. Replaces the previous polling stub.
// Protocol (reverse-engineered from clever-tools' @clevercloud/client `EventsStream`):
//   - Connect to `wss://api.clever-cloud.com/v2/events/event-socket`
//   - On `open`, send `{"message_type":"oauth","authorization":"<OAuth header>"}` where the header
//     is computed for a hypothetical GET on `https://api.clever-cloud.com/v2/events/`
//   - Server emits JSON messages:
//       * `{"message_type":"socket_ready"}` — handshake done; ignore
//       * `{"type":"heartbeat","heartbeat_delay_ms":N}` — reply with
//         `{"type":"heartbeat","heartbeat_msg":"pong"}`
//       * `{"type":"error","id":2001,...}` — auth failed
//       * `{"event":"DEPLOYMENT_ACTION_BEGIN|_END",...,"data":"<JSON-stringified payload>"}` — real
//         events. The `data` field is itself a JSON string and must be parsed.
//   - On socket close/error, reconnect with backoff.
public final class CCEventsService: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Properties
    private let apiV2BaseURL: String  // e.g. https://api.clever-cloud.com/v2
    private let oauthSigner: CCOAuthSigner
    private let urlSession: URLSession

    // Connection state
    @Published public private(set) var connectionState: CCConnectionState = .disconnected
    private let connectionStateSubject = CurrentValueSubject<CCConnectionState, Never>(.disconnected)
    public var connectionStatePublisher: AnyPublisher<CCConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }

    // Event publishing
    private let eventSubject = PassthroughSubject<CCPlatformEvent, Never>()
    public var eventPublisher: AnyPublisher<CCPlatformEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    // WebSocket state — all mutated/read ONLY on `serialQueue` (URLSession callbacks are routed
    // there via the session's delegate queue, see init), which is what makes `@unchecked Sendable` honest.
    private var webSocketTask: URLSessionWebSocketTask?
    private var isUserConnected = false
    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 30.0
    /// Pending reconnect, scheduled via `serialQueue.asyncAfter` (a DispatchQueue has no run loop, so
    /// `Timer.scheduledTimer` would silently never fire here). Cancellable on disconnect.
    private var reconnectWorkItem: DispatchWorkItem?

    // Kept for compatibility with callers — the WebSocket doesn't poll, but if it becomes a fallback
    // we may want a periodic ping. For now this is informational only.
    private var pollingInterval: TimeInterval = 15.0

    private let serialQueue: DispatchQueue

    // MARK: - Initialization
    public init(baseURL: String, oauthSigner: CCOAuthSigner) {
        self.apiV2BaseURL = baseURL
        self.oauthSigner = oauthSigner

        let queue = DispatchQueue(label: "com.fredalix.cciosclient.events", qos: .userInitiated)
        self.serialQueue = queue

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Deliver all URLSession completion handlers (send/receive) on `serialQueue`, the same queue
        // connect()/disconnect() run on — so every access to the mutable WebSocket state is serialized.
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: delegateQueue)

        super.init()
        debugLog("ℹ️ ✅ CCEventsService initialized [endpoint=\(eventSocketURL()?.absoluteString ?? apiV2BaseURL)]")
    }

    // MARK: - Public API (preserved for AppState)

    /// Connect to the event WebSocket. Idempotent.
    public func connect() {
        serialQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isUserConnected else {
                debugLog("ℹ️ ⚠️ Events already connected, ignoring connect()")
                return
            }
            self.isUserConnected = true
            self.openSocket()
        }
    }

    /// Disconnect and cancel any pending reconnect. Idempotent.
    public func disconnect() {
        serialQueue.async { [weak self] in
            guard let self else { return }
            guard self.isUserConnected else {
                debugLog("ℹ️ ⚠️ Events already disconnected, ignoring disconnect()")
                return
            }
            self.isUserConnected = false
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.reconnectAttempt = 0
            self.closeSocket(reason: "user disconnect")
            self.updateConnectionState(.disconnected)
        }
    }

    /// Kept for source-compat. The WebSocket is push-based; this no-ops other than logging.
    public func setPollingInterval(_ interval: TimeInterval) {
        guard interval >= 5.0 else {
            debugLog("ℹ️ ⚠️ pollingInterval clamp: \(interval)s rejected, min 5s")
            return
        }
        pollingInterval = interval
        debugLog("ℹ️ ⚙️ pollingInterval set to \(interval)s (informational; WebSocket is push-based)")
    }

    // MARK: - WebSocket lifecycle

    private func eventSocketURL() -> URL? {
        // baseURL is https://api.clever-cloud.com/v2 — swap the scheme to wss and append the path.
        guard var components = URLComponents(string: apiV2BaseURL) else { return nil }
        components.scheme = "wss"
        components.path = (components.path as NSString).appendingPathComponent("events/event-socket")
        return components.url
    }

    private func authMessageJSON() -> String? {
        // Per the clever-tools protocol, the OAuth header used for the WS auth is computed against
        // GET https://api.clever-cloud.com/v2/events/ — note the trailing slash.
        guard let baseURL = URL(string: apiV2BaseURL),
              let signedURL = URL(string: baseURL.absoluteString + "/events/") else {
            return nil
        }
        var request = URLRequest(url: signedURL)
        request.httpMethod = "GET"
        do {
            let signed = try oauthSigner.signRequest(request)
            guard let authHeader = signed.value(forHTTPHeaderField: "Authorization") else {
                return nil
            }
            let payload: [String: String] = [
                "message_type": "oauth",
                "authorization": authHeader,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            return String(data: data, encoding: .utf8)
        } catch {
            debugLog("❌ Events auth signing failed: \(error)")
            return nil
        }
    }

    private func openSocket() {
        closeSocket(reason: "reopen")

        guard let authMessage = authMessageJSON() else {
            debugLog("❌ Cannot open events WS — auth message unavailable")
            updateConnectionState(.failed("authentication failed"))
            scheduleReconnect()
            return
        }

        guard let url = eventSocketURL() else {
            debugLog("❌ Cannot open events WS — invalid socket URL from base \(apiV2BaseURL)")
            updateConnectionState(.failed("invalid socket URL"))
            scheduleReconnect()
            return
        }
        debugLog("ℹ️ 🔌 Opening events WebSocket: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let task = urlSession.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        // Send auth payload immediately. The server will not push events until it sees a valid oauth
        // message; if signing fails on the server side we'll see a `type=error id=2001` reply.
        task.send(.string(authMessage)) { [weak self] error in
            if let error {
                debugLog("❌ Events WS auth send failed: \(error)")
                self?.handleSocketFailure(error)
            }
        }

        receiveLoop()
    }

    private func closeSocket(reason: String) {
        guard let task = webSocketTask else { return }
        debugLog("ℹ️ 🧹 Closing events WS (\(reason))")
        task.cancel(with: .goingAway, reason: reason.data(using: .utf8))
        webSocketTask = nil
    }

    private func receiveLoop() {
        guard let task = webSocketTask else { return }
        task.receive { [weak self, weak task] result in
            guard let self else { return }
            // If the task was replaced/cancelled, drop this stale callback.
            guard task === self.webSocketTask else { return }

            switch result {
            case .failure(let error):
                self.handleSocketFailure(error)

            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingText(text)
                    } else {
                        debugLog("ℹ️ ⚠️ Events WS received binary frame, ignored (\(data.count) bytes)")
                    }
                @unknown default:
                    debugLog("ℹ️ ⚠️ Events WS unknown message type")
                }
                self.receiveLoop()
            }
        }
    }

    // MARK: - Message handling

    private func handleIncomingText(_ text: String) {
        guard let textData = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: textData) as? [String: Any] else {
            debugLog("ℹ️ ⚠️ Events WS unparseable frame: \(text.prefix(120))")
            return
        }

        // socket_ready: connection acknowledged → mark as live.
        if let messageType = parsed["message_type"] as? String, messageType == "socket_ready" {
            debugLog("ℹ️ ✅ Events WS handshake complete (socket_ready)")
            reconnectAttempt = 0
            updateConnectionState(.polling)
            return
        }

        // Heartbeat: reply pong.
        if let kind = parsed["type"] as? String, kind == "heartbeat" {
            sendPong()
            return
        }

        // Auth error: 2001 means the OAuth message was rejected.
        if let kind = parsed["type"] as? String,
           kind == "error",
           (parsed["id"] as? Int) == 2001 {
            debugLog("❌ Events WS auth rejected by server (id=2001)")
            updateConnectionState(.failed("authentication failed"))
            return
        }

        // Real event: shape `{event:"DEPLOYMENT_ACTION_BEGIN|_END", date:"...", data:"<JSON string>"}`.
        // The `data` field is itself JSON-stringified.
        guard let eventName = parsed["event"] as? String else {
            return
        }
        var payload: [String: Any] = [:]
        if let dataString = parsed["data"] as? String,
           let dataBytes = dataString.data(using: .utf8),
           let parsedData = try? JSONSerialization.jsonObject(with: dataBytes) as? [String: Any] {
            payload = parsedData
        } else if let inlineData = parsed["data"] as? [String: Any] {
            // Some events may already deliver the payload as a JSON object — be tolerant.
            payload = inlineData
        }

        let timestamp: Date = {
            if let iso = parsed["date"] as? String,
               let d = ISO8601DateFormatter().date(from: iso) {
                return d
            }
            return Date()
        }()

        let id = (payload["uuid"] as? String)
            ?? (parsed["id"] as? String)
            ?? UUID().uuidString

        // The deployment payload's `id` is the application id (matches @clevercloud/client's
        // `_matchesAppId` which compares against `data.id`, then `data.appId`).
        let appId = (payload["id"] as? String) ?? (payload["appId"] as? String)
        let state = payload["state"] as? String

        let event = CCPlatformEvent(id: id, timestamp: timestamp, type: eventName, appId: appId, state: state)
        eventSubject.send(event)
    }

    private func sendPong() {
        let payload: [String: String] = [
            "type": "heartbeat",
            "heartbeat_msg": "pong",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        webSocketTask?.send(.string(text)) { error in
            if let error {
                debugLog("❌ Events WS pong send failed: \(error)")
            }
        }
    }

    // MARK: - Reconnect

    private func handleSocketFailure(_ error: Error) {
        let nsError = error as NSError
        // URLSessionTask cancellation surfaces as error code -999. Treat as expected on disconnect.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            debugLog("ℹ️ ⏹️ Events WS cancelled")
            return
        }
        debugLog("❌ Events WS error: \(error.localizedDescription)")
        updateConnectionState(.failed(error.localizedDescription))
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard isUserConnected else { return }

        reconnectAttempt += 1
        // Exponential backoff: 2, 4, 8, 16, 30, 30, ...
        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        debugLog("ℹ️ 🔁 Events WS reconnect in \(Int(delay))s (attempt \(reconnectAttempt))")

        // asyncAfter on serialQueue: no run loop required (unlike Timer), and stays on the one queue
        // that owns all WebSocket state. Cancellable so disconnect() can drop a pending reconnect.
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isUserConnected else { return }
            self.openSocket()
        }
        reconnectWorkItem = work
        serialQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func updateConnectionState(_ newState: CCConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = newState
            self.connectionStateSubject.send(newState)
        }
        switch newState {
        case .disconnected:
            debugLog("ℹ️ 📡 Events state: Disconnected")
        case .polling:
            debugLog("ℹ️ 📡 Events state: Live (WebSocket connected)")
        case .failed(let reason):
            debugLog("❌ 📡 Events state: Failed — \(reason)")
        }
    }
}
