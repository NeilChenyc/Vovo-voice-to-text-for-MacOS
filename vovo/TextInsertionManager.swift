//
//  TextInsertionManager.swift
//  vovo
//
//  Created by Assistant on 2024.
//

import Cocoa
import ApplicationServices
import Carbon

class TextInsertionManager {
    
    private let logger = Logger.shared
    
    init() {
        // 初始化时检查辅助功能权限
        checkAccessibilityPermission()
    }
    
    // MARK: - Public Methods
    
    /// 在当前光标位置插入文本
    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        
        // 检查辅助功能权限
        guard hasAccessibilityPermission() else {
            logger.error("缺少辅助功能权限，无法插入文本")
            showPermissionAlert()
            return
        }
        
        DispatchQueue.main.async {
            self.performTextInsertion(text)
        }
    }
    
    /// 获取当前选中的文本
    func getSelectedText() -> String? {
        guard hasAccessibilityPermission() else { return nil }
        
        // 使用 Command+C 复制选中文本到剪贴板
        let pasteboard = NSPasteboard.general
        let originalContents = pasteboard.string(forType: .string)
        
        // 发送 Command+C
        sendKeyboardShortcut(key: CGKeyCode(kVK_ANSI_C), modifiers: .maskCommand)
        
        // 等待剪贴板更新
        usleep(50000) // 50ms
        
        let selectedText = pasteboard.string(forType: .string)
        
        // 恢复原始剪贴板内容
        if let originalContents = originalContents {
            pasteboard.clearContents()
            pasteboard.setString(originalContents, forType: .string)
        }
        
        return selectedText != originalContents ? selectedText : nil
    }
    
    // MARK: - Private Methods
    
    private func performTextInsertion(_ text: String) {
        // 方法1: 使用剪贴板和粘贴
        insertTextViaClipboard(text)
        
        // 方法2: 直接模拟键盘输入（备用方案）
        // insertTextViaKeyboardEvents(text)
    }
    
    private func insertTextViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        
        // 保存当前剪贴板内容
        let originalContents = pasteboard.string(forType: .string)
        
        // 将文本放入剪贴板
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 发送 Command+V 粘贴
        sendKeyboardShortcut(key: CGKeyCode(kVK_ANSI_V), modifiers: .maskCommand)
        
        // 延迟后恢复原始剪贴板内容
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let originalContents = originalContents {
                pasteboard.clearContents()
                pasteboard.setString(originalContents, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }
    }
    
    private func insertTextViaKeyboardEvents(_ text: String) {
        // 直接模拟键盘输入每个字符
        for char in text {
            if let keyCode = getKeyCodeForCharacter(char) {
                sendKeyPress(keyCode: keyCode)
                usleep(10000) // 10ms 延迟
            } else {
                // 对于无法直接映射的字符，使用 Unicode 输入
                insertUnicodeCharacter(char)
            }
        }
    }
    
    private func sendKeyboardShortcut(key: CGKeyCode, modifiers: CGEventFlags) {
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
            return
        }
        
        keyDownEvent.flags = modifiers
        keyUpEvent.flags = modifiers
        
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
    }
    
    private func sendKeyPress(keyCode: CGKeyCode) {
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
    }
    
    private func insertUnicodeCharacter(_ character: Character) {
        let unicodeScalar = character.unicodeScalars.first?.value ?? 0
        
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
            return
        }
        
        let unicodeChar = UInt16(unicodeScalar & 0xFFFF)
        event.keyboardSetUnicodeString(stringLength: 1, unicodeString: [unicodeChar])
        event.post(tap: .cghidEventTap)
    }
    
    private func getKeyCodeForCharacter(_ character: Character) -> CGKeyCode? {
        // 基本字符到键码的映射
        let characterMap: [Character: CGKeyCode] = [
            "a": CGKeyCode(kVK_ANSI_A), "b": CGKeyCode(kVK_ANSI_B), "c": CGKeyCode(kVK_ANSI_C),
            "d": CGKeyCode(kVK_ANSI_D), "e": CGKeyCode(kVK_ANSI_E), "f": CGKeyCode(kVK_ANSI_F),
            "g": CGKeyCode(kVK_ANSI_G), "h": CGKeyCode(kVK_ANSI_H), "i": CGKeyCode(kVK_ANSI_I),
            "j": CGKeyCode(kVK_ANSI_J), "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
            "m": CGKeyCode(kVK_ANSI_M), "n": CGKeyCode(kVK_ANSI_N), "o": CGKeyCode(kVK_ANSI_O),
            "p": CGKeyCode(kVK_ANSI_P), "q": CGKeyCode(kVK_ANSI_Q), "r": CGKeyCode(kVK_ANSI_R),
            "s": CGKeyCode(kVK_ANSI_S), "t": CGKeyCode(kVK_ANSI_T), "u": CGKeyCode(kVK_ANSI_U),
            "v": CGKeyCode(kVK_ANSI_V), "w": CGKeyCode(kVK_ANSI_W), "x": CGKeyCode(kVK_ANSI_X),
            "y": CGKeyCode(kVK_ANSI_Y), "z": CGKeyCode(kVK_ANSI_Z),
            "0": CGKeyCode(kVK_ANSI_0), "1": CGKeyCode(kVK_ANSI_1), "2": CGKeyCode(kVK_ANSI_2),
            "3": CGKeyCode(kVK_ANSI_3), "4": CGKeyCode(kVK_ANSI_4), "5": CGKeyCode(kVK_ANSI_5),
            "6": CGKeyCode(kVK_ANSI_6), "7": CGKeyCode(kVK_ANSI_7), "8": CGKeyCode(kVK_ANSI_8),
            "9": CGKeyCode(kVK_ANSI_9),
            " ": CGKeyCode(kVK_Space), "\n": CGKeyCode(kVK_Return), "\t": CGKeyCode(kVK_Tab)
        ]
        
        return characterMap[character.lowercased().first ?? character]
    }
    
    // MARK: - Permission Methods
    
    private func hasAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    private func checkAccessibilityPermission() {
        if !hasAccessibilityPermission() {
            logger.warning("缺少辅助功能权限，文本插入功能将无法正常工作")
        }
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "vovo 需要辅助功能权限来插入识别的文本。请在系统设置中授予权限。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
    
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Text Processing Extensions

extension TextInsertionManager {
    
    /// 清理和格式化识别的文本
    func cleanAndFormatText(_ text: String) -> String {
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除多余的空格
        cleanedText = cleanedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // 添加适当的标点符号
        if !cleanedText.isEmpty && !cleanedText.hasSuffix(".") && !cleanedText.hasSuffix("!") && !cleanedText.hasSuffix("?") {
            // 如果文本看起来像一个完整的句子，添加句号
            if cleanedText.count > 10 {
                cleanedText += "。"
            }
        }
        
        return cleanedText
    }
    
    /// 检测当前应用程序
    func getCurrentApplication() -> String? {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            return frontmostApp.bundleIdentifier
        }
        return nil
    }
}