import Cocoa
import Carbon.HIToolbox
import FlutterMacOS
import ServiceManagement

// 定义 Fn 键的 keyCode (kVK_Function = 63)
let kVK_FunctionKey: UInt32 = 63

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  var overlayPanel: NSPanel?
  var overlayContentView: OverlayView?
  var methodChannel: FlutterMethodChannel?
  var globalMonitor: Any?
  var localMonitor: Any?
  var statusItem: NSStatusItem?
  var eventTap: CFMachPort?
  var eventTapSource: CFRunLoopSource?
  var eventTapKeepAliveTimer: Timer?
  var hotKeyRef: EventHotKeyRef?
  var hotKeyHandler: EventHandlerRef?
  var registeredHotKeyCode: UInt32 = UInt32(kVK_F2)
  var meetingHotKeyRef: EventHotKeyRef?
  var registeredMeetingKeyCode: UInt32 = UInt32(kVK_F2)
  var meetingHotKeyEnabled: Bool = false
  var lastActiveApp: NSRunningApplication?
  var previousFnPressedEventTap: Bool = false
  var previousFnPressedNSEvent: Bool = false
  var fnTapEligibleEventTap: Bool = false
  var fnTapEligibleNSEvent: Bool = false
  var lastFnDownTime: CFAbsoluteTime = 0
  var lastFnEmitTime: CFAbsoluteTime = 0
  var lastFnEmitType: String = ""
  private lazy var logFileURL: URL = {
    let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
    let logsDir = libraryDir?.appendingPathComponent("Logs")
    if let logsDir = logsDir {
      try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
      return logsDir.appendingPathComponent("voicetype.log")
    }
    return URL(fileURLWithPath: "/tmp/voicetype.log")
  }()

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 关闭主窗口不退出应用，让录音 overlay 可以独立存在
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // 获取 FlutterViewController 并注册 MethodChannel
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }

    methodChannel = FlutterMethodChannel(
      name: "com.voicetype/overlay",
      binaryMessenger: controller.engine.binaryMessenger
    )

    setupStatusItem()
    mainFlutterWindow?.isReleasedWhenClosed = false
    mainFlutterWindow?.delegate = self

    methodChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "showOverlay":
        if let args = call.arguments as? [String: Any] {
          self?.showOverlay(args: args)
        }
        result(nil)
      case "hideOverlay":
        self?.hideOverlay()
        result(nil)
      case "updateOverlay":
        if let args = call.arguments as? [String: Any] {
          self?.updateOverlay(args: args)
        }
        result(nil)
      case "showMainWindow":
        self?.showMainWindow()
        result(nil)
      case "insertText":
        if let args = call.arguments as? [String: Any],
           let text = args["text"] as? String {
          self?.insertTextAtCursor(text)
        }
        result(nil)
      case "checkAccessibility":
        let trusted = AXIsProcessTrusted()
        result(trusted)
      case "requestAccessibility":
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        result(trusted)
      case "openSoundInput":
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input") {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      case "openMicrophonePrivacy":
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone") {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      case "openAccessibilityPrivacy":
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      case "openInputMonitoringPrivacy":
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent") {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      case "checkInputMonitoring":
        if #available(macOS 10.15, *) {
          result(CGPreflightListenEventAccess())
        } else {
          result(true)
        }
      case "requestInputMonitoring":
        if #available(macOS 10.15, *) {
          result(CGRequestListenEventAccess())
        } else {
          result(true)
        }
      case "registerHotkey":
        if let args = call.arguments as? [String: Any],
           let keyCode = args["keyCode"] as? Int {
          let modifiers = args["modifiers"] as? Int ?? 0
          let ok = self?.registerHotkey(
            keyCode: UInt32(keyCode),
            modifiers: UInt32(modifiers)
          ) ?? false
          result(ok)
        } else {
          self?.log("[hotkey] method registerHotkey invalid args=\(String(describing: call.arguments))")
          result(false)
        }
      case "unregisterHotkey":
        self?.unregisterHotkey()
        result(nil)
      case "registerMeetingHotkey":
        if let args = call.arguments as? [String: Any],
           let keyCode = args["keyCode"] as? Int {
          let modifiers = args["modifiers"] as? Int ?? 0
          let ok = self?.registerMeetingHotkey(
            keyCode: UInt32(keyCode),
            modifiers: UInt32(modifiers)
          ) ?? false
          result(ok)
        } else {
          self?.log("[hotkey] method registerMeetingHotkey invalid args=\(String(describing: call.arguments))")
          result(false)
        }
      case "unregisterMeetingHotkey":
        self?.unregisterMeetingHotkey()
        result(nil)
      case "getLaunchAtLogin":
        if #available(macOS 13.0, *) {
          let status = SMAppService.mainApp.status
          result(status == .enabled)
        } else {
          result(false)
        }
      case "setLaunchAtLogin":
        if let args = call.arguments as? [String: Any],
           let enabled = args["enabled"] as? Bool {
          if #available(macOS 13.0, *) {
            do {
              if enabled {
                try SMAppService.mainApp.register()
              } else {
                try SMAppService.mainApp.unregister()
              }
              result(true)
            } catch {
              self?.log("[launch] setLaunchAtLogin error: \(error)")
              result(false)
            }
          } else {
            result(false)
          }
        } else {
          result(false)
        }
      case "getShowInDock":
        let policy = NSApp.activationPolicy()
        result(policy == .regular)
      case "setShowInDock":
        if let args = call.arguments as? [String: Any],
           let show = args["show"] as? Bool {
          let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory
          let ok = NSApp.setActivationPolicy(policy)
          if show {
            NSApp.activate(ignoringOtherApps: true)
          }
          self?.log("[dock] setShowInDock show=\(show) ok=\(ok)")
          result(ok)
        } else {
          result(false)
        }
      case "setTrayLabels":
        if let args = call.arguments as? [String: Any] {
          let openLabel = args["open"] as? String ?? "Open"
          let quitLabel = args["quit"] as? String ?? "Quit"
          if let menu = self?.statusItem?.menu {
            // Item 0 = open, item 1 = separator, item 2 = quit
            if menu.items.count > 0 {
              menu.items[0].title = openLabel
            }
            if menu.items.count > 2 {
              menu.items[2].title = quitLabel
            }
          }
          result(nil)
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    ensureAccessibilityPermission()

    // 注册全局快捷键监听（即使主窗口不在前台也能触发）
    setupGlobalHotkey(controller: controller)
  }

  func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      if #available(macOS 11.0, *) {
        button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Offhand")
      } else {
        button.title = "VT"
      }
    }
    let menu = NSMenu()
    let openItem = NSMenuItem(
      title: "打开",
      action: #selector(showMainWindowFromStatusItem),
      keyEquivalent: ""
    )
    openItem.target = self
    menu.addItem(openItem)
    menu.addItem(NSMenuItem.separator())
    let quitItem = NSMenuItem(
      title: "退出",
      action: #selector(quitFromStatusItem),
      keyEquivalent: ""
    )
    quitItem.target = self
    menu.addItem(quitItem)
    item.menu = menu
    statusItem = item
  }

  func ensureAccessibilityPermission() {
    let trusted = AXIsProcessTrusted()
    log("[accessibility] current trust status: \(trusted)")
    if trusted {
      return
    }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    let result = AXIsProcessTrustedWithOptions(options)
    log("[accessibility] requested permission, result: \(result)")
  }

  func log(_ message: String) {
    NSLog("%@", message)
    let formatter = ISO8601DateFormatter()
    let line = "[\(formatter.string(from: Date()))] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if !FileManager.default.fileExists(atPath: logFileURL.path) {
      FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }
    if let handle = try? FileHandle(forWritingTo: logFileURL) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    }
  }

  func emitGlobalKeyEvent(
    keyCode: UInt32,
    type: String,
    isRepeat: Bool,
    source: String,
    hasModifiersOverride: Bool? = nil
  ) {
    // Fn 键去重：CGEventTap 和 NSEvent 都可能触发，短时间内只发一次
    if keyCode == kVK_FunctionKey {
      let now = CFAbsoluteTimeGetCurrent()
      if type == lastFnEmitType && (now - lastFnEmitTime) < 0.08 {
        log("[hotkey] dedup Fn \(type) from \(source), skip")
        return
      }
      lastFnEmitTime = now
      lastFnEmitType = type
    }

    // 获取当前修饰键状态（Cmd/Ctrl/Alt/Shift）
    let flags = NSEvent.modifierFlags
    let modifiers = currentHotkeyModifiers(from: flags)
    let hasModifiersFromFlags = !flags.intersection([.command, .control, .option, .shift]).isEmpty
    let hasModifiers = hasModifiersOverride ?? hasModifiersFromFlags

    let payload: [String: Any] = [
      "keyCode": Int(keyCode),
      "type": type,
      "isRepeat": isRepeat,
      "hasModifiers": hasModifiers,
      "modifiers": Int(modifiers),
    ]

    log("[hotkey] emit keyCode=\(keyCode) type=\(type) isRepeat=\(isRepeat) source=\(source)")

    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        NSLog("[hotkey] emit skipped: self is nil")
        return
      }
      guard let channel = self.methodChannel else {
        NSLog("[hotkey] emit skipped: methodChannel is nil")
        return
      }
      channel.invokeMethod("onGlobalKeyEvent", arguments: payload)
    }
  }

  func currentHotkeyModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.control) {
      modifiers |= UInt32(controlKey)
    }
    if flags.contains(.option) {
      modifiers |= UInt32(optionKey)
    }
    if flags.contains(.shift) {
      modifiers |= UInt32(shiftKey)
    }
    if flags.contains(.command) {
      modifiers |= UInt32(cmdKey)
    }
    return modifiers
  }

  @objc func showMainWindowFromStatusItem() {
    showMainWindow()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if sender == mainFlutterWindow {
      sender.orderOut(nil)
      return false
    }
    return true
  }

  @objc func quitFromStatusItem() {
    NSApp.terminate(nil)
  }

  func setupGlobalHotkey(controller: FlutterViewController) {
    if setupCarbonHotkey() {
      log("[hotkey] using Carbon hotkey")
    } else if setupEventTap() {
      log("[hotkey] using CGEventTap")
    }

    setupNSEventFallbackMonitors()
  }

  func setupNSEventFallbackMonitors() {
    if globalMonitor != nil && localMonitor != nil {
      return
    }

    // 兜底：NSEvent 全局/本地监听
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [self] event in

      if self.methodChannel == nil {
        return
      }
      self.captureActiveApplication()

      if event.type == .keyDown,
         UInt32(event.keyCode) != kVK_FunctionKey,
         self.previousFnPressedNSEvent {
        self.fnTapEligibleNSEvent = false
      }

      if let (emitKeyCode, eventType) = self.matchNSEvent(event) {
        var hasModifiersOverride: Bool? = nil
        if emitKeyCode == kVK_FunctionKey {
          if eventType == "down" {
            hasModifiersOverride = false
          } else if eventType == "up" {
            hasModifiersOverride = !self.fnTapEligibleNSEvent
            self.fnTapEligibleNSEvent = false
          }
        }
        self.emitGlobalKeyEvent(
          keyCode: emitKeyCode,
          type: eventType,
          isRepeat: event.type == .flagsChanged ? false : event.isARepeat,
          source: "nsevent-global",
          hasModifiersOverride: hasModifiersOverride
        )
      }
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [self] event in

      if self.methodChannel == nil {
        return event
      }
      self.captureActiveApplication()

      if event.type == .keyDown,
         UInt32(event.keyCode) != kVK_FunctionKey,
         self.previousFnPressedNSEvent {
        self.fnTapEligibleNSEvent = false
      }

      if let (emitKeyCode, eventType) = self.matchNSEvent(event) {
        var hasModifiersOverride: Bool? = nil
        if emitKeyCode == kVK_FunctionKey {
          if eventType == "down" {
            hasModifiersOverride = false
          } else if eventType == "up" {
            hasModifiersOverride = !self.fnTapEligibleNSEvent
            self.fnTapEligibleNSEvent = false
          }
        }
        self.emitGlobalKeyEvent(
          keyCode: emitKeyCode,
          type: eventType,
          isRepeat: event.type == .flagsChanged ? false : event.isARepeat,
          source: "nsevent-local",
          hasModifiersOverride: hasModifiersOverride
        )
      }
      return event
    }

    log("[hotkey] NSEvent fallback monitors enabled")
  }

  func setupCarbonHotkey() -> Bool {
    if hotKeyHandler == nil {
      let eventTypes = [
        EventTypeSpec(
          eventClass: OSType(kEventClassKeyboard),
          eventKind: UInt32(kEventHotKeyPressed)
        ),
        EventTypeSpec(
          eventClass: OSType(kEventClassKeyboard),
          eventKind: UInt32(kEventHotKeyReleased)
        ),
      ]

      let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
      let status = InstallEventHandler(
        GetEventDispatcherTarget(),
        { _, event, userData in
          guard let userData = userData else {
            return noErr
          }
          let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
          delegate.captureActiveApplication()
          let kind = GetEventKind(event)
          let type = kind == UInt32(kEventHotKeyPressed) ? "down" : "up"

          // Extract hotkey ID to distinguish voice vs meeting hotkey
          var hotKeyID = EventHotKeyID()
          GetEventParameter(event, EventParamName(kEventParamDirectObject),
                           EventParamType(typeEventHotKeyID), nil,
                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

          let keyCode: UInt32
          if hotKeyID.id == 2 {
            keyCode = delegate.registeredMeetingKeyCode
          } else {
            keyCode = delegate.registeredHotKeyCode
          }

          delegate.log("[hotkey] Carbon handler fired type=\(type) keyCode=\(keyCode) hotKeyId=\(hotKeyID.id)")

          delegate.emitGlobalKeyEvent(
            keyCode: keyCode,
            type: type,
            isRepeat: false,
            source: "carbon"
          )
          return noErr
        },
        eventTypes.count,
        eventTypes,
        refcon,
        &hotKeyHandler
      )

      if status != noErr {
        log("[hotkey] failed to install Carbon handler: \(status)")
        return false
      }
    }

    return registerHotkey(keyCode: registeredHotKeyCode, modifiers: 0)
  }

  @discardableResult
  func registerHotkey(keyCode: UInt32, modifiers: UInt32) -> Bool {
    registeredHotKeyCode = keyCode
    previousFnPressedEventTap = false
    previousFnPressedNSEvent = false
    fnTapEligibleEventTap = false
    fnTapEligibleNSEvent = false
    lastFnEmitTime = 0
    lastFnEmitType = ""

    // Fn 键不走 Carbon：直接使用 EventTap + NSEvent 兜底
    if keyCode == kVK_FunctionKey {
      if let hotKeyRef = hotKeyRef {
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
      }

      let tapOK = setupEventTap(preferHIDForFn: true, recreateIfNeeded: true)
      setupNSEventFallbackMonitors()
      if tapOK {
        log("[hotkey] fn key uses CGEventTap path")
      } else {
        log("[hotkey] fn key CGEventTap unavailable, relying on NSEvent fallback")
      }

      let monitorOK = (globalMonitor != nil || localMonitor != nil)
      return tapOK || monitorOK
    }

    if let hotKeyRef = hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }

    let hotKeyID = EventHotKeyID(signature: fourCharCode("VTYP"), id: 1)
    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      hotKeyID,
      GetEventDispatcherTarget(),
      0,
      &hotKeyRef
    )

    if status != noErr {
      log("[hotkey] failed to register Carbon hotkey: \(status)")
      // Fn 等按键无法通过 Carbon 注册时，回退到 CGEventTap
      let fallbackOK = setupEventTap()
      setupNSEventFallbackMonitors()
      if fallbackOK {
        log("[hotkey] fallback to CGEventTap for keyCode=\(keyCode)")
      } else {
        log("[hotkey] fallback to CGEventTap failed for keyCode=\(keyCode)")
      }
      let monitorOK = (globalMonitor != nil || localMonitor != nil)
      return fallbackOK || monitorOK
    }

    log("[hotkey] registered Carbon hotkey keyCode=\(keyCode) modifiers=\(modifiers)")
    return true
  }

  func unregisterHotkey() {
    if let hotKeyRef = hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    previousFnPressedEventTap = false
    previousFnPressedNSEvent = false
    fnTapEligibleEventTap = false
    fnTapEligibleNSEvent = false
    lastFnEmitTime = 0
    lastFnEmitType = ""
  }

  @discardableResult
  func registerMeetingHotkey(keyCode: UInt32, modifiers: UInt32) -> Bool {
    registeredMeetingKeyCode = keyCode
    meetingHotKeyEnabled = true
    fnTapEligibleEventTap = false
    fnTapEligibleNSEvent = false

    // Fn 键不走 Carbon
    if keyCode == kVK_FunctionKey {
      if let meetingHotKeyRef = meetingHotKeyRef {
        UnregisterEventHotKey(meetingHotKeyRef)
        self.meetingHotKeyRef = nil
      }
      let tapOK = setupEventTap(preferHIDForFn: true, recreateIfNeeded: true)
      setupNSEventFallbackMonitors()
      return tapOK || (globalMonitor != nil || localMonitor != nil)
    }

    if let meetingHotKeyRef = meetingHotKeyRef {
      UnregisterEventHotKey(meetingHotKeyRef)
      self.meetingHotKeyRef = nil
    }

    let hotKeyID = EventHotKeyID(signature: fourCharCode("VTYM"), id: 2)
    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      hotKeyID,
      GetEventDispatcherTarget(),
      0,
      &meetingHotKeyRef
    )

    if status != noErr {
      log("[hotkey] failed to register Carbon meeting hotkey: \(status)")
      let fallbackOK = setupEventTap()
      setupNSEventFallbackMonitors()
      return fallbackOK || (globalMonitor != nil || localMonitor != nil)
    }

    log("[hotkey] registered Carbon meeting hotkey keyCode=\(keyCode) modifiers=\(modifiers)")
    return true
  }

  func unregisterMeetingHotkey() {
    meetingHotKeyEnabled = false
    fnTapEligibleEventTap = false
    fnTapEligibleNSEvent = false
    if let meetingHotKeyRef = meetingHotKeyRef {
      UnregisterEventHotKey(meetingHotKeyRef)
      self.meetingHotKeyRef = nil
    }
  }

  /// Helper: match NSEvent against registered hotkeys, return (keyCode, eventType) or nil
  func matchNSEvent(_ event: NSEvent) -> (UInt32, String)? {
    let kc = UInt32(event.keyCode)

    // Determine which hotkeys should use NSEvent fallback (not handled by Carbon/EventTap)
    let voiceUsesFallback: Bool = {
      if hotKeyRef != nil { return false }
      if registeredHotKeyCode == kVK_FunctionKey,
         let tap = eventTap,
         CGEvent.tapIsEnabled(tap: tap) { return false }
      return true
    }()
    let meetingUsesFallback: Bool = {
      if !meetingHotKeyEnabled { return false }
      if meetingHotKeyRef != nil { return false }
      if registeredMeetingKeyCode == kVK_FunctionKey,
         let tap = eventTap,
         CGEvent.tapIsEnabled(tap: tap) { return false }
      return true
    }()

    let matchesVoice = voiceUsesFallback && kc == registeredHotKeyCode
    let matchesMeeting = meetingUsesFallback && kc == registeredMeetingKeyCode

    if event.type == .keyDown {
      if matchesVoice { return (registeredHotKeyCode, "down") }
      if matchesMeeting { return (registeredMeetingKeyCode, "down") }
      return nil
    } else if event.type == .keyUp {
      if matchesVoice { return (registeredHotKeyCode, "up") }
      if matchesMeeting { return (registeredMeetingKeyCode, "up") }
      return nil
    } else if event.type == .flagsChanged {
      // Fn key special handling
      // 不依赖 voiceUsesFallback/meetingUsesFallback 判断 Fn：
      // CGEventTap 在部分 macOS 版本上可能无法可靠接收 Fn flagsChanged 事件，
      // 因此 NSEvent 始终作为 Fn 的后备通道，通过 emitGlobalKeyEvent 去重防止重复。
      let voiceIsFn = registeredHotKeyCode == kVK_FunctionKey && hotKeyRef == nil
      let meetingIsFn = meetingHotKeyEnabled && registeredMeetingKeyCode == kVK_FunctionKey && meetingHotKeyRef == nil
      if (voiceIsFn || meetingIsFn) && kc == kVK_FunctionKey {
        let fnPressed = event.modifierFlags.contains(.function)
        let now = CFAbsoluteTimeGetCurrent()
        if fnPressed == previousFnPressedNSEvent {
          if (now - lastFnDownTime) > 0.5 {
            previousFnPressedNSEvent = !fnPressed
          } else {
            return nil
          }
        }
        previousFnPressedNSEvent = fnPressed
        if fnPressed {
          fnTapEligibleNSEvent = true
          lastFnDownTime = now
        }
        let emitKey = voiceIsFn ? registeredHotKeyCode : registeredMeetingKeyCode
        return (emitKey, fnPressed ? "down" : "up")
      }
      // Non-Fn flagsChanged
      if matchesVoice {
        let fnPressed = event.modifierFlags.contains(.function)
        return (registeredHotKeyCode, fnPressed ? "down" : "up")
      }
      if matchesMeeting {
        let fnPressed = event.modifierFlags.contains(.function)
        return (registeredMeetingKeyCode, fnPressed ? "down" : "up")
      }
      return nil
    }
    return nil
  }

  func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8 {
      result = (result << 8) + OSType(char)
    }
    return result
  }

  func teardownEventTap() {
    eventTapKeepAliveTimer?.invalidate()
    eventTapKeepAliveTimer = nil

    if let source = eventTapSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      eventTapSource = nil
    }

    if let tap = eventTap {
      CFMachPortInvalidate(tap)
      eventTap = nil
    }
  }

  @discardableResult
  func setupEventTap(preferHIDForFn: Bool = false, recreateIfNeeded: Bool = false) -> Bool {
    if recreateIfNeeded {
      teardownEventTap()
    }

    if eventTap != nil {
      // 确保已有的 tap 处于启用状态
      CGEvent.tapEnable(tap: eventTap!, enable: true)
      return true
    }

    let mask =
      (1 << CGEventType.keyDown.rawValue) |
      (1 << CGEventType.keyUp.rawValue) |
      (1 << CGEventType.flagsChanged.rawValue)
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
      }

      let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()

      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = delegate.eventTap {
          CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
      }

      guard delegate.methodChannel != nil else {
        return Unmanaged.passUnretained(event)
      }

      // Carbon 热键可用时，不再通过 EventTap 转发，避免重复触发
      // 但如果会议热键通过 Carbon 注册，仍需检查会议热键
      let voiceUsesCarbon = delegate.hotKeyRef != nil
      let meetingUsesCarbon = delegate.meetingHotKeyRef != nil

      delegate.captureActiveApplication()
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

      if type == .keyDown,
         UInt32(keyCode) != kVK_FunctionKey,
         delegate.previousFnPressedEventTap {
        delegate.fnTapEligibleEventTap = false
      }

      // Determine which registered hotkey matches
      let matchesVoice = !voiceUsesCarbon && UInt32(keyCode) == delegate.registeredHotKeyCode
      let matchesMeeting = !meetingUsesCarbon && delegate.meetingHotKeyEnabled && UInt32(keyCode) == delegate.registeredMeetingKeyCode

      if !matchesVoice && !matchesMeeting {
        // Check Fn key special case
        if UInt32(keyCode) == kVK_FunctionKey && type == .flagsChanged {
          let voiceIsFn = !voiceUsesCarbon && delegate.registeredHotKeyCode == kVK_FunctionKey
          let meetingIsFn = !meetingUsesCarbon && delegate.meetingHotKeyEnabled && delegate.registeredMeetingKeyCode == kVK_FunctionKey
          if !voiceIsFn && !meetingIsFn {
            return Unmanaged.passUnretained(event)
          }
          // Fall through to flagsChanged handling below
        } else {
          return Unmanaged.passUnretained(event)
        }
      }

      let emitKeyCode: UInt32
      let eventType: String
      if type == .keyDown {
        emitKeyCode = matchesVoice ? delegate.registeredHotKeyCode : delegate.registeredMeetingKeyCode
        eventType = "down"
      } else if type == .keyUp {
        emitKeyCode = matchesVoice ? delegate.registeredHotKeyCode : delegate.registeredMeetingKeyCode
        eventType = "up"
      } else if type == .flagsChanged {
        // Fn 键特殊处理：通过 maskSecondaryFn 标志位变化检测按下/释放
        let voiceIsFn = !voiceUsesCarbon && delegate.registeredHotKeyCode == kVK_FunctionKey
        let meetingIsFn = !meetingUsesCarbon && delegate.meetingHotKeyEnabled && delegate.registeredMeetingKeyCode == kVK_FunctionKey
        if (voiceIsFn || meetingIsFn) && UInt32(keyCode) == kVK_FunctionKey {
          let fnPressed = event.flags.contains(.maskSecondaryFn)
          let now = CFAbsoluteTimeGetCurrent()
          if fnPressed == delegate.previousFnPressedEventTap {
            if (now - delegate.lastFnDownTime) > 0.5 {
              delegate.previousFnPressedEventTap = !fnPressed
              delegate.log("[hotkey] EventTap Fn state reset (stale), fnPressed=\(fnPressed)")
            } else {
              return Unmanaged.passUnretained(event)
            }
          }
          delegate.previousFnPressedEventTap = fnPressed
          if fnPressed {
            delegate.fnTapEligibleEventTap = true
            delegate.lastFnDownTime = now
          }
          // Emit for the hotkey that is set to Fn (prefer voice if both are Fn)
          emitKeyCode = voiceIsFn ? delegate.registeredHotKeyCode : delegate.registeredMeetingKeyCode
          eventType = fnPressed ? "down" : "up"
        } else if matchesVoice || matchesMeeting {
          let fnPressed = event.flags.contains(.maskSecondaryFn)
          emitKeyCode = matchesVoice ? delegate.registeredHotKeyCode : delegate.registeredMeetingKeyCode
          eventType = fnPressed ? "down" : "up"
        } else {
          return Unmanaged.passUnretained(event)
        }
      } else {
        return Unmanaged.passUnretained(event)
      }

      var hasModifiersOverride: Bool? = nil
      if emitKeyCode == kVK_FunctionKey {
        if eventType == "down" {
          hasModifiersOverride = false
        } else if eventType == "up" {
          hasModifiersOverride = !delegate.fnTapEligibleEventTap
          delegate.fnTapEligibleEventTap = false
        }
      }

      delegate.emitGlobalKeyEvent(
        keyCode: emitKeyCode,
        type: eventType,
        isRepeat: type == .flagsChanged ? false : isRepeat,
        source: "event-tap",
        hasModifiersOverride: hasModifiersOverride
      )

      return Unmanaged.passUnretained(event)
    }

    let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    
    // 尝试创建 CGEventTap，使用多种方法以获得更好的兼容性
    var tap: CFMachPort? = nil

    let tapCandidates: [CGEventTapLocation] = preferHIDForFn
      ? [.cghidEventTap, .cgAnnotatedSessionEventTap, .cgSessionEventTap]
      : [.cgAnnotatedSessionEventTap, .cgSessionEventTap, .cghidEventTap]

    for location in tapCandidates {
      tap = CGEvent.tapCreate(
        tap: location,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: CGEventMask(mask),
        callback: callback,
        userInfo: refcon
      )
      if tap != nil {
        log("[hotkey] created CGEventTap location=\(location.rawValue) option=listenOnly")
        break
      }
    }

    guard let eventTap = tap else {
      log("[hotkey] failed to create CGEventTap with any method. Accessibility permission may be required.")
      return false
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    self.eventTap = eventTap
    eventTapSource = source

    // 高频检查并重新启用 event tap，防止系统因权限不足自动禁用
    eventTapKeepAliveTimer?.invalidate()
    var disableCount = 0
    eventTapKeepAliveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self, let tap = self.eventTap else { return }
      if !CGEvent.tapIsEnabled(tap: tap) {
        disableCount += 1
        self.log("[hotkey] EventTap disabled (count=\(disableCount)), re-enabling")
        // EventTap 被禁用期间可能丢失了 Fn 释放事件，重置状态
        self.previousFnPressedEventTap = false
        self.fnTapEligibleEventTap = false
        // 检测权限是否已授予：如果已授予则重建 EventTap 以获得稳定连接
        if AXIsProcessTrusted() || CGPreflightListenEventAccess() {
          let isFn = self.registeredHotKeyCode == kVK_FunctionKey
          self.setupEventTap(preferHIDForFn: isFn, recreateIfNeeded: true)
          disableCount = 0
          return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
      } else {
        disableCount = 0
      }
    }

    return true
  }

  func showOverlay(args: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if self.overlayPanel == nil {
        self.createOverlayPanel()
      }

      let state = args["state"] as? String ?? "recording"
      let duration = args["duration"] as? String ?? "00:00"
      let level = args["level"] as? Double ?? 0.0
      let stateLabel = args["stateLabel"] as? String

      self.overlayContentView?.update(state: state, duration: duration, level: level, stateLabel: stateLabel)
      self.overlayPanel?.orderFront(nil)
      self.positionOverlay()
    }
  }

  func hideOverlay() {
    DispatchQueue.main.async { [weak self] in
      self?.overlayPanel?.orderOut(nil)
    }
  }

  func updateOverlay(args: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      let state = args["state"] as? String ?? "recording"
      let duration = args["duration"] as? String ?? "00:00"
      let level = args["level"] as? Double ?? 0.0
      let stateLabel = args["stateLabel"] as? String
      self?.overlayContentView?.update(state: state, duration: duration, level: level, stateLabel: stateLabel)
    }
  }

  func showMainWindow() {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func insertTextAtCursor(_ text: String) {
    if insertTextViaAccessibility(text) {
      log("[insert] success via accessibility")
      return
    }
    log("[insert] accessibility insert failed, fallback to paste")
    let pasteboard = NSPasteboard.general
    let previousString = pasteboard.string(forType: .string)
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    if let targetApp = lastActiveApp,
       targetApp.bundleIdentifier != Bundle.main.bundleIdentifier {
      targetApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      self.sendPasteShortcut()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      pasteboard.clearContents()
      if let prev = previousString {
        pasteboard.setString(prev, forType: .string)
      }
    }
  }

  func insertTextViaAccessibility(_ text: String) -> Bool {
    guard AXIsProcessTrusted() else {
      log("[insert] accessibility not trusted")
      return false
    }

    let systemWide = AXUIElementCreateSystemWide()
    var focusedElement: AnyObject?
    let focusedResult = AXUIElementCopyAttributeValue(
      systemWide,
      kAXFocusedUIElementAttribute as CFString,
      &focusedElement
    )
    if focusedResult != .success {
      log("[insert] no focused element, status=\(focusedResult.rawValue)")
      return false
    }

    guard let target = focusedElement else {
      log("[insert] focused element is nil")
      return false
    }

    let insertResult = AXUIElementSetAttributeValue(
      target as! AXUIElement,
      kAXSelectedTextAttribute as CFString,
      text as CFTypeRef
    )

    if insertResult == .success {
      return true
    }

    let valueResult = AXUIElementSetAttributeValue(
      target as! AXUIElement,
      kAXValueAttribute as CFString,
      text as CFTypeRef
    )

    if valueResult == .success {
      return true
    }

    log("[insert] AX insert failed selected=\(insertResult.rawValue) value=\(valueResult.rawValue)")
    return false
  }

  func captureActiveApplication() {
    if let frontmost = NSWorkspace.shared.frontmostApplication {
      if frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
        lastActiveApp = frontmost
      }
    }
  }

  func sendPasteShortcut() {
    guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
    let keyV = CGKeyCode(kVK_ANSI_V)

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
    keyDown?.flags = .maskCommand
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
    keyUp?.flags = .maskCommand

    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
  }

  func createOverlayPanel() {
    let panelWidth: CGFloat = 280
    let panelHeight: CGFloat = 56

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
      styleMask: [.nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true

    let contentView = OverlayView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
    panel.contentView = contentView

    overlayPanel = panel
    overlayContentView = contentView
  }

  func positionOverlay() {
    guard let panel = overlayPanel, let screen = NSScreen.main else { return }
    let screenFrame = screen.visibleFrame
    let panelFrame = panel.frame
    let x = screenFrame.midX - panelFrame.width / 2
    let y = screenFrame.origin.y + 80
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }

  deinit {
    eventTapKeepAliveTimer?.invalidate()
    eventTapKeepAliveTimer = nil
    if let monitor = globalMonitor {
      NSEvent.removeMonitor(monitor)
    }
    if let monitor = localMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}
