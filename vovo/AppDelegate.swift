//
//  AppDelegate.swift
//  vovo
//
//  Created by Assistant on 2024.
//

import Cocoa
import AVFoundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private let logger = Logger.shared
    
    var statusBarManager: StatusBarManager?
    var permissionManager: PermissionManager?
    var audioRecordingManager: AudioRecordingManager?
    var webSocketManager: WebSocketManager?
    var hotKeyManager: HotKeyManager?
    var textInsertionManager: TextInsertionManager?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 初始化各个管理器
        setupManagers()
        
        // 检查权限
        checkPermissions()
        
        // 设置状态栏
        setupStatusBar()
        
        // 注册全局快捷键
        setupGlobalHotKey()
        
        logger.info("vovo 应用启动完成")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // 清理资源
        hotKeyManager?.unregisterHotKey()
        audioRecordingManager?.stopRecording()
        webSocketManager?.disconnect()
        logger.info("vovo 应用即将退出")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 防止应用在 Dock 中被点击时创建新窗口
        return false
    }
    
    // MARK: - Setup Methods
    
    private func setupManagers() {
        permissionManager = PermissionManager()
        audioRecordingManager = AudioRecordingManager()
        webSocketManager = WebSocketManager()
        hotKeyManager = HotKeyManager()
        textInsertionManager = TextInsertionManager()
        statusBarManager = StatusBarManager()
        
        // 设置录音完成回调
        audioRecordingManager?.onRecordingComplete = { [weak self] audioData in
            self?.handleRecordingComplete(audioData: audioData)
        }
        
        // 设置实时音频数据回调
        audioRecordingManager?.onAudioData = { [weak self] (audioData: Data) in
            self?.handleRealtimeAudioData(audioData: audioData)
        }
        
        // 设置语音识别结果回调
        webSocketManager?.onRecognitionResult = { [weak self] text in
            self?.handleRecognitionResult(text: text)
        }
        
        // 设置快捷键回调
        hotKeyManager?.onHotKeyPressed = { [weak self] in
            self?.handleHotKeyPressed()
        }
    }
    
    private func checkPermissions() {
        permissionManager?.checkAllPermissions { [weak self] allGranted in
            DispatchQueue.main.async {
                if allGranted {
                    self?.logger.success("所有权限已授予")
                } else {
                    self?.logger.warning("部分权限未授予，请在系统设置中手动开启")
                    self?.showPermissionAlert()
                }
            }
        }
    }
    
    private func setupStatusBar() {
        statusBarManager?.setup()
        statusBarManager?.onStartRecording = { [weak self] in
            self?.startRecording()
        }
        statusBarManager?.onStopRecording = { [weak self] in
            self?.stopRecording()
        }
        statusBarManager?.onQuit = {
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func setupGlobalHotKey() {
        hotKeyManager?.registerHotKey()
    }
    
    // MARK: - Event Handlers
    
    private func handleHotKeyPressed() {
        if audioRecordingManager?.isRecording == true {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard let permissionManager = permissionManager,
              permissionManager.hasMicrophonePermission() else {
            showPermissionAlert()
            return
        }
        
        statusBarManager?.updateRecordingStatus(isRecording: true)
        
        // 先连接WebSocket，然后开始录音并发送初始请求
        webSocketManager?.connect()
        
        // 延迟一点时间确保WebSocket连接建立
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.webSocketManager?.startRecording()
            self?.audioRecordingManager?.startRecording()
        }
        
        logger.audio("开始录音")
    }
    
    private func stopRecording() {
        statusBarManager?.updateRecordingStatus(isRecording: false)
        audioRecordingManager?.stopRecording()
        logger.audio("停止录音")
    }
    
    private func handleRecordingComplete(audioData: Data) {
        // 录音完成时发送结束消息
        webSocketManager?.sendEndMessage()
    }
    
    private func handleRealtimeAudioData(audioData: Data) {
        // 实时发送音频数据到火山引擎 API
        webSocketManager?.sendAudioData(audioData)
    }
    
    private func handleRecognitionResult(text: String) {
        // 将识别结果插入到当前光标位置
        textInsertionManager?.insertText(text)
        logger.info("识别结果: \(text)")
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "权限不足"
        alert.informativeText = "vovo 需要麦克风和辅助功能权限才能正常工作。请在系统设置中授予相应权限。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 打开系统设置
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}