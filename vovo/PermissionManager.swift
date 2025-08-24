//
//  PermissionManager.swift
//  vovo
//
//  Created by Assistant on 2024.
//

import Cocoa
import AVFoundation

class PermissionManager {
    
    // MARK: - Public Methods
    
    /// 检查所有必要权限
    func checkAllPermissions(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var microphoneGranted = false
        var accessibilityGranted = false
        
        // 检查麦克风权限
        group.enter()
        checkMicrophonePermission { granted in
            microphoneGranted = granted
            group.leave()
        }
        
        // 检查辅助功能权限
        group.enter()
        DispatchQueue.global().async {
            accessibilityGranted = self.checkAccessibilityPermission()
            group.leave()
        }
        
        group.notify(queue: .main) {
            let allGranted = microphoneGranted && accessibilityGranted
            completion(allGranted)
        }
    }
    
    /// 检查麦克风权限状态
    func hasMicrophonePermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    /// 检查辅助功能权限状态
    func hasAccessibilityPermission() -> Bool {
        return checkAccessibilityPermission()
    }
    
    // MARK: - Private Methods
    
    /// 检查并请求麦克风权限
    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            // 请求权限
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }
    
    /// 检查辅助功能权限
    private func checkAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// 请求辅助功能权限（会打开系统设置）
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    /// 打开系统设置页面
    func openSystemPreferences(for permission: PermissionType) {
        var urlString: String
        
        switch permission {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// 显示权限提示对话框
    func showPermissionAlert(for permission: PermissionType) {
        let alert = NSAlert()
        
        switch permission {
        case .microphone:
            alert.messageText = "需要麦克风权限"
            alert.informativeText = "vovo 需要访问麦克风来录制语音。请在系统设置中授予麦克风权限。"
        case .accessibility:
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "vovo 需要辅助功能权限来监听全局快捷键和插入文本。请在系统设置中授予辅助功能权限。"
        }
        
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSystemPreferences(for: permission)
        }
    }
}

// MARK: - Permission Types

enum PermissionType {
    case microphone
    case accessibility
}