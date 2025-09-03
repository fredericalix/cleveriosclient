//
//  RemoteLogger.swift
//  cleveriosclient
//
//  Remote logging system for debugging TestFlight issues
//

import Foundation
import UIKit

// MARK: - Log Level
public enum LogLevel: String, Codable, Sendable {
    case error = "ERROR"
    case warn = "WARN"
    case info = "INFO"
    case debug = "DEBUG"
}

// MARK: - Device Information
struct DeviceInfo: Codable, Sendable {
    let deviceId: String
    let model: String
    let osVersion: String
    let appVersion: String
    let buildNumber: String
}

// MARK: - Log Context
struct LogContext: Codable, Sendable {
    let file: String?
    let function: String?
    let line: Int?
    let userId: String?
    let organizationId: String?
}

// MARK: - Log Entry
struct LogEntry: Codable, Sendable {
    let timestamp: Date
    let level: LogLevel
    let message: String
    let deviceInfo: DeviceInfo
    let context: LogContext?
    let sessionId: String?
    let metadata: [String: String]?
}

// MARK: - Batch Request
struct LogBatchRequest: Codable, Sendable {
    let logs: [LogEntry]
}

// MARK: - Logger Configuration
public final class LoggerConfiguration: Sendable {
    let apiEndpoint: String
    let authToken: String
    let batchSize: Int
    let flushInterval: TimeInterval
    let maxRetries: Int
    let enableConsoleOutput: Bool
    
    public init(apiEndpoint: String = "https://log-ios.fredalix.com",
                authToken: String = "cf4a1462-8666-4b75-874e-4a28e7f9ef4c",
                batchSize: Int = 50,
                flushInterval: TimeInterval = 30.0,
                maxRetries: Int = 3,
                enableConsoleOutput: Bool = true) {
        self.apiEndpoint = apiEndpoint
        self.authToken = authToken
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.maxRetries = maxRetries
        self.enableConsoleOutput = enableConsoleOutput
    }
}

// MARK: - Remote Logger
@globalActor
public actor RemoteLoggerActor {
    public static let shared = RemoteLoggerActor()
}

public final class RemoteLogger: @unchecked Sendable {
    public static let shared = RemoteLogger()
    private var configuration: LoggerConfiguration?
    private let queue = DispatchQueue(label: "com.clevercloud.logger", qos: .background)
    private var logBuffer: [LogEntry] = []
    private var timer: Timer?
    private var currentUserId: String?
    private var currentOrganizationId: String?
    
    private init() {
        // Load any persisted logs on init
        loadPersistedLogs()
    }
    
    // MARK: - Configuration
    public func configure(with config: LoggerConfiguration = LoggerConfiguration()) {
        self.configuration = config
        startBatchTimer()
        
        // Log configuration
        info("RemoteLogger configured", metadata: [
            "endpoint": config.apiEndpoint,
            "batchSize": String(config.batchSize),
            "flushInterval": String(config.flushInterval)
        ])
    }
    
    // MARK: - User Context
    public func setUserContext(userId: String?, organizationId: String?) {
        self.currentUserId = userId
        self.currentOrganizationId = organizationId
    }
    
    // MARK: - Logging Methods
    public func error(_ message: String,
                     file: String = #file,
                     function: String = #function,
                     line: Int = #line,
                     metadata: [String: String]? = nil) {
        log(level: .error, message: message, file: file, function: function, line: line, metadata: metadata)
    }
    
    public func warn(_ message: String,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line,
                    metadata: [String: String]? = nil) {
        log(level: .warn, message: message, file: file, function: function, line: line, metadata: metadata)
    }
    
    public func info(_ message: String,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line,
                    metadata: [String: String]? = nil) {
        log(level: .info, message: message, file: file, function: function, line: line, metadata: metadata)
    }
    
    public func debug(_ message: String,
                     file: String = #file,
                     function: String = #function,
                     line: Int = #line,
                     metadata: [String: String]? = nil) {
        log(level: .debug, message: message, file: file, function: function, line: line, metadata: metadata)
    }
    
    // MARK: - Core Logging
    private func log(level: LogLevel,
                    message: String,
                    file: String,
                    function: String,
                    line: Int,
                    metadata: [String: String]?) {
        
        // Console output if enabled
        if configuration?.enableConsoleOutput ?? true {
            let emoji = levelEmoji(for: level)
            let fileName = URL(fileURLWithPath: file).lastPathComponent
            print("\(emoji) [\(fileName):\(line)] \(function) - \(message)")
        }
        
        // Skip if not configured
        guard configuration != nil else { return }
        
        let context = LogContext(
            file: URL(fileURLWithPath: file).lastPathComponent,
            function: function,
            line: line,
            userId: currentUserId,
            organizationId: currentOrganizationId
        )
        
        Task { @MainActor in
            let deviceInfo = getDeviceInfo()
            
            let logEntry = LogEntry(
                timestamp: Date(),
                level: level,
                message: message,
                deviceInfo: deviceInfo,
                context: context,
                sessionId: getSessionId(),
                metadata: metadata
            )
            
            queue.async { [weak self] in
                self?.logBuffer.append(logEntry)
                
                if let batchSize = self?.configuration?.batchSize,
                   self?.logBuffer.count ?? 0 >= batchSize {
                    self?.flush()
                }
            }
        }
    }
    
    private func levelEmoji(for level: LogLevel) -> String {
        switch level {
        case .error: return "❌"
        case .warn: return "⚠️"
        case .info: return "ℹ️"
        case .debug: return "🔍"
        }
    }
    
    // MARK: - Device Information
    @MainActor
    private func getDeviceInfo() -> DeviceInfo {
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        return DeviceInfo(
            deviceId: getOrCreateDeviceId(),
            model: getDeviceModel(),
            osVersion: device.systemVersion,
            appVersion: appVersion,
            buildNumber: buildNumber
        )
    }
    
    private func getOrCreateDeviceId() -> String {
        let key = "com.clevercloud.logger.deviceId"
        if let deviceId = UserDefaults.standard.string(forKey: key) {
            return deviceId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
    
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // Common device mappings
        let modelMap: [String: String] = [
            // iPhone 15 series
            "iPhone15,3": "iPhone 15 Pro Max",
            "iPhone15,2": "iPhone 15 Pro",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone15,4": "iPhone 15",
            // iPhone 14 series
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone14,7": "iPhone 14",
            "iPhone14,3": "iPhone 14 Pro Max",
            "iPhone14,2": "iPhone 14 Pro",
            // iPhone 13 series
            "iPhone14,5": "iPhone 13",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,6": "iPhone 13 Pro Max",
            "iPhone13,3": "iPhone 13 Pro",
            // iPad
            "iPad13,1": "iPad Air (4th gen)",
            "iPad13,2": "iPad Air (4th gen)",
            // Simulator
            "arm64": "Simulator (Apple Silicon)",
            "x86_64": "Simulator (Intel)"
        ]
        
        return modelMap[identifier] ?? identifier
    }
    
    // MARK: - Session Management
    private var sessionId: String {
        if let id = UserDefaults.standard.string(forKey: "com.clevercloud.logger.sessionId") {
            return id
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "com.clevercloud.logger.sessionId")
        return newId
    }
    
    private func getSessionId() -> String {
        return sessionId
    }
    
    public func startNewSession() {
        UserDefaults.standard.set(UUID().uuidString, forKey: "com.clevercloud.logger.sessionId")
        info("New session started")
    }
    
    // MARK: - Batching and Network
    private func startBatchTimer() {
        timer?.invalidate()
        
        guard let interval = configuration?.flushInterval else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }
    
    public func flush() {
        queue.async { [weak self] in
            guard let self = self,
                  !self.logBuffer.isEmpty,
                  let config = self.configuration else { return }
            
            let logsToSend = Array(self.logBuffer.prefix(config.batchSize))
            self.logBuffer.removeFirst(min(logsToSend.count, self.logBuffer.count))
            
            self.sendLogs(logsToSend, config: config)
        }
    }
    
    private func sendLogs(_ logs: [LogEntry], config: LoggerConfiguration) {
        // 🚫 DISABLED: Remote logging to log-ios.fredalix.com has been disabled
        // Logs will only be printed to console, not sent to remote server
        if config.enableConsoleOutput {
            print("🚫 RemoteLogger: Remote logging disabled - \(logs.count) logs NOT sent to server")
        }
        return
        
        // Original code below is commented out to disable remote logging
        /*
        guard let url = URL(string: "\(config.apiEndpoint)/api/logs") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let batchRequest = LogBatchRequest(logs: logs)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(batchRequest)
            request.httpBody = jsonData
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    if config.enableConsoleOutput {
                        print("❌ RemoteLogger: Failed to send logs - \(error.localizedDescription)")
                    }
                    self?.handleFailedBatch(logs)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200...299:
                        if config.enableConsoleOutput {
                            print("✅ RemoteLogger: Successfully sent \(logs.count) logs")
                        }
                    case 401:
                        print("❌ RemoteLogger: Authentication failed. Check your auth token.")
                    case 429:
                        print("⚠️ RemoteLogger: Rate limit exceeded. Will retry later.")
                        self?.handleFailedBatch(logs)
                    default:
                        print("❌ RemoteLogger: Server returned status \(httpResponse.statusCode)")
                        self?.handleFailedBatch(logs)
                    }
                }
            }.resume()
            
        } catch {
            if config.enableConsoleOutput {
                print("❌ RemoteLogger: Failed to encode logs - \(error.localizedDescription)")
            }
            handleFailedBatch(logs)
        }
        */
    }
    
    // MARK: - Offline Support
    private func handleFailedBatch(_ logs: [LogEntry]) {
        queue.async { [weak self] in
            // Prepend failed logs back to buffer for retry
            self?.logBuffer.insert(contentsOf: logs, at: 0)
            
            // Persist to disk if buffer is getting too large
            if self?.logBuffer.count ?? 0 > 1000 {
                self?.persistLogsToFile()
            }
        }
    }
    
    private func persistLogsToFile() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask).first!
        let logFilePath = documentsPath.appendingPathComponent("pending_logs.json")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(logBuffer)
            try data.write(to: logFilePath)
            logBuffer.removeAll()
        } catch {
            print("❌ RemoteLogger: Failed to persist logs - \(error.localizedDescription)")
        }
    }
    
    private func loadPersistedLogs() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask).first!
        let logFilePath = documentsPath.appendingPathComponent("pending_logs.json")
        
        guard FileManager.default.fileExists(atPath: logFilePath.path) else { return }
        
        do {
            let data = try Data(contentsOf: logFilePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let logs = try decoder.decode([LogEntry].self, from: data)
            logBuffer.append(contentsOf: logs)
            try FileManager.default.removeItem(at: logFilePath)
        } catch {
            print("❌ RemoteLogger: Failed to load persisted logs - \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    public func logNetworkRequest(method: String, url: String, statusCode: Int?, error: Error?) {
        var metadata: [String: String] = [
            "method": method,
            "url": url
        ]
        
        if let statusCode = statusCode {
            metadata["statusCode"] = String(statusCode)
        }
        
        if let error = error {
            metadata["error"] = error.localizedDescription
            self.error("Network request failed", metadata: metadata)
        } else {
            self.debug("Network request completed", metadata: metadata)
        }
    }
} 