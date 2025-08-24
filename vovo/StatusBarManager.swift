//
//  StatusBarManager.swift
//  vovo
//
//  Created by Assistant on 2024.
//

import Cocoa

class StatusBarManager {
    
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var isRecording = false
    private let logger = Logger.shared
    
    // 回调闭包
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onQuit: (() -> Void)?
    
    // 菜单项
    private var recordingMenuItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?
    
    // MARK: - Public Methods
    
    func setup() {
        // 创建状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // 设置初始图标和标题
        updateStatusBarAppearance()
        
        // 创建菜单
        setupMenu()
        
        // 设置菜单
        statusItem?.menu = menu
        
        logger.info("状态栏已设置")
    }
    
    func updateRecordingStatus(isRecording: Bool) {
        self.isRecording = isRecording
        
        DispatchQueue.main.async {
            self.updateStatusBarAppearance()
            self.updateMenuItems()
        }
    }
    
    func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    // MARK: - Private Methods
    
    private func setupMenu() {
        menu = NSMenu()
        
        // 状态显示项
        statusMenuItem = NSMenuItem(title: "vovo - 就绪", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu?.addItem(statusMenuItem!)
        
        menu?.addItem(NSMenuItem.separator())
        
        // 录音控制项
        recordingMenuItem = NSMenuItem(
            title: "开始录音 (⌘⇧Space)",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        recordingMenuItem?.target = self
        menu?.addItem(recordingMenuItem!)
        
        menu?.addItem(NSMenuItem.separator())
        
        // 权限检查项
        let permissionMenuItem = NSMenuItem(
            title: "检查权限",
            action: #selector(checkPermissions),
            keyEquivalent: ""
        )
        permissionMenuItem.target = self
        menu?.addItem(permissionMenuItem)
        
        // 关于项
        let aboutMenuItem = NSMenuItem(
            title: "关于 vovo",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutMenuItem.target = self
        menu?.addItem(aboutMenuItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        // 退出项
        let quitMenuItem = NSMenuItem(
            title: "退出 vovo",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitMenuItem.target = self
        menu?.addItem(quitMenuItem)
    }
    
    private func updateStatusBarAppearance() {
        guard let statusItem = statusItem else { return }
        
        if isRecording {
            // 录音状态：红色圆点图标
            statusItem.button?.title = "🔴"
            statusItem.button?.toolTip = "vovo - 正在录音"
        } else {
            // 就绪状态：麦克风图标
            statusItem.button?.title = "🎤"
            statusItem.button?.toolTip = "vovo - 就绪 (⌘⇧Space 开始录音)"
        }
    }
    
    private func updateMenuItems() {
        if isRecording {
            statusMenuItem?.title = "vovo - 正在录音..."
            recordingMenuItem?.title = "停止录音 (⌘⇧Space)"
        } else {
            statusMenuItem?.title = "vovo - 就绪"
            recordingMenuItem?.title = "开始录音 (⌘⇧Space)"
        }
    }
    
    // MARK: - Menu Actions
    
    @objc private func toggleRecording() {
        if isRecording {
            onStopRecording?()
        } else {
            onStartRecording?()
        }
    }
    
    @objc private func checkPermissions() {
        let permissionManager = PermissionManager()
        
        permissionManager.checkAllPermissions { allGranted in
            DispatchQueue.main.async {
                let alert = NSAlert()
                
                if allGranted {
                    alert.messageText = "权限检查"
                    alert.informativeText = "所有必要权限已授予，vovo 可以正常工作。"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "确定")
                } else {
                    alert.messageText = "权限不足"
                    alert.informativeText = "vovo 需要麦克风和辅助功能权限才能正常工作。请在系统设置中授予相应权限。"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "打开系统设置")
                    alert.addButton(withTitle: "取消")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        self.openSystemPreferences()
                    }
                    return
                }
                
                alert.runModal()
            }
        }
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "关于 vovo"
        alert.informativeText = """
        vovo - 智能语音转文字工具
        
        版本: 1.0.0
        
        功能特性:
        • 一键录音 (⌘⇧Space)
        • 实时语音识别
        • 自动文本插入
        • 基于火山引擎 API
        
        使用方法:
        1. 按 ⌘⇧Space 开始录音
        2. 说话完毕后再次按快捷键停止
        3. 识别结果将自动插入到光标位置
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    @objc private func quitApplication() {
        onQuit?()
    }
    
    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Visual Feedback
    
    func showRecordingFeedback() {
        // 可以在这里添加更多的视觉反馈，比如动画效果
        updateRecordingStatus(isRecording: true)
        
        // 显示通知
        showNotification(title: "vovo", message: "开始录音...")
    }
    
    func showRecognitionResult(_ text: String) {
        // 显示识别结果通知
        let truncatedText = text.count > 50 ? String(text.prefix(50)) + "..." : text
        showNotification(title: "识别完成", message: "\"\(truncatedText)\"")
    }
    
    func showError(_ error: String) {
        showNotification(title: "vovo 错误", message: error)
    }
    
    deinit {
        // 清理状态栏项
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}

// MARK: - Status Bar Animation

extension StatusBarManager {
    
    /// 开始录音动画效果
    func startRecordingAnimation() {
        guard let button = statusItem?.button else { return }
        
        // 创建脉冲动画效果
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 0.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        
        button.layer?.add(animation, forKey: "recordingPulse")
    }
    
    /// 停止录音动画效果
    func stopRecordingAnimation() {
        guard let button = statusItem?.button else { return }
        button.layer?.removeAnimation(forKey: "recordingPulse")
    }
}