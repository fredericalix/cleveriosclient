import Foundation
import Combine

// MARK: - Connection State
public enum CCConnectionState: Equatable, Sendable {
    case disconnected
    case polling
    case failed(String)
}

// MARK: - Event Models
public struct CCPlatformEvent {
    public let id: String
    public let timestamp: Date
    public let type: String
    public let data: [String: Any]

    public init(id: String, timestamp: Date, type: String, data: [String: Any]) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.data = data
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

    // WebSocket state
    private var webSocketTask: URLSessionWebSocketTask?
    private var isUserConnected = false
    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var reconnectTimer: Timer?

    // Kept for compatibility with callers — the WebSocket doesn't poll, but if it becomes a fallback
    // we may want a periodic ping. For now this is informational only.
    private var pollingInterval: TimeInterval = 15.0

    private let serialQueue = DispatchQueue(label: "com.fredalix.cciosclient.events", qos: .userInitiated)

    // MARK: - Initialization
    public init(baseURL: String, oauthSigner: CCOAuthSigner) {
        self.apiV2BaseURL = baseURL
        self.oauthSigner = oauthSigner

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)

        super.init()
        debugLog("ℹ️ ✅ CCEventsService initialized [endpoint=\(eventSocketURL().absoluteString)]")
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
            self.reconnectTimer?.invalidate()
            self.reconnectTimer = nil
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

    private func eventSocketURL() -> URL {
        // baseURL is https://api.clever-cloud.com/v2 — strip the https scheme and append the path.
        var components = URLComponents(string: apiV2BaseURL)!
        components.scheme = "wss"
        components.path = (components.path as NSString).appendingPathComponent("events/event-socket")
        return components.url!
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

        let url = eventSocketURL()
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

        let event = CCPlatformEvent(id: id, timestamp: timestamp, type: eventName, data: payload)
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

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.serialQueue.async {
                guard self.isUserConnected else { return }
                self.openSocket()
            }
        }
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
