//
//  HotKeyManager.swift
//  vovo
//
//  Created by Assistant on 2024.
//

import Cocoa

class HotKeyManager {
    
    private var globalMonitor: Any?
    private let logger = Logger.shared
    
    var onHotKeyPressed: (() -> Void)?
    
    init() {
        // 初始化热键管理器
    }
    
    // MARK: - Public Methods
    
    func registerHotKey() {
        // 使用NSEvent监听全局热键 Command+Shift+Space
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 49 { // 49 是空格键
                self?.onHotKeyPressed?()
            }
        }
        
        if globalMonitor != nil {
            logger.success("全局热键注册成功: Command+Shift+Space")
        } else {
            logger.error("全局热键注册失败")
        }
    }
    
    func unregisterHotKey() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
            logger.info("全局热键注销成功")
        }
    }
    
    // MARK: - Private Methods
    
    deinit {
        unregisterHotKey()
    }
}