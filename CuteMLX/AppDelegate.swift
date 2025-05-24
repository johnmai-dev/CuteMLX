//
//  AppDelegate.swift
//  CuteMLX
//
//  Created by John Mai on 2025/5/24.
//

import Cocoa
import AppKit
import SwiftUI

// Custom window class that allows becoming key window
class CustomKeyWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}
// Window position coordinator
class WindowCoordinator: NSObject {
    // References to all windows
    var mainContentWindow: NSWindow?
    var inputWindow: NSWindow?
    var controlButtonWindow: NSWindow?
    
    // Record relative positions
    var mainContentOffset: NSPoint = .zero
    var inputOffset: NSPoint = .zero
    var controlButtonOffset: NSPoint = .zero
    
    // For tracking dragging
    var lastDragLocation: NSPoint?
    
    // Initialize relative positions
    func setupOffsets(baseWindow: NSWindow) {
        let baseOrigin = baseWindow.frame.origin
        
        if let mainContentWindow = mainContentWindow {
            mainContentOffset = NSPoint(
                x: mainContentWindow.frame.origin.x - baseOrigin.x,
                y: mainContentWindow.frame.origin.y - baseOrigin.y
            )
        }
        
        if let inputWindow = inputWindow {
            inputOffset = NSPoint(
                x: inputWindow.frame.origin.x - baseOrigin.x,
                y: inputWindow.frame.origin.y - baseOrigin.y
            )
        }
        
        if let controlButtonWindow = controlButtonWindow {
            controlButtonOffset = NSPoint(
                x: controlButtonWindow.frame.origin.x - baseOrigin.x,
                y: controlButtonWindow.frame.origin.y - baseOrigin.y
            )
        }
    }
    
    // Move all windows
    func moveAllWindows(to newBaseOrigin: NSPoint) {
        // Move content window
        if let mainContentWindow = mainContentWindow {
            mainContentWindow.setFrameOrigin(NSPoint(
                x: newBaseOrigin.x + mainContentOffset.x,
                y: newBaseOrigin.y + mainContentOffset.y
            ))
        }
        
        // Move input window
        if let inputWindow = inputWindow {
            inputWindow.setFrameOrigin(NSPoint(
                x: newBaseOrigin.x + inputOffset.x,
                y: newBaseOrigin.y + inputOffset.y
            ))
        }
        
        // Move control button window
        if let controlButtonWindow = controlButtonWindow {
            controlButtonWindow.setFrameOrigin(NSPoint(
                x: newBaseOrigin.x + controlButtonOffset.x,
                y: newBaseOrigin.y + controlButtonOffset.y
            ))
        }
    }
    
    // Bring all windows to front, keeping same level
    func bringAllWindowsToFront() {
        // Set all windows to same level and show
        if let inputWindow = inputWindow {
            // Set input window as base level
            let baseLevel = inputWindow.level
            
            if let mainWindow = mainContentWindow {
                mainWindow.level = baseLevel
                mainWindow.orderFront(nil)
            }
            
            if let controlWindow = controlButtonWindow {
                controlWindow.level = baseLevel
                controlWindow.orderFront(nil)
            }
            
            // Make input window become key window
            inputWindow.makeKeyAndOrderFront(nil)
        }
    }
}

// AppDelegate implementation
class AppDelegate: NSObject, NSApplicationDelegate {
    // Window references
    var mainContentWindow: NSWindow!
    var inputWindow: NSWindow!
    var controlButtonWindow: NSWindow!
    
    // Window coordinator
    var windowCoordinator = WindowCoordinator()
    
    // Timer for periodically syncing window levels
    var windowSyncTimer: Timer?
    
    // LLM evaluator instance
    @MainActor
    let llmEvaluator = LLMEvaluator()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize and show all windows
        setupWindows()
        
        // Hide menu bar application icon
        NSApp.setActivationPolicy(.accessory)
        
        // Add application activation notification
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // When application is activated, ensure all windows are at same level
            self?.windowCoordinator.bringAllWindowsToFront()
        }
    }
    
    func setupWindows() {
        // Set window positions
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        
        // Calculate base position (center position)
        let centerX = screenFrame.midX
        let centerY = screenFrame.midY
        
        // Window size definitions
        let mainWindowWidth: CGFloat = 250
        let mainWindowHeight: CGFloat = 250
        let inputWindowHeight: CGFloat = 45
        let controlButtonSize: CGFloat = 80
        let spacing: CGFloat = 20
        
        // Calculate main window position (center position)
        let mainWindowX = centerX - mainWindowWidth / 2
        let mainWindowY = centerY - mainWindowHeight / 2
        
        // Calculate input window position (below main window with 20px spacing)
        let inputWindowX = mainWindowX // Align with main window left edge
        let inputWindowY = mainWindowY - spacing - inputWindowHeight
        
        // Calculate control button window position (left of input window with 20px spacing)
        let controlButtonX = inputWindowX - spacing - controlButtonSize
        let controlButtonY = inputWindowY + (inputWindowHeight - controlButtonSize) / 2 // Vertically centered
        
        // Create content window
        mainContentWindow = createWindow(
            size: CGSize(width: mainWindowWidth, height: mainWindowHeight),
            position: NSPoint(x: mainWindowX, y: mainWindowY),
            contentView: NSHostingView(rootView: MainContentView(llm: llmEvaluator))
        )
        
        // Create input window (needs to receive keyboard input)
        inputWindow = createWindow(
            size: CGSize(width: mainWindowWidth, height: inputWindowHeight),
            position: NSPoint(x: inputWindowX, y: inputWindowY),
            contentView: NSHostingView(rootView: InputView(llm: llmEvaluator)),
            canBecomeKey: true
        )
        
        // Create control button window
        controlButtonWindow = createWindow(
            size: CGSize(width: controlButtonSize, height: controlButtonSize),
            position: NSPoint(x: controlButtonX, y: controlButtonY),
            contentView: NSHostingView(rootView: ControlButtonView(llm: llmEvaluator))
        )
        
        // Configure window coordinator
        windowCoordinator.mainContentWindow = mainContentWindow
        windowCoordinator.inputWindow = inputWindow
        windowCoordinator.controlButtonWindow = controlButtonWindow
        
        // Use main content window as base window to calculate offsets
        windowCoordinator.setupOffsets(baseWindow: mainContentWindow)
        
        // Add drag monitors to draggable windows (input window doesn't need drag functionality)
        addDragMonitor(to: mainContentWindow)
        addDragMonitor(to: controlButtonWindow)
        
        // Add activation notifications for each window
        addWindowNotifications(to: mainContentWindow)
        addWindowNotifications(to: inputWindow)
        addWindowNotifications(to: controlButtonWindow)
        
        // Show all windows
        mainContentWindow.orderFront(nil)
        controlButtonWindow.orderFront(nil)
        // Make input window the key window so it can receive keyboard input
        inputWindow.makeKeyAndOrderFront(nil)
        
        // Start timer for periodic window level synchronization
        startWindowSyncTimer()
    }
    
    func createWindow(size: CGSize, position: NSPoint, contentView: NSView, canBecomeKey: Bool = false) -> NSWindow {
        let window: NSWindow
        
        if canBecomeKey {
            // For windows that need to receive keyboard input (like input window), use different style
            window = CustomKeyWindow(
                contentRect: NSRect(origin: position, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
        } else {
            // For windows that don't need keyboard input, keep original style
            window = NSWindow(
                contentRect: NSRect(origin: position, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        }
        
        // Set window properties
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .normal
        window.hasShadow = true
        window.contentView = contentView
        
        return window
    }
    
    // Add drag event monitor
    func addDragMonitor(to window: NSWindow) {
        // Create a view to receive mouse events
        let dragView = DragHandleView(frame: window.contentView?.bounds ?? .zero)
        dragView.autoresizingMask = [.width, .height]
        dragView.windowCoordinator = windowCoordinator
        
        if let contentView = window.contentView {
            // Add drag view to the bottom layer so it doesn't block other UI elements
            contentView.addSubview(dragView, positioned: .below, relativeTo: nil)
        }
    }
    
    // Add window notifications to ensure windows stay at the same level
    func addWindowNotifications(to window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // When any window is activated, bring all windows to front
            self?.windowCoordinator.bringAllWindowsToFront()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // When any window becomes main window, bring all windows to front
                         self?.windowCoordinator.bringAllWindowsToFront()
         }
     }
     
     // Start window synchronization timer
     func startWindowSyncTimer() {
         windowSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
             // Check if windows are at the same level, if not then sync
             self?.checkAndSyncWindowLevels()
         }
     }
     
     // Check and synchronize window levels
     func checkAndSyncWindowLevels() {
         guard let mainWindow = mainContentWindow,
               let inputWindow = inputWindow,
               let controlWindow = controlButtonWindow else { return }
         
         // Check if all windows are at the same level
         let mainLevel = mainWindow.level
         if inputWindow.level != mainLevel || controlWindow.level != mainLevel {
             // If not at the same level, sync them
             windowCoordinator.bringAllWindowsToFront()
         }
     }
 }

// Custom view for handling drag operations
class DragHandleView: NSView {
    var windowCoordinator: WindowCoordinator?
    var initialMouseLocation: NSPoint?
    var initialWindowOrigin: NSPoint?
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Entire area can be dragged (since input window no longer uses drag functionality)
        return self
    }
    
    override func mouseDown(with event: NSEvent) {
        // Record initial mouse screen position and window position
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowOrigin = window?.frame.origin
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let initialMouseLocation = initialMouseLocation,
              let initialWindowOrigin = initialWindowOrigin,
              let windowCoordinator = windowCoordinator else { return }
        
        // Get current mouse screen position
        let currentMouseLocation = NSEvent.mouseLocation
        
        // Calculate mouse movement distance
        let deltaX = currentMouseLocation.x - initialMouseLocation.x
        let deltaY = currentMouseLocation.y - initialMouseLocation.y
        
        // Calculate new base origin position
        let newBaseOrigin = NSPoint(
            x: initialWindowOrigin.x + deltaX,
            y: initialWindowOrigin.y + deltaY
        )
        
        // Move all windows
        windowCoordinator.moveAllWindows(to: newBaseOrigin)
        
        // Ensure all windows stay at the same level
        windowCoordinator.bringAllWindowsToFront()
    }
}
