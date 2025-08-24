//
//  AudioRecordingManager.swift
//  vovo
//
//  Created by Assistant on 2024.
//

import AVFoundation
import Foundation

class AudioRecordingManager: NSObject {
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFormat: AVAudioFormat?
    private var audioBuffer: AVAudioPCMBuffer?
    private var recordedData = Data()
    private lazy var configManager: ConfigManager = ConfigManager.shared
    private let logger = Logger.shared
    
    var isRecording = false
    var onRecordingComplete: ((Data) -> Void)?
    var onAudioData: ((Data) -> Void)? // 实时音频数据回调
    
    override init() {
        super.init()
        setupAudioEngine()
    }
    
    // MARK: - Public Methods
    
    func startRecording() {
        guard !isRecording else { 
            logger.audio("录音已在进行中，忽略重复启动请求")
            return 
        }
        
        logger.audio("开始启动录音")
        
        do {
            logger.audio("设置音频会话")
            try setupAudioSession()
            
            logger.audio("启动音频引擎")
            try startAudioEngine()
            
            isRecording = true
            recordedData.removeAll()
            
            logger.audio("录音启动成功")
            logger.info("音频录制已开始")
        } catch {
            logger.error("录音启动失败: \(error.localizedDescription)")
            logger.error("音频录制启动错误: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { 
            logger.audio("录音未在进行中，忽略停止请求")
            return 
        }
        
        logger.audio("开始停止录音")
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        isRecording = false
        
        logger.audio("录音结束，数据大小: \(recordedData.count) 字节")
        logger.info("音频录制已停止，总数据量: \(recordedData.count) 字节")
        
        onRecordingComplete?(recordedData)
    }
    
    // MARK: - Private Methods
    
    private func setupAudioEngine() {
        logger.audio("初始化音频引擎")
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
        
        // 从配置管理器获取音频格式设置
        guard let audioConfig = configManager.getAudioConfig() else {
            logger.error("无法获取音频配置，使用默认设置")
            // 使用默认设置
            audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                       sampleRate: 16000,
                                       channels: 1,
                                       interleaved: false)
            logger.audio("使用默认音频格式: 16kHz, 单声道, PCM16")
            return
        }
        
        // 设置音频格式 - 使用配置文件中的参数
        audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                   sampleRate: Double(audioConfig.sampleRate),
                                   channels: AVAudioChannelCount(audioConfig.channels),
                                   interleaved: false)
        
        logger.audio("音频格式配置: 采样率=\(audioConfig.sampleRate)Hz, 声道数=\(audioConfig.channels), 格式=PCM16")
    }
    
    private func setupAudioSession() throws {
        // macOS doesn't require AVAudioSession configuration like iOS
        // Audio engine will handle the audio session automatically
    }
    
    private func startAudioEngine() throws {
        guard let audioEngine = audioEngine,
              let inputNode = inputNode else {
            logger.error("音频引擎组件未正确初始化")
            throw AudioRecordingError.setupFailed
        }
        
        // 获取输入节点的输出格式（硬件格式）
        let inputFormat = inputNode.outputFormat(forBus: 0)
        logger.audio("输入节点硬件格式: 采样率=\(inputFormat.sampleRate)Hz, 声道数=\(inputFormat.channelCount), 格式=\(inputFormat.commonFormat.rawValue)")
        
        // 安装音频处理 tap - 使用输入节点的原生格式
        let bufferSize: AVAudioFrameCount = 1024
        logger.audio("安装音频处理tap，缓冲区大小: \(bufferSize)")
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }
        
        logger.audio("启动音频引擎")
        try audioEngine.start()
        logger.audio("音频引擎启动成功")
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        var audioData: Data
        
        // 根据音频格式处理数据
        switch buffer.format.commonFormat {
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData?[0] else { 
                logger.error("无法获取Int16音频通道数据")
                return 
            }
            audioData = Data(bytes: channelData, count: frameLength * MemoryLayout<Int16>.size)
            
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData?[0] else { 
                logger.error("无法获取Float32音频通道数据")
                return 
            }
            // 将Float32转换为Int16
            let int16Data = UnsafeMutablePointer<Int16>.allocate(capacity: frameLength)
            defer { int16Data.deallocate() }
            
            for i in 0..<frameLength {
                let floatSample = channelData[i]
                let clampedSample = max(-1.0, min(1.0, floatSample))
                int16Data[i] = Int16(clampedSample * 32767.0)
            }
            
            audioData = Data(bytes: int16Data, count: frameLength * MemoryLayout<Int16>.size)
            
        default:
            logger.error("不支持的音频格式: \(buffer.format.commonFormat.rawValue)")
            return
        }
        
        // 暂时屏蔽音频缓冲区处理日志
        // logger.debug("处理音频缓冲区: 帧长度=\(frameLength), 格式=\(buffer.format.commonFormat.rawValue), 数据大小=\(audioData.count)字节")
        
        // 累积录音数据
        recordedData.append(audioData)
        
        // 实时音频数据回调（用于流式传输）
        onAudioData?(audioData)
        
        // 定期记录累积数据大小（每100个缓冲区记录一次）
        if recordedData.count % (audioData.count * 100) < audioData.count {
            logger.audio("累积录音数据: \(recordedData.count)字节")
        }
    }
    
    deinit {
        stopRecording()
    }
}

// MARK: - Audio Recording Error

enum AudioRecordingError: Error {
    case setupFailed
    case permissionDenied
    case recordingFailed
    
    var localizedDescription: String {
        switch self {
        case .setupFailed:
            return "音频引擎设置失败"
        case .permissionDenied:
            return "麦克风权限被拒绝"
        case .recordingFailed:
            return "录音过程中发生错误"
        }
    }
}

// MARK: - Audio Format Extensions

extension AudioRecordingManager {
    
    /// 获取 WAV 格式的音频数据
    func getWAVData() -> Data? {
        guard !recordedData.isEmpty else { return nil }
        return createWAVData(from: recordedData)
    }
    
    /// 创建 WAV 格式数据
    private func createWAVData(from pcmData: Data) -> Data {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let fileSize = dataSize + 36
        
        var wavData = Data()
        
        // RIFF Header
        wavData.append("RIFF".data(using: .ascii)!)
        var fileSizeLE = fileSize.littleEndian
        wavData.append(Data(bytes: &fileSizeLE, count: 4))
        wavData.append("WAVE".data(using: .ascii)!)
        
        // Format Chunk
        wavData.append("fmt ".data(using: .ascii)!)
        var chunkSize: UInt32 = 16
        var chunkSizeLE = chunkSize.littleEndian
        wavData.append(Data(bytes: &chunkSizeLE, count: 4))
        var audioFormat: UInt16 = 1 // PCM
        var audioFormatLE = audioFormat.littleEndian
        wavData.append(Data(bytes: &audioFormatLE, count: 2))
        var channelsLE = channels.littleEndian
        wavData.append(Data(bytes: &channelsLE, count: 2))
        var sampleRateLE = sampleRate.littleEndian
        wavData.append(Data(bytes: &sampleRateLE, count: 4))
        var byteRateLE = byteRate.littleEndian
        wavData.append(Data(bytes: &byteRateLE, count: 4))
        var blockAlignLE = blockAlign.littleEndian
        wavData.append(Data(bytes: &blockAlignLE, count: 2))
        var bitsPerSampleLE = bitsPerSample.littleEndian
        wavData.append(Data(bytes: &bitsPerSampleLE, count: 2))
        
        // Data Chunk
        wavData.append("data".data(using: .ascii)!)
        var dataSizeLE = dataSize.littleEndian
        wavData.append(Data(bytes: &dataSizeLE, count: 4))
        wavData.append(pcmData)
        
        return wavData
    }
}