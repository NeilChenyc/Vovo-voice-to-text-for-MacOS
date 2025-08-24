//
//  Logger.swift
//  vovo
//
//  Created by Assistant on 2024.
//

import Foundation
import os.log

// MARK: - Log Level
enum LogLevel: String, CaseIterable {
    case debug = "🔍 DEBUG"
    case info = "ℹ️ INFO"
    case warning = "⚠️ WARNING"
    case error = "❌ ERROR"
    case success = "✅ SUCCESS"
    case network = "🌐 NETWORK"
    case websocket = "🔌 WEBSOCKET"
    case audio = "🎤 AUDIO"
    case config = "⚙️ CONFIG"
    
    var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        case .success:
            return .info
        case .network, .websocket, .audio, .config:
            return .info
        }
    }
}

// MARK: - Logger Class
class Logger {
    
    static let shared = Logger()
    
    private let osLog: OSLog
    private let dateFormatter: DateFormatter
    private let isDebugMode: Bool
    
    private init() {
        self.osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.vovo.app", category: "VovoApp")
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        #if DEBUG
        self.isDebugMode = true
        #else
        self.isDebugMode = false
        #endif
    }
    
    // MARK: - Public Logging Methods
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }
    
    func success(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .success, message: message, file: file, function: function, line: line)
    }
    
    // MARK: - Specialized Logging Methods
    
    func network(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .network, message: message, file: file, function: function, line: line)
    }
    
    func websocket(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .websocket, message: message, file: file, function: function, line: line)
    }
    
    func audio(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .audio, message: message, file: file, function: function, line: line)
    }
    
    func config(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .config, message: message, file: file, function: function, line: line)
    }
    
    // MARK: - WebSocket Specific Methods
    
    func websocketConnection(_ status: String, url: String? = nil) {
        let urlInfo = url != nil ? " URL: \(url!)" : ""
        websocket("连接状态: \(status)\(urlInfo)")
    }
    
    func websocketSend(_ messageType: String, size: Int) {
        websocket("发送数据: \(messageType), 大小: \(size) bytes")
    }
    
    func websocketReceive(_ messageType: String, size: Int, content: String? = nil) {
        let contentInfo = content != nil ? ", 内容: \(content!)" : ""
        websocket("接收数据: \(messageType), 大小: \(size) bytes\(contentInfo)")
    }
    
    func websocketError(_ error: String) {
        websocket("错误: \(error)")
    }
    
    // MARK: - Audio Specific Methods
    
    func audioRecording(_ status: String, details: String? = nil) {
        let detailsInfo = details != nil ? " - \(details!)" : ""
        audio("录音状态: \(status)\(detailsInfo)")
    }
    
    func audioData(_ info: String) {
        audio("音频数据: \(info)")
    }
    
    // MARK: - Config Specific Methods
    
    func configLoad(_ status: String, details: String? = nil) {
        let detailsInfo = details != nil ? " - \(details!)" : ""
        config("配置加载: \(status)\(detailsInfo)")
    }
    
    func configValidation(_ result: String, details: String? = nil) {
        let detailsInfo = details != nil ? " - \(details!)" : ""
        config("配置验证: \(result)\(detailsInfo)")
    }
    
    // MARK: - Private Methods
    
    private func log(level: LogLevel, message: String, file: String, function: String, line: Int) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let formattedMessage = "[\(timestamp)] \(level.rawValue) [\(fileName):\(line)] \(function) - \(message)"
        
        // 输出到Xcode控制台
        print(formattedMessage)
        
        // 输出到系统日志（可在Console.app中查看）
        if isDebugMode || level == .error || level == .warning {
            os_log("%{public}@", log: osLog, type: level.osLogType, formattedMessage)
        }
    }
}

// MARK: - Convenience Extensions
extension Logger {
    
    // 数据包详细信息记录
    func logDataPacket(direction: String, type: String, data: Data) {
        let hexString = data.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
        let truncated = data.count > 32 ? "..." : ""
        websocket("\(direction) 数据包: \(type), 大小: \(data.count) bytes, 内容: \(hexString)\(truncated)")
    }
    
    // API响应记录
    func logAPIResponse(endpoint: String, statusCode: Int? = nil, response: String? = nil) {
        let statusInfo = statusCode != nil ? " [\(statusCode!)]" : ""
        let responseInfo = response != nil ? ", 响应: \(response!)" : ""
        network("API响应\(statusInfo): \(endpoint)\(responseInfo)")
    }
    
    // 性能监控
    func logPerformance(_ operation: String, duration: TimeInterval) {
        info("性能监控: \(operation) 耗时 \(String(format: "%.3f", duration))s")
    }
}