import AppKit
import SwiftUI
import ApplicationServices
import CoreGraphics

@MainActor
public final class FloatingPanel<Content: View>: NSPanel {
    private var localKeyDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var workspaceAppObserver: NSObjectProtocol?
    private var workspaceSpaceObserver: NSObjectProtocol?
    private weak var previousApp: NSRunningApplication?
    public private(set) var lastPresentTimestamp: TimeInterval = 0
    public private(set) var lastDismissTimestamp: TimeInterval = 0

    public init(contentRect: NSRect, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .nonactivatingPanel,
                .fullSizeContentView,
                .borderless
            ],
            backing: .buffered,
            defer: false
        )

        // Окно открывается на текущем рабочем столе и автоматически скрывается при перелистывании Spaces
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = false

        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.minSize = NSSize(width: 900, height: 650)

        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovable = true
        self.isMovableByWindowBackground = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true

        let savedTheme = UserDefaults.standard.string(forKey: "selectedThemeId")
            ?? UserDefaults.standard.string(forKey: "pasteVaultTheme")
            ?? "obsidian"
        let isLight = (savedTheme == "frost" || savedTheme == "solarizedPaper")
        self.appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)

        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true

        let containerView = NSView(frame: contentRect)
        containerView.wantsLayer = true
        containerView.layer?.isOpaque = false
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.layer?.cornerRadius = 20
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.masksToBounds = true

        let hostingView = NSHostingView(rootView: content())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 20
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        containerView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.contentView = containerView
        if let themeFrame = containerView.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.isOpaque = false
            themeFrame.layer?.backgroundColor = NSColor.clear.cgColor
            themeFrame.layer?.cornerRadius = 20
            themeFrame.layer?.cornerCurve = .continuous
            themeFrame.layer?.masksToBounds = true
        }

        // Запоминаем текущее внешнее приложение
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier,
           front.activationPolicy == .regular,
           !ClipboardMonitor.isIgnoredTarget(front) {
            self.previousApp = front
        }

        // Отслеживаем последнее активное стороннее приложение (Warp, Safari, ChatGPT, Antigravity и т.д.)
        workspaceAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier,
               app.localizedName != "Paste Vault",
               app.localizedName != "PasteVault",
               app.activationPolicy == .regular,
               !ClipboardMonitor.isIgnoredTarget(app) {
                Task { @MainActor in
                    self?.previousApp = app
                    ClipboardMonitor.shared.updateTargetApplication(app)
                }
            }
        }

        // При перелистывании рабочих столов macOS (Spaces) влево-вправо аккуратно закрываем окно
        workspaceSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isVisible else { return }
                self.lastDismissTimestamp = ProcessInfo.processInfo.systemUptime
                self.orderOut(nil)
            }
        }

        // Глобальный мониторинг кликов мыши вне окна Paste Vault: мгновенно скрывает панель при клике мимо
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isVisible else { return }
                if ClipboardMonitor.shared.isModalOverlayActive { return }
                if self.attachedSheet != nil { return }
                let hasActiveSaveOrOpenPanel = NSApp.windows.contains { $0.isVisible && ($0 is NSSavePanel || $0 is NSOpenPanel || $0.className.contains("SavePanel") || $0.className.contains("OpenPanel")) }
                if hasActiveSaveOrOpenPanel { return }

                let mouseLocation = NSEvent.mouseLocation
                if self.frame.contains(mouseLocation) { return }

                // Исключаем клики внутри дочерних окон и окон поповеров приложения Paste Vault (NSPopover)
                let isInsideAnyAppWindow = NSApp.windows.contains { w in
                    guard w.isVisible else { return false }
                    let isPopover = w.className.contains("Popover") || (w.parent == self)
                    return isPopover && w.frame.contains(mouseLocation)
                }
                if isInsideAnyAppWindow { return }

                self.dismissPanel(restorePreviousApp: false)
            }
        }

        // Глобальный мониторинг клавиши Esc, когда окно Paste Vault открыто поверх других приложений
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 && flags.isEmpty {
                Task { @MainActor in
                    if ClipboardMonitor.shared.isModalOverlayActive {
                        NotificationCenter.default.post(name: Notification.Name("pasteVaultModalEscape"), object: nil)
                    } else {
                        self.dismissPanel(restorePreviousApp: false)
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("pasteVaultDismissPanel"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissPanel(restorePreviousApp: true)
            }
        }
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    override public func close() {
        dismissPanel(restorePreviousApp: true)
    }

    override public func cancelOperation(_ sender: Any?) {
        if ShortcutManager.shared.isRecordingShortcut {
            ShortcutManager.shared.stopRecording()
            return
        }
        dismissPanel(restorePreviousApp: true)
    }

    public func dismissPanel(restorePreviousApp: Bool = true) {
        if ShortcutManager.shared.isRecordingShortcut {
            return
        }
        if self.attachedSheet != nil {
            return
        }
        let hasActiveSaveOrOpenPanel = NSApp.windows.contains { $0.isVisible && ($0 is NSSavePanel || $0 is NSOpenPanel || $0.className.contains("SavePanel") || $0.className.contains("OpenPanel")) }
        if hasActiveSaveOrOpenPanel {
            return
        }
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyDownMonitor = nil
        }

        guard self.isVisible else { return }
        self.lastDismissTimestamp = ProcessInfo.processInfo.systemUptime
        self.orderOut(nil)

        if restorePreviousApp {
            let target = AppDelegate.shared?.monitor.targetApp ?? previousApp
            if let prev = target, !prev.isTerminated {
                prev.activate()
            } else {
                NSApp.deactivate()
            }
        }
    }

    /// Позиционирует панель 900×600 непосредственно по центру активного окна пользователя (без переключения Spaces)
    public func positionOverActiveWindow() {
        let panelWidth: CGFloat = 900
        let panelHeight: CGFloat = 650
        let myPID = ProcessInfo.processInfo.processIdentifier

        var targetPID: pid_t? = ClipboardMonitor.shared.lastActiveApp?.processIdentifier
            ?? AppDelegate.shared?.monitor.targetApp?.processIdentifier
        if targetPID == nil || targetPID == myPID {
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if frontPID != myPID {
                targetPID = frontPID
            }
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windowList = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 1080

        var matchedWindowCocoaRect: NSRect? = nil

        if let pid = targetPID, pid != myPID {
            for entry in windowList {
                guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                      ownerPID == pid,
                      let layer = entry[kCGWindowLayer as String] as? Int,
                      layer == 0,
                      let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                      let qX = bounds["X"],
                      let qY = bounds["Y"],
                      let qW = bounds["Width"],
                      let qH = bounds["Height"],
                      qW > 200, qH > 200 else {
                    continue
                }
                let cocoaY = primaryScreenHeight - qY - qH
                matchedWindowCocoaRect = NSRect(x: qX, y: cocoaY, width: qW, height: qH)
                break
            }
        }

        // Если у targetPID не нашлось окна на экране, берём самое верхнее окно любого активного приложения на текущем экране
        if matchedWindowCocoaRect == nil {
            for entry in windowList {
                guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                      ownerPID != myPID,
                      let layer = entry[kCGWindowLayer as String] as? Int,
                      layer == 0,
                      let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                      let qX = bounds["X"],
                      let qY = bounds["Y"],
                      let qW = bounds["Width"],
                      let qH = bounds["Height"],
                      qW > 200, qH > 200 else {
                    continue
                }
                let cocoaY = primaryScreenHeight - qY - qH
                matchedWindowCocoaRect = NSRect(x: qX, y: cocoaY, width: qW, height: qH)
                break
            }
        }

        if let winRect = matchedWindowCocoaRect {
            let winCenter = NSPoint(x: winRect.midX, y: winRect.midY)
            let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(winCenter, $0.frame, false) })
                ?? NSScreen.screens.first(where: { $0.frame.intersects(winRect) })
                ?? NSScreen.main
                ?? NSScreen.screens.first

            let rawX = winRect.midX - panelWidth / 2
            let rawY = winRect.midY - panelHeight / 2

            if let screen = targetScreen {
                let finalFrame = clampedFrame(x: rawX, y: rawY, width: panelWidth, height: panelHeight, in: screen.visibleFrame)
                self.setFrame(finalFrame, display: true)
                return
            }
        }

        // Fallback: если открытых окон нет — центрируем на том NSScreen, где сейчас находится курсор мыши
        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let screen = mouseScreen {
            let visible = screen.visibleFrame
            let rawX = visible.midX - panelWidth / 2
            let rawY = visible.midY - panelHeight / 2
            let finalFrame = clampedFrame(x: rawX, y: rawY, width: panelWidth, height: panelHeight, in: visible)
            self.setFrame(finalFrame, display: true)
        } else {
            self.setFrame(NSRect(x: 200, y: 200, width: panelWidth, height: panelHeight), display: true)
        }
    }

    public func showPanel() {
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier,
           frontApp.localizedName != "Paste Vault",
           frontApp.localizedName != "PasteVault",
           frontApp.activationPolicy == .regular,
           !ClipboardMonitor.isIgnoredTarget(frontApp) {
            self.previousApp = frontApp
            ClipboardMonitor.shared.updateTargetApplication(frontApp)
        }
        presentPanel()
    }

    public func togglePanel() {
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier,
           frontApp.localizedName != "Paste Vault",
           frontApp.localizedName != "PasteVault",
           frontApp.activationPolicy == .regular,
           !ClipboardMonitor.isIgnoredTarget(frontApp) {
            self.previousApp = frontApp
            ClipboardMonitor.shared.updateTargetApplication(frontApp)
        }
        toggleOrPresent(preferCursor: true)
    }

    public func presentPanel() {
        self.isReleasedWhenClosed = false
        let now = ProcessInfo.processInfo.systemUptime
        self.lastPresentTimestamp = now

        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != Bundle.main.bundleIdentifier,
           frontApp.localizedName != "Paste Vault",
           frontApp.localizedName != "PasteVault",
           frontApp.activationPolicy == .regular,
           !ClipboardMonitor.isIgnoredTarget(frontApp) {
            self.previousApp = frontApp
            ClipboardMonitor.shared.updateTargetApplication(frontApp)
        } else {
            ClipboardMonitor.shared.detectFrontmostExternalApp()
            if let detected = ClipboardMonitor.shared.lastActiveApp ?? ClipboardMonitor.shared.targetApp {
                self.previousApp = detected
            }
        }

        let savedTheme = UserDefaults.standard.string(forKey: "selectedThemeId")
            ?? UserDefaults.standard.string(forKey: "pasteVaultTheme")
            ?? "obsidian"
        let isLight = (savedTheme == "frost" || savedTheme == "solarizedPaper")
        self.appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)

        // Показываем панель поверх полноэкранных и обычных окон на текущем Space БЕЗ NSApp.activate()
        ClipboardMonitor.shared.refreshAccessibilityStatus()
        self.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.level = .popUpMenu
        self.positionOverActiveWindow()
        self.invalidateShadow()
        self.orderFrontRegardless()
        self.makeKey()

        installEventMonitors()
    }

    public func toggleOrPresent(preferCursor: Bool = false) {
        if ShortcutManager.shared.isRecordingShortcut {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPresentTimestamp < 0.18 || now - lastDismissTimestamp < 0.18 {
            return
        }

        if self.isVisible {
            dismissPanel(restorePreviousApp: true)
        } else {
            presentPanel()
        }
    }

    // MARK: - Smart Multi-Monitor & Target App Positioning
    private func calculateSmartPanelFrame(for targetApp: NSRunningApplication?) -> NSRect {
        let width = max(self.frame.width, 900)
        let height = max(self.frame.height, 600)
        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let screen = mouseScreen {
            let visible = screen.visibleFrame
            let rawX = visible.midX - width / 2
            let rawY = visible.midY - height / 2
            return clampedFrame(x: rawX, y: rawY, width: width, height: height, in: visible)
        }

        return NSRect(x: 200, y: 200, width: width, height: height)
    }

    private func clampedFrame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, in visible: NSRect) -> NSRect {
        let margin: CGFloat = 14
        let finalWidth = min(width, visible.width - margin * 2)
        let finalHeight = min(height, visible.height - margin * 2)
        let minX = visible.minX + margin
        let maxX = max(minX, visible.maxX - finalWidth - margin)
        let minY = visible.minY + margin
        let maxY = max(minY, visible.maxY - finalHeight - margin)

        let clampedX = min(max(x, minX), maxX)
        let clampedY = min(max(y, minY), maxY)
        return NSRect(x: round(clampedX), y: round(clampedY), width: round(finalWidth), height: round(finalHeight))
    }

    private func screenContaining(point: NSPoint) -> NSScreen? {
        return NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
    }

    /// Определяет координаты сфокусированного поля ввода (например, поисковой строки Safari) через AXUIElement
    private func queryFocusedElementAppKitRect(for app: NSRunningApplication) -> NSRect? {
        guard AccessibilityService.isAccessibilityTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard status == .success, let focusedObj = focusedValue else { return nil }
        let focusedElement = focusedObj as! AXUIElement

        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(focusedElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posRef = posValue,
              let sizeRef = sizeValue else {
            return nil
        }

        var cgPoint = CGPoint.zero
        var cgSize = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &cgPoint),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &cgSize),
              cgSize.width > 16, cgSize.height > 8, cgSize.height < 500 else {
            return nil
        }

        return convertQuartzRectToAppKit(cgX: cgPoint.x, cgY: cgPoint.y, width: cgSize.width, height: cgSize.height)
    }

    /// Определяет координаты активного окна целевого приложения (например, Safari) на любом из мониторов
    private func queryFrontmostWindowAppKitRect(for app: NSRunningApplication, preferredScreen: NSScreen?) -> NSRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let targetPID = app.processIdentifier
        var candidateRects: [NSRect] = []

        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == targetPID,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"],
                  let y = bounds["Y"],
                  let w = bounds["Width"],
                  let h = bounds["Height"],
                  w >= 200, h >= 150 else {
                continue
            }

            let appKitRect = convertQuartzRectToAppKit(cgX: x, cgY: y, width: w, height: h)
            candidateRects.append(appKitRect)
        }

        guard !candidateRects.isEmpty else { return nil }

        // Если у приложения (например, Safari) открыто несколько окон на разных мониторах, предпочитаем окно на экране с курсором
        if let preferredScreen {
            if let matchOnMouseScreen = candidateRects.first(where: {
                NSMouseInRect(NSPoint(x: $0.midX, y: $0.midY), preferredScreen.frame, false)
            }) {
                return matchOnMouseScreen
            }
        }

        return candidateRects.first
    }

    /// Конвертирует глобальные координаты Quartz (0,0 в верхнем левом углу главного экрана) в координаты AppKit (0,0 в нижнем левом углу)
    private func convertQuartzRectToAppKit(cgX: CGFloat, cgY: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 1080
        let appKitY = primaryScreenHeight - cgY - height
        return NSRect(x: cgX, y: appKitY, width: width, height: height)
    }

    private func installEventMonitors() {
        guard localKeyDownMonitor == nil else { return }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Если прямо сейчас идёт запись горячей клавиши в Настройках — поглощаем событие, чтобы окно не закрывалось
            if ShortcutManager.shared.isRecordingShortcut {
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let config = ShortcutManager.shared.config

            // Защита от попадания ⌘V в окно самого PasteVault во время автовставки
            if ClipboardMonitor.shared.isPerformingAutoPaste {
                if flags.contains(.command) && (event.keyCode == 9 || event.charactersIgnoringModifiers?.lowercased() == "v") {
                    return nil
                }
            }

            // Если открыто модальное окно просмотра/редактора скриншотов — обрабатываем его горячие клавиши в приоритете
            if ClipboardMonitor.shared.isModalOverlayActive {
                let isTextInput = ClipboardMonitor.shared.isEditingScreenshotText

                // Esc (53) без модификаторов — закрыть редактор (или завершить ввод текста), не закрывая главное окно
                if event.keyCode == 53 && flags.isEmpty {
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultModalEscape"), object: nil)
                    return nil
                }
                // Return / Enter (36 / 76) без модификаторов — завершить ввод текста или сохранить копию скриншота
                if (event.keyCode == 36 || event.keyCode == 76) && flags.subtracting([.numericPad, .function]).isEmpty {
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultPasteSelected"), object: nil)
                    return nil
                }
                // Пробел (Space, keyCode 49) без модификаторов — переключить на инструмент «✋ Рука»
                if event.keyCode == 49 && flags.isEmpty && !isTextInput {
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultEditorSelectHand"), object: nil)
                    return nil
                }
                // ⌫ Backspace (51) или Delete (117) без модификаторов — удалить выделенный элемент на холсте
                if (event.keyCode == 51 || event.keyCode == 117) && flags.subtracting([.numericPad, .function]).isEmpty && !isTextInput {
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultEditorDeleteSelected"), object: nil)
                    return nil
                }
                // ⌘ + Z (keyCode 6) — отменить последний шаг разметки
                if flags == .command && (event.keyCode == 6 || event.charactersIgnoringModifiers?.lowercased() == "z") && !isTextInput {
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultEditorUndo"), object: nil)
                    return nil
                }
                // ⌘ + S (keyCode 1) — сохранить копию скриншота
                if flags == .command && (event.keyCode == 1 || event.charactersIgnoringModifiers?.lowercased() == "s") {
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultPasteSelected"), object: nil)
                    return nil
                }
                // ⌘ + "+" / "=" (keyCode 24 или 69 на numpad) — увеличить масштаб
                if flags.contains(.command) && (event.keyCode == 24 || event.keyCode == 69 || event.charactersIgnoringModifiers == "+" || event.charactersIgnoringModifiers == "=") {
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultEditorZoomIn"), object: nil)
                    return nil
                }
                // ⌘ + "-" (keyCode 27 или 78 на numpad) — уменьшить масштаб
                if flags.contains(.command) && (event.keyCode == 27 || event.keyCode == 78 || event.charactersIgnoringModifiers == "-") {
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultEditorZoomOut"), object: nil)
                    return nil
                }
                // ⌘ + 0 (keyCode 29 или 82 на numpad) — сбросить масштаб до 100%
                if flags == .command && (event.keyCode == 29 || event.keyCode == 82 || event.charactersIgnoringModifiers == "0") {
                    NotificationCenter.default.post(name: Notification.Name("pasteVaultEditorZoomReset"), object: nil)
                    return nil
                }
                // ⌘Q (keyCode 12) — полный выход из приложения
                if flags == .command && (event.keyCode == 12 || event.charactersIgnoringModifiers?.lowercased() == "q") {
                    NSApplication.shared.terminate(nil)
                    return nil
                }
                return event
            }

            // 1. Esc (53) без модификаторов — закрыть окно
            if event.keyCode == 53 && flags.isEmpty {
                self.dismissPanel(restorePreviousApp: true)
                return nil
            }

            // 2. togglePanel (например, ⌥Space) — закрыть окно, если оно уже открыто
            if config.togglePanel.matches(event: event) {
                self.dismissPanel(restorePreviousApp: true)
                return nil
            }

            // 3. Стрелка вниз (125) — следующий элемент списка
            if event.keyCode == 125 && flags.subtracting([.numericPad, .function]).isEmpty {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultMoveSelectionDown"), object: nil)
                return nil
            }

            // 4. Стрелка вверх (126) — предыдущий элемент списка
            if event.keyCode == 126 && flags.subtracting([.numericPad, .function]).isEmpty {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultMoveSelectionUp"), object: nil)
                return nil
            }

            // 5. Вставить выбранную запись (pasteSelected)
            if config.pasteSelected.matches(event: event) {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultPasteSelected"), object: nil)
                return nil
            }

            // 6. Вставить без форматирования (pastePlainText)
            if config.pastePlainText.matches(event: event) {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultPastePlainText"), object: nil)
                return nil
            }

            // 7. Быстрая вставка по номеру 1..9 (quickPasteModifier)
            if config.matchesQuickPaste(event: event), let digit = config.quickPasteDigit(event: event) {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultPasteByIndex"), object: digit - 1)
                return nil
            }

            // 8. Закрепить / открепить (togglePin)
            if config.togglePin.matches(event: event) {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultTogglePin"), object: nil)
                return nil
            }

            // 9. Удалить запись (deleteItem)
            if config.deleteItem.matches(event: event) {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultDeleteItem"), object: nil)
                return nil
            }

            // 10. Очистить незакрепленную историю (clearHistory)
            if config.clearHistory.matches(event: event) {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultClearHistory"), object: nil)
                return nil
            }

            // 11. Пауза / запись (togglePause)
            if config.togglePause.matches(event: event) {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultTogglePause"), object: nil)
                return nil
            }

            // 12. Открыть генератор паролей (openPassGen)
            if config.openPassGen.matches(event: event) {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultOpenPassGen"), object: nil)
                return nil
            }

            // 13. Открыть шаблоны (openSnippets)
            if config.openSnippets.matches(event: event) {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultOpenSnippets"), object: nil)
                return nil
            }

            // 14. Открыть настройки (openSettings)
            if config.openSettings.matches(event: event) {
                NotificationCenter.default.post(name: Notification.Name("pasteVaultOpenSettings"), object: nil)
                return nil
            }

            // ⌘Q (keyCode 12) — полный выход из приложения
            if flags == .command && (event.keyCode == 12 || event.charactersIgnoringModifiers?.lowercased() == "q") {
                NSApplication.shared.terminate(nil)
                return nil
            }

            return event
        }
    }
}

public final class DraggableNSView: NSView {
    public override var mouseDownCanMoveWindow: Bool {
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        self.window?.performDrag(with: event)
    }
}

public struct WindowDragHandle: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> DraggableNSView {
        let view = DraggableNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    public func updateNSView(_ nsView: DraggableNSView, context: Context) {}
}

