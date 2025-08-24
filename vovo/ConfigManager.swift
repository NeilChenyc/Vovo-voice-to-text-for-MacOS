//
//  ConfigManager.swift
//  vovo
//
//  Created by Assistant on 2024.
//

import Foundation
import AVFoundation

// MARK: - Configuration Models

struct VolcanoAPIConfig: Codable {
    let appKey: String
    let accessKey: String
    let resourceId: String
    let cluster: String
    let websocketURL: String
    let uid: String
    
    init(appKey: String, accessKey: String, resourceId: String, cluster: String, websocketURL: String) {
        self.appKey = appKey
        self.accessKey = accessKey
        self.resourceId = resourceId
        self.cluster = cluster
        self.websocketURL = websocketURL
        self.uid = "vovo_user_\(UUID().uuidString.prefix(8))"
    }
}

struct AudioConfig: Codable {
    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int
    let format: String
}

struct AppSettings: Codable {
    let autoStart: Bool
    let showInDock: Bool
    let enableNotifications: Bool
    let hotKeyEnabled: Bool
}

struct NetworkConfig: Codable {
    let connectTimeout: TimeInterval
    let requestTimeout: TimeInterval
}

struct RecordingConfig: Codable {
    let maxDuration: TimeInterval
    let silenceThreshold: Float
}

struct ConfigFile: Codable {
    let volcanoAPI: VolcanoAPIConfigFile
    let audio: AudioConfig
    let app: AppSettings
    let network: NetworkConfig
    let recording: RecordingConfig
}

struct VolcanoAPIConfigFile: Codable {
    let appKey: String
    let accessKey: String
    let resourceId: String
    let cluster: String
    let websocketURL: String
}

// MARK: - Configuration Manager

class ConfigManager {
    
    static let shared = ConfigManager()
    private let logger = Logger.shared
    
    // MARK: - Configuration Properties
    
    private var configFile: ConfigFile?
    private var volcanoAPIConfig: VolcanoAPIConfig?
    private let configFileName = "config.json"
    
    private init() {
        logger.config("初始化ConfigManager")
        loadConfiguration()
        logger.config("配置管理器初始化完成")
        printConfigurationInfo()
    }
    
    // MARK: - Configuration Loading
    
    private func loadConfiguration() {
        logger.config("开始加载配置文件")
        
        guard let configPath = getConfigFilePath() else {
            logger.warning("无法找到配置文件路径")
            createDefaultConfigFile()
            return
        }
        
        logger.config("配置文件路径: \(configPath)")
        
        do {
            let configData = try Data(contentsOf: URL(fileURLWithPath: configPath))
            logger.config("配置文件数据读取成功，大小: \(configData.count) bytes")
            
            configFile = try JSONDecoder().decode(ConfigFile.self, from: configData)
            logger.config("配置文件JSON解析成功")
            
            // 创建 VolcanoAPIConfig 实例
            if let volcanoAPIConfigFile = configFile?.volcanoAPI {
                volcanoAPIConfig = VolcanoAPIConfig(
                    appKey: volcanoAPIConfigFile.appKey,
                    accessKey: volcanoAPIConfigFile.accessKey,
                    resourceId: volcanoAPIConfigFile.resourceId,
                    cluster: volcanoAPIConfigFile.cluster,
                    websocketURL: volcanoAPIConfigFile.websocketURL
                )
                logger.config("VolcanoAPIConfig实例创建成功")
            }
            
            logger.success("配置文件加载成功")
        } catch {
            logger.error("配置文件加载失败: \(error.localizedDescription)")
            createDefaultConfigFile()
        }
    }
    
    private func getConfigFilePath() -> String? {
        guard let bundlePath = Bundle.main.resourcePath else { return nil }
        return "\(bundlePath)/\(configFileName)"
    }
    
    private func createDefaultConfigFile() {
        logger.config("开始创建默认配置文件")
        logger.warning("配置文件不存在或损坏，将使用默认配置")
        
        // 这里可以创建默认配置，但在实际应用中通常由用户配置
        let defaultConfig = ConfigFile(
            volcanoAPI: VolcanoAPIConfigFile(
                appKey: "YOUR_APP_KEY_HERE",
                accessKey: "YOUR_ACCESS_KEY_HERE",
                resourceId: "volc.bigasr.sauc.duration",
                cluster: "volc_asr_common",
                websocketURL: "wss://openspeech.bytedance.com/api/v2/asr"
            ),
            audio: AudioConfig(
                sampleRate: 16000,
                channels: 1,
                bitsPerSample: 16,
                format: "pcm"
            ),
            app: AppSettings(
                autoStart: false,
                showInDock: false,
                enableNotifications: true,
                hotKeyEnabled: true
            ),
            network: NetworkConfig(
                connectTimeout: 10.0,
                requestTimeout: 30.0
            ),
            recording: RecordingConfig(
                maxDuration: 60.0,
                silenceThreshold: -50.0
            )
        )
        
        configFile = defaultConfig
        volcanoAPIConfig = VolcanoAPIConfig(
            appKey: defaultConfig.volcanoAPI.appKey,
            accessKey: defaultConfig.volcanoAPI.accessKey,
            resourceId: defaultConfig.volcanoAPI.resourceId,
            cluster: defaultConfig.volcanoAPI.cluster,
            websocketURL: defaultConfig.volcanoAPI.websocketURL
        )
        
        logger.config("默认配置文件创建完成")
        logger.info("请在config.json中配置正确的API密钥")
    }
    
    // MARK: - Public Methods
    
    /// 获取火山引擎 API 配置
    func getVolcanoAPIConfig() -> VolcanoAPIConfig? {
        return volcanoAPIConfig
    }
    
    /// 获取应用设置
    func getAppSettings() -> AppSettings? {
        return configFile?.app
    }
    
    /// 获取音频配置
    func getAudioConfig() -> AudioConfig? {
        return configFile?.audio
    }
    
    /// 验证配置是否有效
    func validateConfiguration() -> Bool {
        logger.config("开始验证配置有效性")
        
        guard let config = getVolcanoAPIConfig() else {
            logger.error("无法获取API配置")
            return false
        }
        
        // 检查必要的配置项是否为空或默认值
        if config.appKey == "YOUR_APP_KEY_HERE" || config.appKey.isEmpty {
            logger.warning("AppKey 未配置或使用默认值")
            return false
        }
        
        if config.accessKey == "YOUR_ACCESS_KEY_HERE" || config.accessKey.isEmpty {
            logger.warning("AccessKey 未配置或使用默认值")
            return false
        }
        
        if config.resourceId.isEmpty {
            logger.warning("ResourceId 未配置")
            return false
        }
        
        logger.success("配置验证通过")
        logger.config("API配置: AppKey=\(config.appKey.prefix(8))..., ResourceId=\(config.resourceId)")
        return true
    }
    
    /// 获取 WebSocket 连接参数
    func getWebSocketParameters() -> [String: Any]? {
        guard let config = getVolcanoAPIConfig(),
              let audioConfig = getAudioConfig() else {
            return nil
        }
        
        return [
            "appkey": config.appKey,
            "token": config.accessKey,
            "cluster": config.cluster,
            "user_id": config.uid,
            "resource_id": config.resourceId,
            "format": audioConfig.format,
            "rate": audioConfig.sampleRate,
            "channel": audioConfig.channels,
            "bits": audioConfig.bitsPerSample,
            "codec": "raw",
            "language": "zh-CN",
            "show_utterances": true,
            "result_type": "full",
            "version": "v2"
        ]
    }
    
    /// 打印配置信息（用于调试）
    private func printConfigurationInfo() {
        logger.config("开始打印配置信息")
        
        guard let config = getVolcanoAPIConfig(),
              let settings = getAppSettings(),
              let audioConfig = getAudioConfig() else {
            logger.warning("配置信息不完整，无法打印详细信息")
            return
        }
        
        logger.info("=== vovo 配置信息 ===")
        logger.info("WebSocket URL: \(config.websocketURL)")
        logger.info("Resource ID: \(config.resourceId)")
        logger.info("Cluster: \(config.cluster)")
        logger.info("User ID: \(config.uid)")
        logger.info("音频格式: \(audioConfig.format)")
        logger.info("采样率: \(audioConfig.sampleRate) Hz")
        logger.info("声道数: \(audioConfig.channels)")
        logger.info("位深: \(audioConfig.bitsPerSample) bit")
        logger.info("=== 应用设置 ===")
        logger.info("自动启动: \(settings.autoStart)")
        logger.info("显示在 Dock: \(settings.showInDock)")
        logger.info("启用通知: \(settings.enableNotifications)")
        logger.info("快捷键启用: \(settings.hotKeyEnabled)")
        logger.config("配置信息打印完成")
    }
    
    // MARK: - Configuration Helpers
    
    /// 获取用于认证的签名参数
    func getAuthParameters() -> [String: String]? {
        guard let config = getVolcanoAPIConfig() else {
            return nil
        }
        
        let timestamp = String(Int(Date().timeIntervalSince1970))
        
        return [
            "appkey": config.appKey,
            "token": config.accessKey,
            "timestamp": timestamp,
            "cluster": config.cluster,
            "user_id": config.uid
        ]
    }
    
    /// 检查是否需要更新配置
    func needsConfigurationUpdate() -> Bool {
        // 在硬编码模式下，总是返回 false
        // 在实际应用中，这里可以检查配置文件的时间戳等
        return false
    }
    
    /// 获取配置状态描述
    func getConfigurationStatus() -> String {
        if validateConfiguration() {
            return "配置正常"
        } else {
            return "配置需要更新 - 请在代码中设置正确的 API 密钥"
        }
    }
}

// MARK: - Configuration Extensions

extension ConfigManager {
    
    /// 获取音频录制配置
    func getAudioRecordingSettings() -> [String: Any]? {
        guard let audioConfig = getAudioConfig() else {
            return nil
        }
        
        return [
            AVSampleRateKey: audioConfig.sampleRate,
            AVNumberOfChannelsKey: audioConfig.channels,
            AVLinearPCMBitDepthKey: audioConfig.bitsPerSample,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVFormatIDKey: kAudioFormatLinearPCM
        ]
    }
    
    /// 获取 WebSocket 连接超时配置
    func getNetworkTimeouts() -> (connect: TimeInterval, request: TimeInterval)? {
        guard let networkConfig = configFile?.network else {
            return nil
        }
        return (connect: networkConfig.connectTimeout, request: networkConfig.requestTimeout)
    }
    
    /// 获取录音相关配置
    func getRecordingSettings() -> (maxDuration: TimeInterval, silenceThreshold: Float)? {
        guard let recordingConfig = configFile?.recording else {
            return nil
        }
        return (maxDuration: recordingConfig.maxDuration, silenceThreshold: recordingConfig.silenceThreshold)
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension ConfigManager {
    
    /// 打印详细的调试信息
    func printDebugInfo() {
        logger.config("开始打印DEBUG配置详情")
        
        guard let config = getVolcanoAPIConfig() else {
            logger.error("无法获取API配置")
            return
        }
        
        logger.config("AppKey: \(config.appKey.prefix(10))...")
        logger.config("AccessKey: \(config.accessKey.prefix(10))...")
        
        if let wsParams = getWebSocketParameters() {
            logger.config("WebSocket 参数:")
            for (key, value) in wsParams {
                logger.config("  \(key): \(value)")
            }
        }
        
        if let authParams = getAuthParameters() {
            logger.config("认证参数:")
            for (key, value) in authParams {
                logger.config("  \(key): \(value)")
            }
        }
        
        logger.config("配置状态: \(getConfigurationStatus())")
        logger.config("DEBUG配置详情打印完成")
    }
}
#endif