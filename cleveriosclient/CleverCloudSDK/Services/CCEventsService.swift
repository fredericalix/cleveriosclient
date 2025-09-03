import Foundation
import Combine
import UIKit

// MARK: - Debug Logger
@MainActor
final class CCDebugLogger {
    static let shared = CCDebugLogger()
    
    private let logFileURL: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("polling_debug.log")
    }()
    
    private init() {
        // Clear log file on init
        try? FileManager.default.removeItem(at: logFileURL)
    }
    
    func log(_ message: String, isError: Bool = false) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        
        // Console output
        print(logMessage.trimmingCharacters(in: .whitespacesAndNewlines))
        
        // File output
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}

// MARK: - Connection State
public enum CCConnectionState: Equatable {
    case disconnected
    case polling
    case failed(Error)
    
    public static func == (lhs: CCConnectionState, rhs: CCConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected):
            return true
        case (.polling, .polling):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
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



// MARK: - Events Service (Polling Only)
public final class CCEventsService: NSObject, ObservableObject, @unchecked Sendable {
    
    // MARK: - Properties
    private let baseURL: String
    private let urlSession: URLSession
    
    // State management
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
    
    // Polling management
    private var pollingTimer: Timer?
    private var pollingInterval: TimeInterval = 15.0 // Default 15 seconds
    private var isPollingActive = false
    
    // Debug helper
    private func writeToDebugLog(_ message: String) {
        Task { @MainActor in
            CCDebugLogger.shared.log(message)
        }
    }
    
    // MARK: - Initialization
    public init(baseURL: String, oauthSigner: CCOAuthSigner) {
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)
        
        super.init()
        
        writeToDebugLog("✅ CCEventsService initialized with polling system")
        writeToDebugLog("📍 Base URL: \(baseURL)")
    }
    
    // MARK: - Public Methods
    
    /// Start polling for events
    public func connect() {
        guard !isPollingActive else {
            writeToDebugLog("⚠️ Polling already active, ignoring connect request")
            return
        }
        
        writeToDebugLog("🚀 Starting polling system with \(pollingInterval)s interval")
        updateConnectionState(.polling)
        
        isPollingActive = true
        startPolling()
    }
    
    /// Stop polling for events
    public func disconnect() {
        guard isPollingActive else {
            writeToDebugLog("⚠️ Polling not active, ignoring disconnect request")
            return
        }
        
        writeToDebugLog("🛑 Stopping polling system")
        stopPolling()
        isPollingActive = false
        updateConnectionState(.disconnected)
    }
    
    /// Set custom polling interval (in seconds)
    public func setPollingInterval(_ interval: TimeInterval) {
        guard interval >= 5.0 else {
            writeToDebugLog("⚠️ Polling interval must be at least 5 seconds")
            return
        }
        
        pollingInterval = interval
        writeToDebugLog("⚙️ Polling interval set to \(interval) seconds")
        
        // If already polling, restart with new interval
        if isPollingActive {
            stopPolling()
            startPolling()
        }
    }
    
    // MARK: - Private Methods
    
    private func updateConnectionState(_ newState: CCConnectionState) {
        connectionState = newState
        connectionStateSubject.send(newState)
        
        switch newState {
        case .disconnected:
            writeToDebugLog("📡 State: Disconnected")
        case .polling:
            writeToDebugLog("📡 State: Polling Active")
        case .failed(let error):
            writeToDebugLog("📡 State: Failed - \(error.localizedDescription)")
        }
    }
    
    private func startPolling() {
        // Poll immediately
        pollEvents()
        
        // Then set up timer for regular polling
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollEvents()
        }
    }
    
    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    private func pollEvents() {
        writeToDebugLog("🔄 Polling for events...")
        
        // Here you would make your actual API call to fetch events
        // For now, we'll emit some test events
        let testEvent = CCPlatformEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            type: "applicationStatusChanged",
            data: ["status": "polling", "timestamp": Date().timeIntervalSince1970]
        )
        
        eventSubject.send(testEvent)
        writeToDebugLog("✅ Poll completed - event emitted")
    }
} 