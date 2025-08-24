//
//  VolcanoWebSocketService.swift
//  vovo
//
//  Created by Assistant on 2024.
//

import Foundation
import Network
import CryptoKit

// MARK: - 扩展

extension UInt32 {
    var bytes: [UInt8] {
        return [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
}

// MARK: - 火山引擎协议定义

enum VolcanoMessageType: UInt8 {
    case fullClientRequest = 0b0001
    case audioOnlyRequest = 0b0010
    case fullServerResponse = 0b1001
    case errorResponse = 0b1111
}

enum VolcanoMessageFlags: UInt8 {
    case normal = 0b0000
    case lastAudioPacket = 0b0010
}

enum VolcanoSerializationMethod: UInt8 {
    case none = 0b0000
    case json = 0b0001
}

enum VolcanoCompressionMethod: UInt8 {
    case none = 0b0000
    case gzip = 0b0001
}

struct VolcanoProtocolHeader {
    let protocolVersion: UInt8 = 0b0001
    let headerSize: UInt8 = 0b0001
    let messageType: VolcanoMessageType
    let messageFlags: VolcanoMessageFlags
    let serializationMethod: VolcanoSerializationMethod
    let compressionMethod: VolcanoCompressionMethod
    let reserved: UInt8 = 0b00000000
    
    func toData() -> Data {
        var data = Data()
        
        // 第一个字节：协议版本(4位) + 头部大小(4位)
        let firstByte = (protocolVersion << 4) | headerSize
        data.append(firstByte)
        
        // 第二个字节：消息类型(4位) + 消息标志(4位)
        let secondByte = (messageType.rawValue << 4) | messageFlags.rawValue
        data.append(secondByte)
        
        // 第三个字节：序列化方法(4位) + 压缩方法(4位)
        let thirdByte = (serializationMethod.rawValue << 4) | compressionMethod.rawValue
        data.append(thirdByte)
        
        // 第四个字节：保留字段
        data.append(reserved)
        
        return data
    }
}

// MARK: - 火山引擎认证管理器

class VolcanoAuthManager {
    let appId: String
    let token: String
    let accessKey: String
    let cluster: String
    
    init(appId: String, token: String, accessKey: String, cluster: String) {
        self.appId = appId
        self.token = token
        self.accessKey = accessKey
        self.cluster = cluster
    }
    
    // 生成认证头 - v3大模型API格式
    func generateAuthHeaders() -> [String: String] {
        return [
            "X-Api-App-Key": appId,
            "X-Api-Access-Key": accessKey,
            "X-Api-Resource-Id": "volc.bigasr.sauc.duration", // 固定值：大模型流式语音识别
            "X-Api-Connect-Id": UUID().uuidString
        ]
    }
}

// MARK: - WebSocket服务代理协议

protocol VolcanoWebSocketServiceDelegate: AnyObject {
    func webSocketService(_ service: VolcanoWebSocketService, didReceiveResult result: SpeechRecognitionResult)
    func webSocketService(_ service: VolcanoWebSocketService, didChangeState state: SpeechRecognitionState)
    func webSocketService(_ service: VolcanoWebSocketService, didUpdateVolume volume: Float)
    func webSocketService(_ service: VolcanoWebSocketService, didEncounterError error: SpeechRecognitionError)
    func webSocketService(_ service: VolcanoWebSocketService, didConnect isConnected: Bool)
}

// MARK: - 火山引擎WebSocket服务

class VolcanoWebSocketService: NSObject {
    
    // MARK: - 属性
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let authManager: VolcanoAuthManager
    private var sequenceNumber: Int = 1
    private var requestId: String = ""
    private var audioDataQueue: [(Data, Bool)] = [] // 缓存音频数据队列
    private var isReconnecting: Bool = false // 重连标志
    
    weak var delegate: VolcanoWebSocketServiceDelegate?
    
    private var currentState: SpeechRecognitionState = .idle {
        didSet {
            delegate?.webSocketService(self, didChangeState: currentState)
        }
    }
    
    // MARK: - 初始化
    
    init(appId: String, token: String, accessKey: String, cluster: String) {
        self.authManager = VolcanoAuthManager(
            appId: appId,
            token: token,
            accessKey: accessKey,
            cluster: cluster
        )
        super.init()
        setupURLSession()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - 公共方法
    
    func startRecognition() {
        print("[VolcanoWebSocket] 🎤 开始语音识别")
        
        guard currentState == .idle else {
            print("[VolcanoWebSocket] ⚠️ 当前状态不允许开始识别: \(currentState)")
            return
        }
        
        currentState = .connecting
        requestId = UUID().uuidString
        sequenceNumber = 1
        
        // 检查是否已有连接
        if let task = webSocketTask, task.state == .running {
            print("[VolcanoWebSocket] ♻️ 复用现有WebSocket连接")
            sendInitialRequest()
        } else {
            print("[VolcanoWebSocket] 🔗 建立新的WebSocket连接")
            cleanupWebSocket()
            connectWebSocket()
        }
    }
    
    func sendAudioData(_ audioData: Data, isLast: Bool = false) {
        print("[VolcanoWebSocket] 🎵 准备发送音频数据 - 大小: \(audioData.count) bytes, 是否最后一包: \(isLast), 当前状态: \(currentState)")
        
        guard currentState == .recognizing || currentState == .connecting else {
            print("[VolcanoWebSocket] ⚠️ 当前状态不允许发送音频数据: \(currentState)")
            return
        }
        
        // 检查WebSocket连接状态
        guard let webSocketTask = webSocketTask, webSocketTask.state == .running else {
            print("[VolcanoWebSocket] ❌ WebSocket连接不可用，状态: \(webSocketTask?.state.rawValue ?? -1)")
            
            // 缓存音频数据
            audioDataQueue.append((audioData, isLast))
            print("[VolcanoWebSocket] 📦 缓存音频数据，队列长度: \(audioDataQueue.count)")
            
            // 连接断开时重新连接
            if currentState == .recognizing && !isReconnecting {
                print("[VolcanoWebSocket] 🔄 检测到连接断开，尝试重新连接")
                isReconnecting = true
                currentState = .connecting
                connectWebSocket()
            }
            return
        }
        
        // v3大模型API使用二进制协议发送音频数据 <mcreference link="https://www.volcengine.com/docs/6561/1354869" index="1">1</mcreference>
        let flags: VolcanoMessageFlags = isLast ? .lastAudioPacket : .normal
        let header = VolcanoProtocolHeader(
            messageType: .audioOnlyRequest,
            messageFlags: flags,
            serializationMethod: .none,
            compressionMethod: .none
        )
        
        var messageData = Data()
        messageData.append(header.toData())
        
        // 添加Payload大小（4字节，大端序）
        var payloadSize = UInt32(audioData.count).bigEndian
        messageData.append(Data(bytes: &payloadSize, count: 4))
        
        // 添加音频数据
        messageData.append(audioData)
        
        // 详细日志
        print("[VolcanoWebSocket] 🎵 发送音频数据包:")
        print("  序列号: \(sequenceNumber)")
        print("  音频数据大小: \(audioData.count) 字节")
        print("  是否最后一包: \(isLast)")
        print("  总消息大小: \(messageData.count) 字节")
        
        webSocketTask.send(.data(messageData)) { [weak self] error in
             if let error = error {
                 print("[VolcanoWebSocket] ❌ 发送音频数据失败: \(error)")
                 print("  序列号: \(self?.sequenceNumber ?? -1)")
                 print("  数据大小: \(audioData.count) 字节")
                 self?.handleError(.networkError(error.localizedDescription))
             } else {
                 print("[VolcanoWebSocket] ✅ 音频数据包发送成功 (序列号: \(self?.sequenceNumber ?? -1), 大小: \(audioData.count) 字节)")
             }
             
             // 递增序列号
             self?.sequenceNumber += 1
         }
         
         if isLast {
             print("[VolcanoWebSocket] 🏁 发送最后一个音频数据包")
         }
    }
    
    func stopRecognition() {
        print("[VolcanoWebSocket] 🛑 停止语音识别")
        currentState = .processing
        
        // 发送结束标记
        if currentState == .processing {
            print("[VolcanoWebSocket] 📤 发送结束标记")
            sendAudioData(Data(), isLast: true)
        }
        
        // 等待服务器响应
        print("[VolcanoWebSocket] ⏳ 等待服务器最终响应")
    }
    
    private func cleanupWebSocket() {
        print("[VolcanoWebSocket] 🧹 清理WebSocket连接")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
    
    func forceCloseConnection() {
        print("[VolcanoWebSocket] 🔒 强制关闭WebSocket连接")
        cleanupWebSocket()
        if currentState != .idle {
            currentState = .idle
        }
    }
    
    // MARK: - 私有方法
    
    private func connectWebSocket() {
        print("[VolcanoWebSocket] 🌐 准备连接WebSocket")
        
        // 火山引擎WebSocket URL - v3大模型双向流式模式
        guard let url = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel") else {
            print("[VolcanoWebSocket] ❌ 无效的WebSocket URL")
            handleError(.configurationError("无效的WebSocket URL"))
            return
        }
        
        print("[VolcanoWebSocket] 🔗 开始连接WebSocket: \(url)")
        
        var request = URLRequest(url: url)
        
        // 添加认证头
        let authHeaders = authManager.generateAuthHeaders()
        print("[VolcanoWebSocket] 🔑 添加鉴权头: \(authHeaders)")
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        print("[VolcanoWebSocket] 📡 创建WebSocket任务")
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        print("[VolcanoWebSocket] 📥 开始接收消息")
        // 开始接收消息
        receiveMessage()
        
        // 注意：不在这里发送初始请求，等待WebSocket连接建立后在didOpenWithProtocol回调中发送
    }
    
    private func sendInitialRequest() {
        print("[VolcanoWebSocket] 📋 准备发送初始请求")
        
        // 构建v3大模型API初始请求参数
        let requestParams: [String: Any] = [
            "user": [
                "uid": "vovo_user_\(UUID().uuidString.prefix(8))"
            ],
            "audio": [
                "format": "wav",
                "rate": 16000,
                "bits": 16,
                "channel": 1,
                "language": "zh-CN"
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": false,
                "enable_ddc": false,
                "enable_punc": false
            ]
        ]
        
        print("[VolcanoWebSocket] 📋 初始请求参数:")
        print("  AppID: \(authManager.appId)")
        print("  AccessKey: \(String(authManager.accessKey.prefix(10)))...")
        print("  Cluster: \(authManager.cluster)")
        print("  RequestID: \(requestId)")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestParams)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            print("[VolcanoWebSocket] 发送JSON: \(jsonString)")
            
            // 使用二进制协议格式发送初始请求
            let header = VolcanoProtocolHeader(
                messageType: .fullClientRequest,
                messageFlags: .normal,
                serializationMethod: .json,
                compressionMethod: .none
            )
            
            var messageData = Data()
            
            // 添加协议头（4字节）
            messageData.append(header.toData())
            
            // 添加payload大小（4字节，大端序）
            let payloadSize = UInt32(jsonData.count)
            messageData.append(contentsOf: payloadSize.bigEndian.bytes)
            
            // 添加JSON payload
            messageData.append(jsonData)
            
            print("[VolcanoWebSocket] 发送二进制消息，总大小: \(messageData.count) 字节")
            print("[VolcanoWebSocket] 协议头: 4字节, Payload大小: 4字节, JSON数据: \(jsonData.count)字节")
            
            // 发送二进制消息
            webSocketTask?.send(.data(messageData)) { [weak self] error in
                if let error = error {
                    print("[VolcanoWebSocket] ❌ 发送初始请求失败: \(error)")
                    self?.handleError(.networkError(error.localizedDescription))
                } else {
                    print("[VolcanoWebSocket] ✅ 初始请求发送成功")
                    self?.currentState = .recognizing  // 修改为recognizing状态，允许发送音频数据
                    self?.isReconnecting = false  // 重置重连标志
                    
                    // 发送缓存的音频数据
                    self?.sendCachedAudioData()
                    
                    if let strongSelf = self {
                        strongSelf.delegate?.webSocketService(strongSelf, didConnect: true)
                    }
                }
            }
            
        } catch {
            print("[VolcanoWebSocket] ❌ JSON序列化失败: \(error)")
            handleError(.configurationError(error.localizedDescription))
        }
    }
    
    private func receiveMessage() {
        // 检查WebSocket连接状态
        guard let webSocketTask = webSocketTask, webSocketTask.state == .running else {
            print("[VolcanoWebSocket] ⚠️ WebSocket连接不可用，停止接收消息")
            return
        }
        
        print("[VolcanoWebSocket] 🔄 开始监听WebSocket消息...")
        webSocketTask.receive { [weak self] result in
            switch result {
            case .success(let message):
                print("[VolcanoWebSocket] 📥 收到WebSocket消息 - 时间: \(Date())")
                self?.handleReceivedMessage(message)
                self?.receiveMessage() // 继续接收下一条消息
                
            case .failure(let error):
                print("[VolcanoWebSocket] ❌ 接收消息失败: \(error)")
                print("[VolcanoWebSocket] 错误详情: \(error.localizedDescription)")
                print("[VolcanoWebSocket] 错误类型: \(type(of: error))")
                self?.handleError(.networkError(error.localizedDescription))
            }
        }
    }
    
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            print("[VolcanoWebSocket] 📦 收到服务器二进制响应:")
            print("  数据大小: \(data.count) 字节")
            print("  数据前16字节: \(data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))")
            parseServerResponse(data)
            
        case .string(let text):
            print("[VolcanoWebSocket] 📝 收到服务器文本消息:")
            print("  内容: \(text)")
            print("  长度: \(text.count) 字符")
            
        @unknown default:
            print("[VolcanoWebSocket] ⚠️ 收到未知类型的消息")
        }
    }
    
    private func parseServerResponse(_ data: Data) {
        print("[VolcanoWebSocket] 🔍 开始解析服务器响应 - 数据大小: \(data.count) 字节")
        
        guard data.count >= 8 else {
            print("[VolcanoWebSocket] ❌ 响应数据长度不足: \(data.count) < 8")
            return
        }
        
        // 解析头部（4字节）
        let headerData = data.prefix(4)
        print("[VolcanoWebSocket] 📋 协议头: \(headerData.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // 解析Payload大小（4字节）
        let payloadSizeData = data.subdata(in: 4..<8)
        let payloadSize = payloadSizeData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        print("[VolcanoWebSocket] 📏 Payload大小: \(payloadSize) 字节")
        
        // 检查数据完整性
        guard data.count >= 8 + Int(payloadSize) else {
            print("[VolcanoWebSocket] ❌ Payload数据长度不足: 需要 \(8 + Int(payloadSize))，实际 \(data.count)")
            return
        }
        
        let payloadData = data.subdata(in: 8..<(8 + Int(payloadSize)))
        print("[VolcanoWebSocket] 📦 Payload数据: \(payloadData.count) 字节")
        
        // 尝试解析JSON
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                print("[VolcanoWebSocket] ✅ JSON解析成功")
                handleServerResponse(jsonObject)
            } else {
                print("[VolcanoWebSocket] ❌ JSON解析失败: 不是有效的字典格式")
                // 尝试打印原始数据
                if let jsonString = String(data: payloadData, encoding: .utf8) {
                    print("[VolcanoWebSocket] 📝 原始JSON: \(jsonString)")
                }
            }
        } catch {
            print("[VolcanoWebSocket] ❌ JSON解析异常: \(error)")
            // 尝试打印原始数据
            if let jsonString = String(data: payloadData, encoding: .utf8) {
                print("[VolcanoWebSocket] 📝 原始数据: \(jsonString)")
            } else {
                print("[VolcanoWebSocket] 📝 原始数据(十六进制): \(payloadData.map { String(format: "%02X", $0) }.joined(separator: " "))")
            }
        }
    }
    
    private func handleServerResponse(_ response: [String: Any]) {
        print("[VolcanoWebSocket] 📨 收到服务器响应: \(response)")
        
        // 检查错误
        if let error = response["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "未知错误"
            print("[VolcanoWebSocket] ❌ 服务器返回错误: code=\(code), message=\(message)")
            
            // 根据错误码分类
            let speechError: SpeechRecognitionError
            switch code {
            case 1000...1999:
                speechError = .authenticationError(message)
            case 2000...2999:
                speechError = .networkError(message)
            case 3000...3999:
                speechError = .serviceUnavailable(message)
            default:
                speechError = .unknownError(message)
            }
            
            handleError(speechError)
            return
        }
        
        // 处理识别结果
        if let result = response["result"] as? [String: Any] {
            print("[VolcanoWebSocket] 🎯 解析识别结果: \(result)")
            
            if let text = result["text"] as? String {
                let isFinal = result["definite"] as? Bool ?? false
                print("[VolcanoWebSocket] 📝 识别文本: '\(text)' (最终: \(isFinal))")
                
                let recognitionResult = SpeechRecognitionResult(
                    text: text,
                    isFinal: isFinal,
                    confidence: result["confidence"] as? Float ?? 0.0,
                    startTime: 0,
                    endTime: 0,
                    segmentId: String(result["segment_id"] as? Int ?? 0),
                    words: [] // 可以进一步解析单词信息
                )
                
                delegate?.webSocketService(self, didReceiveResult: recognitionResult)
                
                if isFinal {
                    print("[VolcanoWebSocket] ✅ 识别完成，准备关闭连接")
                    currentState = .completed
                    // 延迟关闭连接，确保所有数据处理完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.forceCloseConnection()
                    }
                } else {
                    currentState = .recognizing
                }
            } else {
                print("[VolcanoWebSocket] ⚠️ 结果中没有文本字段")
            }
        } else {
            print("[VolcanoWebSocket] ⚠️ 响应中没有result字段")
        }
    }
    
    private func handleError(_ error: SpeechRecognitionError) {
        print("[VolcanoWebSocket] ❌ 处理错误: \(error.localizedDescription)")
        
        // 检查是否是网络连接错误
        if case .networkError(let errorMessage) = error, errorMessage.contains("Socket is not connected") {
            print("[VolcanoWebSocket] 🔄 检测到Socket连接断开，尝试自动重连")
            
            // 清理当前连接
            webSocketTask?.cancel()
            self.webSocketTask = nil
            
            // 设置为连接中状态并尝试重连
            currentState = .connecting
            
            // 设置重连标志
            isReconnecting = true
            
            // 延迟重连，避免频繁重试
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                print("[VolcanoWebSocket] 🔄 开始自动重连")
                self.connectWebSocket()
            }
        } else {
            // 其他类型的错误，设置为错误状态
            currentState = .error(error)
            delegate?.webSocketService(self, didEncounterError: error)
            
            // 清理连接
            print("[VolcanoWebSocket] 🔌 清理WebSocket连接")
            webSocketTask?.cancel()
            self.webSocketTask = nil
        }
    }
    
    private func sendCachedAudioData() {
        guard !audioDataQueue.isEmpty else {
            print("[VolcanoWebSocket] 📦 没有缓存的音频数据需要发送")
            return
        }
        
        print("[VolcanoWebSocket] 📦 开始发送缓存的音频数据，队列长度: \(audioDataQueue.count)")
        
        // 发送所有缓存的音频数据
        let cachedData = audioDataQueue
        audioDataQueue.removeAll()
        
        for (audioData, isLast) in cachedData {
            sendAudioDataDirectly(audioData, isLast: isLast)
        }
        
        print("[VolcanoWebSocket] 📦 缓存音频数据发送完成")
    }
    
    private func sendAudioDataDirectly(_ audioData: Data, isLast: Bool) {
        guard let webSocketTask = webSocketTask, webSocketTask.state == .running else {
            print("[VolcanoWebSocket] ❌ WebSocket连接不可用，无法发送缓存数据")
            return
        }
        
        let flags: VolcanoMessageFlags = isLast ? .lastAudioPacket : .normal
        let header = VolcanoProtocolHeader(
            messageType: .audioOnlyRequest,
            messageFlags: flags,
            serializationMethod: .none,
            compressionMethod: .none
        )
        
        var messageData = Data()
        messageData.append(header.toData())
        messageData.append(contentsOf: UInt32(audioData.count).bigEndian.bytes)
        messageData.append(audioData)
        
        webSocketTask.send(.data(messageData)) { error in
            if let error = error {
                print("[VolcanoWebSocket] ❌ 发送缓存音频数据失败: \(error)")
            } else {
                print("[VolcanoWebSocket] ✅ 缓存音频数据发送成功，大小: \(audioData.count) bytes")
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension VolcanoWebSocketService: URLSessionWebSocketDelegate {
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[VolcanoWebSocket] ✅ WebSocket连接已建立")
        if let protocolName = `protocol` {
            print("[VolcanoWebSocket] Protocol: \(protocolName)")
        } else {
            print("[VolcanoWebSocket] Protocol: none")
        }
        
        // 捕获并记录响应头
        if let httpResponse = webSocketTask.response as? HTTPURLResponse {
            print("[VolcanoWebSocket] 📋 响应头信息:")
            for (key, value) in httpResponse.allHeaderFields {
                print("[VolcanoWebSocket] \(key): \(value)")
            }
            
            // 特别记录X-Tt-Logid用于排错
            if let logId = httpResponse.allHeaderFields["X-Tt-Logid"] as? String {
                print("[VolcanoWebSocket] 🔍 LogID: \(logId) (请保存此ID用于排错)")
            }
            
            // 记录X-Api-Connect-Id
            if let connectId = httpResponse.allHeaderFields["X-Api-Connect-Id"] as? String {
                print("[VolcanoWebSocket] 🔗 Connect-ID: \(connectId)")
            }
        }
        
        // WebSocket连接建立后发送初始请求
        print("[VolcanoWebSocket] 📤 连接建立，发送初始请求")
        sendInitialRequest()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[VolcanoWebSocket] 🔌 WebSocket连接已关闭")
        print("[VolcanoWebSocket] 关闭码: \(closeCode.rawValue)")
        if let reason = reason, let reasonString = String(data: reason, encoding: .utf8) {
            print("[VolcanoWebSocket] 关闭原因: \(reasonString)")
        }
        
        // 如果是在识别过程中意外断开，尝试重连
        if currentState == .recognizing {
            print("[VolcanoWebSocket] 🔄 识别过程中连接断开，尝试重新连接")
            currentState = .connecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.connectWebSocket()
            }
        } else {
            // 更新状态
            if currentState != .idle {
                currentState = .idle
            }
        }
        
        delegate?.webSocketService(self, didConnect: false)
    }
}

// MARK: - URLSessionDelegate

extension VolcanoWebSocketService: URLSessionDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[VolcanoWebSocket] ❌ URLSession任务完成时发生错误: \(error.localizedDescription)")
            handleError(.networkError(error.localizedDescription))
        }
    }
}