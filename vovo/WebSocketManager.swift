//
//  WebSocketManager.swift
//  vovo
//
//  Created by Assistant on 2024.
//

import Foundation
import Network
import Compression

// MARK: - UInt32 Extension for Byte Conversion
extension UInt32 {
    var bytes: [UInt8] {
        return [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
    
    // 修复：确保大端序字节转换正确
    var bigEndianBytes: [UInt8] {
        // 直接从原始值转换为大端序字节，不使用.bigEndian
        return [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
}

// MARK: - Volcano Protocol Definitions
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

// Ensure ConfigManager and Logger are accessible
// These should be part of the same module/target
class WebSocketManager: NSObject {
    
    private let configManager = ConfigManager.shared
    private let logger = Logger.shared
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var connectId: String = ""
    private var sequenceNumber: Int32 = 1
    private var hasStartedRecording = false
    
    var onRecognitionResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onConnectionStatusChanged: ((Bool) -> Void)?
    
    override init() {
        super.init()
        setupURLSession()
        generateConnectId()
    }
    
    // MARK: - Public Methods
    
    func connect() {
        logger.websocket("🚀 WebSocket connect() 方法被调用")
        
        guard !isConnected else { 
            logger.websocket("连接请求被忽略 - 已经连接")
            return 
        }
        
        logger.websocket("开始建立WebSocket连接...")
        
        guard let config = configManager.getVolcanoAPIConfig() else {
            logger.error("无法获取API配置")
            onError?(NSError(domain: "ConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey: "API配置不可用"]))
            return
        }
        
        logger.config("使用配置 - URL: \(config.websocketURL), ResourceID: \(config.resourceId)")
        
        guard let url = URL(string: config.websocketURL) else {
            logger.error("无效的 WebSocket URL: \(config.websocketURL)")
            return
        }
        
        var request = URLRequest(url: url)
        
        // 添加火山引擎 API 认证头（严格按照API文档）
        let connectId = UUID().uuidString
        request.setValue(config.appKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(config.accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(config.resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectId, forHTTPHeaderField: "X-Api-Connect-Id")
        
        // 存储connectId用于后续使用
        self.connectId = connectId
        
        logger.websocket("设置认证头 - AppKey: \(config.appKey.prefix(8))..., ConnectId: \(connectId.prefix(8))...")
        
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        
        logger.websocket("WebSocket任务已启动")
        logger.websocketConnection("正在连接", url: config.websocketURL)
    }
    
    func disconnect() {
        guard isConnected else { 
            logger.websocket("断开连接请求被忽略 - 未连接")
            return 
        }
        
        logger.websocket("开始断开WebSocket连接")
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        onConnectionStatusChanged?(false)
        
        logger.websocketConnection("已断开")
    }
    
    func sendAudioData(_ audioData: Data) {
        guard isConnected else {
            logger.websocket("WebSocket 未连接，无法发送音频数据")
            return
        }
        
        logger.websocketSend("音频数据", size: audioData.count)
        
        let binaryMessage = createAudioMessage(audioData)
        logger.logDataPacket(direction: "发送", type: "音频消息", data: binaryMessage)
        
        webSocketTask?.send(.data(binaryMessage)) { error in
            if let error = error {
                self.logger.websocketError("发送音频数据失败: \(error.localizedDescription)")
                self.onError?(error)
            } else {
                self.logger.websocket("音频数据发送成功，大小: \(audioData.count) bytes")
            }
        }
    }
    
    func sendEndMessage() {
        guard isConnected else { 
            logger.websocket("WebSocket 未连接，无法发送结束消息")
            return 
        }
        
        logger.websocketSend("结束消息", size: 0)
        
        let endMessage = createEndMessage()
        logger.logDataPacket(direction: "发送", type: "结束消息", data: endMessage)
        
        webSocketTask?.send(.data(endMessage)) { error in
            if let error = error {
                self.logger.websocketError("发送结束消息失败: \(error.localizedDescription)")
            } else {
                self.logger.websocket("录音结束信号发送成功")
                // 重置录音状态
                self.hasStartedRecording = false
            }
        }
    }
    
    func startRecording() {
        guard isConnected else {
            logger.websocketError("WebSocket未连接,无法开始录音")
            return
        }
        
        guard !hasStartedRecording else {
            logger.websocket("录音已经开始，跳过重复的初始请求")
            return
        }
        
        logger.websocket("开始录音，发送初始请求")
        hasStartedRecording = true
        sendInitialRequest()
    }
    
    // MARK: - Private Methods
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    private func generateConnectId() {
        connectId = UUID().uuidString
    }
    
    // MARK: - GZIP Compression/Decompression
    
    private func gzipCompress(_ data: Data) -> Data? {
        return data.withUnsafeBytes { bytes in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count * 2)
            defer { buffer.deallocate() }
            
            let compressedSize = compression_encode_buffer(
                buffer, data.count * 2,
                bytes.bindMemory(to: UInt8.self).baseAddress!, data.count,
                nil, COMPRESSION_ZLIB
            )
            
            guard compressedSize > 0 else { return nil }
            return Data(bytes: buffer, count: compressedSize)
        }
    }
    
    private func gzipDecompress(_ data: Data) -> Data? {
        return data.withUnsafeBytes { bytes in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count * 4)
            defer { buffer.deallocate() }
            
            let decompressedSize = compression_decode_buffer(
                buffer, data.count * 4,
                bytes.bindMemory(to: UInt8.self).baseAddress!, data.count,
                nil, COMPRESSION_ZLIB
            )
            
            guard decompressedSize > 0 else { return nil }
            return Data(bytes: buffer, count: decompressedSize)
        }
    }
    
    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.logger.websocket("收到WebSocket消息")
                self?.handleReceivedMessage(message)
                self?.startReceiving() // 继续接收下一条消息
            case .failure(let error):
                self?.logger.websocketError("接收消息失败: \(error.localizedDescription)")
                self?.onError?(error)
            }
        }
    }
    
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            logger.websocketReceive("二进制数据", size: data.count)
            logger.logDataPacket(direction: "接收", type: "二进制消息", data: data)
            handleBinaryMessage(data)
        case .string(let text):
            logger.websocketReceive("文本消息", size: text.count, content: text)
        @unknown default:
            logger.websocket("收到未知类型消息")
        }
    }
    
    private func handleBinaryMessage(_ data: Data) {
        // 详细记录接收到的二进制数据
        logger.websocket("=== 接收到二进制消息 ===")
        logger.websocket("消息总长度: \(data.count) 字节")
        logger.websocket("完整消息(十六进制): \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        // 解析火山引擎二进制协议
        guard data.count >= 8 else { 
            logger.websocketError("二进制消息长度不足，需要至少8字节，实际: \(data.count)字节")
            return 
        }
        
        let header = data.prefix(4)
        let headerBytes = Array(header)
        
        // 解析协议头
        let protocolVersion = (headerBytes[0] & 0xF0) >> 4
        let headerSize = (headerBytes[0] & 0x0F) * 4
        let messageType = (headerBytes[1] & 0xF0) >> 4
        let messageFlags = headerBytes[1] & 0x0F
        let serializationMethod = (headerBytes[2] & 0xF0) >> 4
        let compression = headerBytes[2] & 0x0F
        
        // 解析payload size (4 bytes, big-endian)
        let payloadSizeData = data.subdata(in: 4..<8)
        let payloadSize = payloadSizeData.withUnsafeBytes { UInt32(bigEndian: $0.load(as: UInt32.self)) }
        
        logger.websocket("=== 解析协议头 ===")
        logger.websocket("协议头(4字节): \(header.map { String(format: "%02x", $0) }.joined(separator: " "))")
        logger.websocket("Payload大小(4字节): \(payloadSizeData.map { String(format: "%02x", $0) }.joined(separator: " "))")
        logger.websocket("解析结果 - 版本: \(protocolVersion), 头大小: \(headerSize), 消息类型: \(messageType), 标志: \(messageFlags), 序列化: \(serializationMethod), 压缩: \(compression), payload大小: \(payloadSize)")
        
        // 检查是否是服务端响应 (messageType = 9)
        if messageType == 9 {
            logger.websocket("收到服务端响应消息")
            let payloadStart = Int(headerSize) + 4 // header + payload size
            if data.count >= payloadStart + Int(payloadSize) {
                let payload = data.subdata(in: payloadStart..<(payloadStart + Int(payloadSize)))
                
                if serializationMethod == 1 { // JSON 格式
                    logger.websocket("解析JSON响应，payload大小: \(payload.count)字节")
                    parseJSONResponse(payload)
                } else {
                    logger.websocket("不支持的序列化方法: \(serializationMethod)")
                }
            } else {
                logger.websocketError("payload数据不完整，期望: \(payloadStart + Int(payloadSize))字节，实际: \(data.count)字节")
            }
        } else if messageType == 15 { // 错误消息
            logger.websocketError("收到服务端错误消息，类型: \(messageType)")
        } else {
            logger.websocket("收到其他类型消息: \(messageType)")
        }
    }
    
    private func parseJSONResponse(_ data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                logger.logAPIResponse(endpoint: "WebSocket", response: "\(json)")
                
                // 解析火山引擎大模型API识别结果
                if let result = json["result"] as? [String: Any] {
                    logger.websocket("解析识别结果: \(result)")
                    
                    // 检查是否有文本结果
                    if let text = result["text"] as? String, !text.isEmpty {
                        logger.websocket("识别到文本: \(text)")
                        DispatchQueue.main.async {
                            self.onRecognitionResult?(text)
                        }
                    }
                    
                    // 检查是否是最终结果
                    if let isFinal = result["is_final"] as? Bool, isFinal {
                        logger.websocket("收到最终识别结果")
                    }
                }
                
                // 检查错误信息
                if let error = json["error"] as? [String: Any] {
                    let errorCode = error["code"] as? Int ?? -1
                    let message = error["message"] as? String ?? "未知错误"
                    let errorType = error["type"] as? String ?? "未知类型"
                    
                    logger.websocketError("API返回详细错误信息:")
                    logger.websocketError("  - 错误代码: \(errorCode)")
                    logger.websocketError("  - 错误类型: \(errorType)")
                    logger.websocketError("  - 错误消息: \(message)")
                    logger.websocketError("  - 完整错误对象: \(error)")
                    
                    DispatchQueue.main.async {
                        let userInfo: [String: Any] = [
                            NSLocalizedDescriptionKey: message,
                            "errorCode": errorCode,
                            "errorType": errorType,
                            "fullError": error
                        ]
                        self.onError?(NSError(domain: "VolcanoAPIError", code: errorCode, userInfo: userInfo))
                    }
                }
            }
        } catch {
            logger.websocketError("解析JSON响应失败: \(error.localizedDescription)")
        }
    }
    
    private func sendInitialRequest() {
        logger.websocket("发送初始化请求")
        let requestData = createInitialRequest()
        logger.logDataPacket(direction: "发送", type: "初始化请求", data: requestData)
        
        webSocketTask?.send(.data(requestData)) { [weak self] error in
            if let error = error {
                self?.logger.websocketError("发送初始化请求失败: \(error.localizedDescription)")
                // 错误已通过logger.websocketError记录
                self?.onError?(error)
            } else {
                self?.logger.websocket("初始请求已发送")
                // 连接状态已在didOpenWithProtocol中设置
            }
        }
    }
    
    private func createInitialRequest() -> Data {
        guard let config = configManager.getVolcanoAPIConfig(),
              let audioConfig = configManager.getAudioConfig() else {
            logger.error("无法获取配置信息")
            return Data()
        }
        
        // 调试协议头构造
        debugProtocolHeader()
        
        // 构建v3大模型API初始请求参数 - 与参考实现保持一致
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
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestParams)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            logger.websocket("发送JSON: \(jsonString)")
            
            // 使用专门的full client request格式
            return createFullClientRequest(payload: jsonData)
        } catch {
            logger.error("创建初始请求失败: \(error.localizedDescription)")
            return Data()
        }
    }
    
    // 调试协议头构造的辅助方法
    private func debugProtocolHeader() {
        logger.websocket("=== 调试协议头构造 ===")
        
        // 测试Full Client Request头
        let fullRequestHeader = VolcanoProtocolHeader(
            messageType: .fullClientRequest,
            messageFlags: .normal,
            serializationMethod: .json,
            compressionMethod: .none
        )
        let fullRequestData = fullRequestHeader.toData()
        logger.websocket("Full Client Request头: \(fullRequestData.map { String(format: "%02x", $0) }.joined(separator: " "))")
        logger.websocket("  - 协议版本: \(fullRequestHeader.protocolVersion) (0b\(String(fullRequestHeader.protocolVersion, radix: 2)))")
        logger.websocket("  - 头部大小: \(fullRequestHeader.headerSize) (0b\(String(fullRequestHeader.headerSize, radix: 2)))")
        logger.websocket("  - 消息类型: \(fullRequestHeader.messageType.rawValue) (0b\(String(fullRequestHeader.messageType.rawValue, radix: 2)))")
        logger.websocket("  - 消息标志: \(fullRequestHeader.messageFlags.rawValue) (0b\(String(fullRequestHeader.messageFlags.rawValue, radix: 2)))")
        logger.websocket("  - 序列化方法: \(fullRequestHeader.serializationMethod.rawValue) (0b\(String(fullRequestHeader.serializationMethod.rawValue, radix: 2)))")
        logger.websocket("  - 压缩方法: \(fullRequestHeader.compressionMethod.rawValue) (0b\(String(fullRequestHeader.compressionMethod.rawValue, radix: 2)))")
        
        // 测试Audio Only Request头
        let audioOnlyHeader = VolcanoProtocolHeader(
            messageType: .audioOnlyRequest,
            messageFlags: .normal,
            serializationMethod: .none,
            compressionMethod: .none
        )
        let audioOnlyData = audioOnlyHeader.toData()
        logger.websocket("Audio Only Request头: \(audioOnlyData.map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        // 测试UInt32字节转换
        let testSize: UInt32 = 1234
        let testBytes = testSize.bigEndianBytes
        logger.websocket("UInt32(\(testSize))大端字节: \(testBytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
    }
    
    // 严格按照官方文档的full client request格式：Header + Payload size + Payload
    private func createFullClientRequest(payload: Data) -> Data {
        // 使用结构化的协议头 - 与参考实现保持一致
        let header = VolcanoProtocolHeader(
            messageType: .fullClientRequest,
            messageFlags: .normal,
            serializationMethod: .json,
            compressionMethod: .none  // 不使用压缩，与参考实现一致
        )
        
        var messageData = Data()
        
        // 添加协议头（4字节）
        let headerData = header.toData()
        messageData.append(headerData)
        
        // 添加payload大小（4字节，大端序）
        let payloadSize = UInt32(payload.count)
        let payloadSizeBytes = payloadSize.bigEndianBytes
        messageData.append(contentsOf: payloadSizeBytes)
        
        // 添加JSON payload（不压缩）
        messageData.append(payload)
        
        // 详细的二进制数据日志记录
        logger.websocket("=== 构造Full Client Request ===")
        logger.websocket("协议头(4字节): \(headerData.map { String(format: "%02x", $0) }.joined(separator: " "))")
        logger.websocket("Payload大小(4字节): \(payloadSizeBytes.map { String(format: "%02x", $0) }.joined(separator: " ")) (值: \(payloadSize))")
        logger.websocket("JSON Payload(\(payload.count)字节): \(String(data: payload, encoding: .utf8) ?? "无法解析为UTF-8")")
        logger.websocket("完整消息(\(messageData.count)字节): \(messageData.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))\(messageData.count > 32 ? "..." : "")")
        
        return messageData
    }
    
    private func createAudioMessage(_ audioData: Data) -> Data {
        // 根据官方文档，audio only request使用简化格式：Header + Payload size (4B) + Payload
        return createAudioOnlyMessage(audioData)
    }
    
    private func createAudioOnlyMessage(_ audioData: Data) -> Data {
        // 使用结构化的协议头 - audio only request
        let header = VolcanoProtocolHeader(
            messageType: .audioOnlyRequest,
            messageFlags: .normal,
            serializationMethod: .none,  // 二进制序列化
            compressionMethod: .none     // 不使用压缩，与参考实现一致
        )
        
        var messageData = Data()
        
        // 添加协议头（4字节）
        messageData.append(header.toData())
        
        // 添加payload大小（4字节，大端序）
        let payloadSize = UInt32(audioData.count)
        messageData.append(contentsOf: payloadSize.bigEndianBytes)
        
        // 添加音频数据（不压缩）
        messageData.append(audioData)
        
        logger.websocket("构建audio only request: header=4字节, payload大小=\(audioData.count)字节")
        
        return messageData
    }
    
    private func createEndMessage() -> Data {
        // 结束消息使用audio only格式，但payload为空，并设置lastAudioPacket标志
        let header = VolcanoProtocolHeader(
            messageType: .audioOnlyRequest,
            messageFlags: .lastAudioPacket,  // 标记为最后一个音频包
            serializationMethod: .none,
            compressionMethod: .none
        )
        
        var messageData = Data()
        
        // 添加协议头（4字节）
        messageData.append(header.toData())
        
        // Payload size为0 (4字节，大端序)
        let payloadSize: UInt32 = 0
        messageData.append(contentsOf: payloadSize.bigEndianBytes)
        
        // 无payload
        
        logger.websocket("构建结束消息: header=4字节, payload大小=0字节")
        
        return messageData
    }
    
    private func createBinaryMessage(messageType: UInt8, messageFlags: UInt8 = 0, payload: Data) -> Data {
        var message = Data()
        
        // 根据火山引擎API文档，协议格式严格按照规范：
        // 4字节固定header + [可选header扩展] + 4字节payload size + payload
        
        let protocolVersion: UInt8 = 0b0001 // V1
        // 根据API文档：初始请求使用JSON序列化(0b0001)，音频数据使用二进制序列化(0b0000)
        let serializationMethod: UInt8
        if messageType == 1 { // 初始请求使用JSON序列化
            serializationMethod = 0b0001
        } else { // 音频数据和结束消息使用二进制序列化
            serializationMethod = 0b0000
        }
        // 初始请求 (messageType == 1) 和音频数据 (messageType == 0b0010) 都使用 GZIP 压缩，与官方 Python 示例保持一致
        let compression: UInt8
        if messageType == 1 || messageType == 0b0010 {
            compression = 0b0001 // GZIP
        } else {
            compression = 0b0000 // 不压缩
        }
        
        // 检查是否需要序列号（header扩展）
        let hasSequenceNumber = (messageFlags == 0b0001 || messageFlags == 0b0011)
        // Python示例中header size固定为1（表示4字节header），序列号单独添加
        let headerSize: UInt8 = 0b0001 // 固定为1，表示4字节header
        
        // 构建4字节固定header（与Python示例完全一致）
        let byte0 = (protocolVersion << 4) | headerSize
        let byte1 = (messageType << 4) | messageFlags
        let byte2 = (serializationMethod << 4) | compression
        let byte3: UInt8 = 0 // Reserved
        
        message.append(byte0)
        message.append(byte1)
        message.append(byte2)
        message.append(byte3)
        
        // 如果需要序列号，在header后添加4字节序列号（与Python示例一致）
        if hasSequenceNumber {
            let currentSeq: Int32
            if messageFlags == 0b0011 { // NEG_WITH_SEQUENCE (最后一包)
                currentSeq = -sequenceNumber
            } else {
                currentSeq = sequenceNumber
            }
            
            let seqBytes = withUnsafeBytes(of: currentSeq.bigEndian) { Data($0) }
            message.append(seqBytes)
            
            // 递增序列号
            sequenceNumber += 1
        }
        
        // 处理payload压缩
        var finalPayload = payload
        if !payload.isEmpty && compression == 0b0001 {
            if let compressedPayload = gzipCompress(payload) {
                finalPayload = compressedPayload
                logger.websocket("Payload压缩: \(payload.count) -> \(compressedPayload.count) bytes")
            } else {
                logger.warning("Payload压缩失败，使用原始数据")
            }
        }
        
        // Payload size (4 bytes, big-endian unsigned integer)
        let payloadSize = UInt32(finalPayload.count)
        let payloadSizeBytes = withUnsafeBytes(of: payloadSize.bigEndian) { Data($0) }
        message.append(payloadSizeBytes)
        
        // Payload
        message.append(finalPayload)
        
        let seqInfo = hasSequenceNumber ? ", 序列号=\(hasSequenceNumber ? (messageFlags == 0b0011 ? -sequenceNumber + 1 : sequenceNumber - 1) : 0)" : ""
        logger.websocket("构建二进制消息: 类型=\(messageType), 标志=\(messageFlags), header大小=\(headerSize*4)字节\(seqInfo), payload大小=\(finalPayload.count)")
        
        return message
    }
    
    deinit {
        disconnect()
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketManager: URLSessionWebSocketDelegate {
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logger.websocketConnection("WebSocket连接已建立")
        logger.info("WebSocket连接成功，协议: \(`protocol` ?? "未知")")
        isConnected = true
        onConnectionStatusChanged?(true)
        
        // 连接建立后开始接收消息
        logger.websocket("开始接收消息")
        startReceiving()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "无原因"
        logger.websocketConnection("WebSocket连接已关闭")
        logger.warning("WebSocket连接关闭，代码: \(closeCode.rawValue)，原因: \(reasonString)")
        isConnected = false
        hasStartedRecording = false
        onConnectionStatusChanged?(false)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            logger.websocketError("WebSocket任务完成时发生错误: \(error.localizedDescription)")
            logger.error("WebSocket任务错误: \(error)")
            isConnected = false
            hasStartedRecording = false
            onConnectionStatusChanged?(false)
            onError?(error)
        }
    }
}