import XCTest
import SwiftUI
import AppKit
import CryptoKit
import ApplicationServices
@testable import PasteVault

/// Деструктивный E2E- и UI-набор тестов (Итерация 30.35).
/// Строго изолирован в /tmp/PasteVault_TestRun_<pid>/, AppDefaults.shared и NSPasteboard.withUniqueName().
/// Честно проверяет ожидаемое корректное поведение: падения тестов отражают реально найденные поломки в коде приложения.
@MainActor
final class DestructiveE2ETests: XCTestCase {

    // MARK: - Вспомогательные утилиты изоляции и живого UI

    private func makeTransparentPNGImage(size: NSSize, alphaRect: NSRect? = nil) throws -> (NSImage, Data) {
        let w = max(1, Int(size.width))
        let h = max(1, Int(size.height))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w,
            pixelsHigh: h,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "DestructiveE2E", code: 1)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.9, alpha: 0.5).setFill()
        NSRect(x: 0, y: 0, width: max(1, w / 2), height: max(1, h / 2)).fill()
        if let alphaRect {
            NSColor.clear.setFill()
            alphaRect.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: size)
        img.addRepresentation(rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "DestructiveE2E", code: 2)
        }
        return (img, png)
    }

    private func pumpRunLoop(_ seconds: TimeInterval = 0.05) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private struct AXButtonProxy {
        let label: String
        let title: String
        let help: String
        let press: () -> Bool

        var combinedText: String { "\(label) \(title) \(help)" }
    }

    private static var appBootstrapped = false

    private func prepareLiveWindow(_ window: NSWindow, hosting: NSViewController) {
        if !Self.appBootstrapped {
            Self.appBootstrapped = true
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.finishLaunching()
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.layoutIfNeeded()
        hosting.view.layoutSubtreeIfNeeded()
        pumpRunLoop(0.3)
    }

    private func collectAccessibilityButtons(from root: NSView) -> [AXButtonProxy] {
        var result: [AXButtonProxy] = []
        var stack: [Any] = [root]
        var visited = 0
        while !stack.isEmpty && visited < 8000 {
            visited += 1
            let current = stack.removeLast()
            if let btn = current as? NSButton {
                let lbl = btn.accessibilityLabel() ?? ""
                let ttl = btn.title
                let hlp = btn.accessibilityHelp() ?? btn.toolTip ?? ""
                result.append(AXButtonProxy(label: lbl, title: ttl, help: hlp, press: { [weak btn] in
                    guard let btn else { return false }
                    btn.performClick(nil)
                    return true
                }))
            } else if let axEl = current as? NSAccessibilityProtocol {
                let role = axEl.accessibilityRole()
                if role == .button || role == .radioButton || role == .checkBox || role == .popUpButton {
                    let lbl = axEl.accessibilityLabel() ?? ""
                    let ttl = axEl.accessibilityTitle() ?? ""
                    let hlp = axEl.accessibilityHelp() ?? ""
                    result.append(AXButtonProxy(label: lbl, title: ttl, help: hlp, press: {
                        axEl.accessibilityPerformPress()
                    }))
                }
            }
            if let axContainer = current as? NSAccessibilityProtocol,
               let children = axContainer.accessibilityChildren() {
                stack.append(contentsOf: children)
            }
            if let view = current as? NSView {
                for sub in view.subviews {
                    stack.append(sub)
                }
            }
        }

        // Всегда обходим также живые SwiftUI AXUIElement собственного PID (так как на вкладках могут быть смешаны NSButton и SwiftUI ButtonStyle)
        let appEl = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement] {
            var axStack: [AXUIElement] = axWindows
            var axVisited = 0
            while !axStack.isEmpty && axVisited < 4000 {
                axVisited += 1
                let el = axStack.removeLast()
                var roleRef: CFTypeRef?
                var titleRef: CFTypeRef?
                var descRef: CFTypeRef?
                var helpRef: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
                _ = AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
                _ = AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
                _ = AXUIElementCopyAttributeValue(el, kAXHelpAttribute as CFString, &helpRef)
                let roleStr = (roleRef as? String) ?? ""
                if roleStr == kAXButtonRole || roleStr == kAXRadioButtonRole || roleStr == kAXCheckBoxRole || roleStr == kAXPopUpButtonRole {
                    let lbl = (descRef as? String) ?? ""
                    let ttl = (titleRef as? String) ?? ""
                    let hlp = (helpRef as? String) ?? ""
                    result.append(AXButtonProxy(label: lbl, title: ttl, help: hlp, press: {
                        AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
                    }))
                }
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    axStack.append(contentsOf: children)
                }
            }
        }
        return result
    }

    private func collectAccessibilityTextFields() -> [AXUIElement] {
        let appEl = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return []
        }
        var out: [AXUIElement] = []
        var stack: [AXUIElement] = axWindows
        var visited = 0
        while !stack.isEmpty && visited < 4000 {
            visited += 1
            let el = stack.removeLast()
            var roleRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
            if (roleRef as? String) == kAXTextFieldRole {
                out.append(el)
            }
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                stack.append(contentsOf: children)
            }
        }
        return out
    }

    private func collectAllAccessibilityText(fromAppPid: Bool = true) -> [String] {
        guard fromAppPid else { return [] }
        let appEl = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return []
        }
        var texts: [String] = []
        var stack: [AXUIElement] = axWindows
        var visited = 0
        while !stack.isEmpty && visited < 4000 {
            visited += 1
            let el = stack.removeLast()
            for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
                var valRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, attr as CFString, &valRef) == .success,
                   let str = valRef as? String, !str.isEmpty {
                    texts.append(str)
                }
            }
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                stack.append(contentsOf: children)
            }
        }
        return texts
    }

    private func collectSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var out: [T] = []
        if let matched = root as? T { out.append(matched) }
        for sub in root.subviews {
            out.append(contentsOf: collectSubviews(of: type, in: sub))
        }
        return out
    }

    // MARK: - ШАГ 1: Расследование автозапуска таймера при копировании пароля или фразы

    func testStep1_PassGenDefaultCleanLaunchShouldNotStartTimerAutomatically() async throws {
        // Очищаем явный ключ в AppDefaults, имитируя чистый запуск нового пользователя
        let prev = AppDefaults.shared.object(forKey: "passGenAutoPurgeEnabled")
        AppDefaults.shared.removeObject(forKey: "passGenAutoPurgeEnabled")
        defer {
            if let prev { AppDefaults.shared.set(prev, forKey: "passGenAutoPurgeEnabled") }
            else { AppDefaults.shared.removeObject(forKey: "passGenAutoPurgeEnabled") }
        }

        let monitor = ClipboardMonitor.shared
        monitor.clearAllHistory()
        monitor.autoPurgeSecretsEnabled = false

        // Открываем живое окно MainPanelView и нажимаем кнопку вкладки «Пароли» -> «Скопировать»
        let hosting = NSHostingController(rootView: MainPanelView(monitor: monitor))
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 920, height: 640))
        prepareLiveWindow(window, hosting: hosting)
        defer { window.close() }

        let buttons = collectAccessibilityButtons(from: hosting.view)
        let passTabBtn = buttons.first(where: {
            $0.combinedText.contains("Пароли") || $0.combinedText.contains("PassGen") || $0.combinedText.contains("Passwords")
        })
        if let passTabBtn {
            _ = passTabBtn.press()
        } else {
            // Запасной способ переключения вкладки в живом окне (через хоткей-нотификацию MainPanelView)
            NotificationCenter.default.post(name: Notification.Name("pasteVaultOpenPassGen"), object: nil)
        }
        pumpRunLoop(0.25)

        let passButtons = collectAccessibilityButtons(from: hosting.view)
        let copyBtn = passButtons.first(where: {
            $0.label == "Скопировать" || $0.title == "Скопировать" || $0.label == "Copy" || $0.title == "Copy"
        })
        XCTAssertNotNil(copyBtn, "Кнопка 'Скопировать' на вкладке PassGen должна находиться в живом AX-дереве (найдено кнопок: \(passButtons.count))")
        _ = copyBtn?.press()
        pumpRunLoop(0.15)

        // Ожидаемое поведение режима «включается только вручную»:
        // при выключенном autoPurgeSecretsEnabled скопированный пароль/фраза должен создаваться БЕЗ автотаймера (expiresAt == nil).
        // Баг в MainPanelView.swift:3416: @AppStorage("passGenAutoPurgeEnabled") по умолчанию == true, поэтому таймер 60с запускается сам!
        let latest = try XCTUnwrap(monitor.items.first, "После копирования из PassGen запись должна появиться в истории")
        XCTAssertNil(
            latest.expiresAt,
            "БАГ #1: При чистом профиле и autoPurgeSecretsEnabled=false копирование из PassGen само запустило таймер expiresAt=\(String(describing: latest.expiresAt))!"
        )
    }

    func testStep1_PassGenPasteCreatesOrphanImmediateDestructWorkItem() {
        let monitor = ClipboardMonitor.shared
        monitor.clearAllHistory()
        defer { monitor.clearAllHistory() }

        // Воспроизводим exact flow кнопки «Вставить в ...» в PassGen (MainPanelView.swift:7254-7256, 3767-3769, 3795-3797):
        // recordGeneratedPassword + pasteIntoTargetApp(text:selfDestructAfterSeconds:)
        let secret = "MockGeneratedSecret!99"
        let itemId = monitor.recordGeneratedPassword(secret, ttlSeconds: 60)
        monitor.pasteIntoTargetApp(text: secret, selfDestructAfterSeconds: 60)

        XCTAssertTrue(monitor.hasPendingDestructWorkItem(for: itemId))
        // Пользователь вручную отменяет таймер на карточке:
        monitor.cancelTimerForItem(id: itemId)

        // Ожидаем: не осталось НИ ОДНОГО активного DispatchWorkItem очистки буфера обмена.
        // Баг: pasteIntoTargetApp создал второй таймер под ключом "immediate_<UUID>", который невозможно отменить!
        XCTAssertEqual(
            monitor.pendingDestructWorkItemCount,
            0,
            "БАГ #2: cancelTimerForItem не отменил второй сиротский immediate-таймер буфера обмена (осталось \(monitor.pendingDestructWorkItemCount))!"
        )
    }

    func testStep1_NormalEnglishHyphenatedPhraseFalsePositiveTriggersSecretWithTTL() {
        // Пользователь копирует обычную английскую фразу/slug через дефис (не пароль!)
        let normalPhrases = [
            "apple-banana-cherry-dragon",
            "build-deploy-verify-release",
            "dark-theme-glass-panel"
        ]
        for phrase in normalPhrases {
            let analysis = SecretDetector.inspect(phrase, language: .en)
            XCTAssertFalse(
                analysis.isSensitive,
                "БАГ #3: Обычная фраза '\(phrase)' ложно распознана как пароль (secretKind=\(analysis.secretKind ?? "nil"), recommendedTTL=\(analysis.recommendedTTLSeconds ?? -1))!"
            )
        }
    }

    // MARK: - ШАГ 2: Живое прокликивание реального окна приложения в изолированной песочнице

    func testStep2_LiveMainPanel20TabCyclesSearch500CharsAndDeckInteraction() async throws {
        let monitor = ClipboardMonitor.shared
        monitor.clearAllHistory()
        defer { monitor.clearAllHistory() }

        // Наполняем буфер разнородными записями, включая закреплённую запись
        monitor.captureTextItem("Закреплённая строка для поиска keyword_pin", isMarkedConcealed: false, appName: "Notes")
        if let pinId = monitor.items.first?.id { monitor.togglePin(for: pinId) }
        monitor.captureTextItem("https://example.com/?utm_source=test", isMarkedConcealed: false, appName: "Safari")
        monitor.captureTextItem("#FF5733", isMarkedConcealed: false, appName: "Figma")

        let hosting = NSHostingController(rootView: MainPanelView(monitor: monitor))
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 920, height: 640))
        prepareLiveWindow(window, hosting: hosting)
        defer { window.close() }

        let tabTitles = ["Буфер обмена", "Фрагменты", "Пароли", "Настройки"]
        for cycle in 0..<20 {
            let buttons = collectAccessibilityButtons(from: hosting.view)
            for title in tabTitles {
                if let btn = buttons.first(where: { $0.combinedText.contains(title) }) {
                    _ = btn.press()
                }
            }
            if cycle % 5 == 0 {
                pumpRunLoop(0.02)
            }
        }
        pumpRunLoop(0.1)

        // Возвращаемся на вкладку «Буфер обмена» и стресс-тестируем поле поиска и кнопки фильтрации
        let buttonsAfter = collectAccessibilityButtons(from: hosting.view)
        _ = buttonsAfter.first(where: { $0.combinedText.contains("Буфер обмена") })?.press()
        pumpRunLoop(0.15)

        // Кликаем по фильтрам категорий («Ссылки», «Коды», «Все»)
        for filterTitle in ["Ссылки", "Коды", "Все"] {
            let curBtns = collectAccessibilityButtons(from: hosting.view)
            _ = curBtns.first(where: { $0.combinedText.contains(filterTitle) })?.press()
            pumpRunLoop(0.03)
        }

        let searchFields = collectSubviews(of: NSTextField.self, in: hosting.view)
        let axTextFields = collectAccessibilityTextFields()
        XCTAssertTrue(!searchFields.isEmpty || !axTextFields.isEmpty, "На экране буфера должно быть поле поиска (NSView или AXTextField)")
        let inputs = [
            "keyword_pin",
            "Кириллица поиск",
            "English query",
            "🚀🔐🔥💻",
            "[]{}()*+?^$.\\|",
            String(repeating: "A", count: 500),
            ""
        ]
        if let searchField = searchFields.first {
            for q in inputs {
                searchField.stringValue = q
                NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: searchField)
                pumpRunLoop(0.02)
            }
        } else if let axTF = axTextFields.first {
            for q in inputs {
                _ = AXUIElementSetAttributeValue(axTF, kAXValueAttribute as CFString, q as CFString)
                pumpRunLoop(0.02)
            }
        }

        // Проверяем прокрутку и закрытие окна при переходе на вкладку «Фрагменты»
        let snippetsBtn = collectAccessibilityButtons(from: hosting.view).first(where: {
            $0.combinedText.contains("Фрагменты") || $0.combinedText.contains("Snippets")
        })
        if let snippetsBtn {
            _ = snippetsBtn.press()
        } else {
            NotificationCenter.default.post(name: Notification.Name("pasteVaultOpenSnippets"), object: nil)
        }
        pumpRunLoop(0.2)

        // Открываем вкладку «Настройки» и проверяем наличие контролов
        let settingsBtn = collectAccessibilityButtons(from: hosting.view).first(where: {
            $0.combinedText.contains("Настройки") || $0.combinedText.contains("Settings")
        })
        if let settingsBtn {
            _ = settingsBtn.press()
        } else {
            NotificationCenter.default.post(name: Notification.Name("pasteVaultOpenSettings"), object: nil)
        }
        pumpRunLoop(0.15)

        // Проверяем, что при закрытии окна не остаётся падений или зависаний RunLoop
        window.close()
        pumpRunLoop(0.05)
    }

    func testStep2_LiveSnippetDeck15Snippets8MacrosScrollZonesScrubberAndWindowClose() throws {
        // 15 фрагментов: длинный текст, изображение, 8 макросов
        var snippets: [QuickSnippetItem] = []
        let all8Macros = "{{date}} | {{time}} | {{datetime}} | {{weekday}} | {{iso}} | {{user}} | {{uuid}} | {{app}}"
        for i in 0..<15 {
            snippets.append(QuickSnippetItem(
                id: "snip_deck_\(i)",
                title: String(format: "Сниппет #%02d", i),
                content: i == 0 ? (all8Macros + "\n" + String(repeating: "Длинная строка карточки для скролла.\n", count: 25)) : "Body \(i) \(all8Macros)",
                category: "Разработка",
                isPinned: (i % 5 == 0),
                imagePath: i == 1 ? "/tmp/fake_preview.png" : nil,
                useCount: (15 - i) * 3,
                createdAt: Date().addingTimeInterval(Double(-i * 120)).timeIntervalSince1970
            ))
        }

        // Проверка всех 5 сортировок (pinned / mostUsed / newest / oldest / alphabetical)
        for order in ["pinned", "mostUsed", "newest", "oldest", "alphabetical"] {
            let sorted = SnippetDeckHelper.sortSnippets(snippets, order: order, pinnedSnapshotIds: ["snip_deck_0", "snip_deck_5"])
            XCTAssertEqual(sorted.count, 15, "Сортировка \(order) должна сохранять все 15 фрагментов")
        }

        // Скраббер и 10 точек
        let dots = SnippetDeckHelper.visibleDotIndices(total: 15, activeIndex: 7, maxVisibleDots: 10)
        XCTAssertEqual(dots.count, 10)
        XCTAssertEqual(SnippetDeckHelper.scrubberTargetIndex(locationY: 199, capsuleHeight: 200, total: 15), 14)
        XCTAssertLessThan(SnippetDeckHelper.continuousStepInterval(stepCount: 25), SnippetDeckHelper.continuousStepInterval(stepCount: 1))

        // Проверка раскрытия всех 8 макросов
        let expanded = SnippetMacroEngine.expand(all8Macros, targetAppName: "Xcode")
        XCTAssertFalse(expanded.contains("{{date}}"))
        XCTAssertFalse(expanded.contains("{{time}}"))
        XCTAssertFalse(expanded.contains("{{datetime}}"))
        XCTAssertFalse(expanded.contains("{{weekday}}"))
        XCTAssertFalse(expanded.contains("{{iso}}"))
        XCTAssertFalse(expanded.contains("{{user}}"))
        XCTAssertFalse(expanded.contains("{{uuid}}"))
        XCTAssertTrue(expanded.contains("Xcode"))

        // Живое окно с DeckScrollWheelCatcher и проверкой всех 4 зон прокрутки + закрытия
        var wheelSteps = 0
        let catcher = DeckScrollWheelCatcher(isEnabled: true, frontOffsetY: 82) { _ in
            wheelSteps += 1
        }
        let host = NSHostingController(rootView: catcher.frame(width: 600, height: 340))
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 600, height: 340))
        win.makeKeyAndOrderFront(nil)
        pumpRunLoop(0.1)

        let bounds = NSRect(x: 0, y: 0, width: 600, height: 340)
        let frontRect = DeckScrollWheelCatcher.frontTextRect(in: bounds, frontOffsetY: 82)
        // Верх заголовка передней карточки: y < frontRect.minY -> должен перелистывать колоду!
        // Середина тела карточки: y == frontRect.midY, x == 300 -> НЕ должен перелистывать колоду (внутри frontTextRect)!
        // Нижняя полоса 12pt (cardBottom - 5): frontRect расширен до cardBottom, значит НЕ перелистывает!
        // Боковое поле (x = 40 < бокового отступа карточки, но внутри frontTextRect из-за full-width)!
        let centerY = bounds.height / 2
        let cardTop = centerY + 82 - 125
        let cardBottom = cardTop + 250
        XCTAssertFalse(frontRect.contains(NSPoint(x: 300, y: cardTop + 20)), "Заголовок карточки должен перелистывать колоду")
        XCTAssertTrue(frontRect.contains(NSPoint(x: 300, y: frontRect.midY)), "Центр текста должен прокручиваться внутри карточки")
        XCTAssertTrue(frontRect.contains(NSPoint(x: 300, y: cardBottom - 5)), "Нижние 12 pt карточки после фикса 30.34 внутри frontTextRect")

        win.close()
        pumpRunLoop(0.05)
        XCTAssertEqual(wheelSteps, 0)
    }

    func testStep2_LiveScreenshotEditorTinyNarrowTransparentAndLayoutShortcuts() throws {
        // 1. Проверяем поведение в очень узком окне (< 400 pt ширины, например 360×600)
        let engine = ScreenshotEditorEngine()
        let (normImg, _) = try makeTransparentPNGImage(size: NSSize(width: 320, height: 180))
        var canvasSize = CGSize(width: 320, height: 180)
        var panOffset = CGSize.zero

        let narrowFooter = ScreenshotEditorBottomShortcutBar(
            engine: engine,
            theme: .obsidian,
            currentFont: .inter,
            windowOpacity: 0.9
        )
        let footerHost = NSHostingView(rootView: narrowFooter)
        let footerMinSize = footerHost.fittingSize
        // Ожидаем: при ширине < 400 pt футер редактора должен помещаться в узкое окно (< 380 pt) без обрезки!
        XCTAssertLessThanOrEqual(
            footerMinSize.width,
            390,
            "БАГ #4: Минимальная ширина нижней панели ScreenshotEditorBottomShortcutBar = \(footerMinSize.width) pt (> 390 pt) — в узком окне < 400 pt подписи/капсулы обрежутся!"
        )

        // 2. Открытие ScreenshotEditorWorkspaceView в живом узком окне 360×600
        let workspace = ScreenshotEditorWorkspaceView(
            engine: engine,
            sourceImage: normImg,
            theme: .obsidian,
            currentFont: .inter,
            windowOpacity: 0.9,
            scaleToFit: true,
            zoomScale: 2.25,
            lastCanvasSize: Binding(get: { canvasSize }, set: { canvasSize = $0 }),
            panOffset: Binding(get: { panOffset }, set: { panOffset = $0 })
        )
        let wsHost = NSHostingController(rootView: workspace)
        let wsWindow = NSWindow(contentViewController: wsHost)
        wsWindow.setContentSize(NSSize(width: 360, height: 600))
        wsWindow.makeKeyAndOrderFront(nil)
        defer { wsWindow.close() }
        pumpRunLoop(0.2)

        // 3. Проверка 1x1 PNG и прозрачного PNG
        let (tinyImg, _) = try makeTransparentPNGImage(size: NSSize(width: 1, height: 1))
        let renderedTiny = engine.renderAnnotatedImage(baseImage: tinyImg, canvasSize: CGSize(width: 1, height: 1), zoomScale: 1.0)
        XCTAssertNotNil(renderedTiny, "Редактор должен корректно экспортировать даже 1×1 PNG")

        let (alphaImg, _) = try makeTransparentPNGImage(size: NSSize(width: 120, height: 80), alphaRect: NSRect(x: 60, y: 0, width: 60, height: 80))
        engine.selectedTool = .arrow
        _ = engine.addArrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50))
        engine.selectedTool = .text
        let tid = engine.addText("Line 1\nLine 2", at: CGPoint(x: 30, y: 30))
        engine.selectedTool = .shape
        _ = engine.addShape(kind: .roundedRect, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 80, y: 60))
        engine.selectedTool = .highlighter
        engine.highlighterOpacity = 0.0
        _ = engine.addBoxHighlighter(rect: CGRect(x: 5, y: 5, width: 35, height: 15), color: .amber)
        engine.highlighterOpacity = 1.0
        _ = engine.addBoxHighlighter(rect: CGRect(x: 5, y: 25, width: 35, height: 15), color: .sky)
        engine.selectedTool = .step
        _ = engine.addStepPin(at: CGPoint(x: 70, y: 70))
        engine.selectedTool = .pixelate
        _ = engine.addPixelate(rect: CGRect(x: 15, y: 15, width: 30, height: 30))
        engine.selectedTool = .eraser
        _ = engine.addEraserStroke(points: [CGPoint(x: 20, y: 20), CGPoint(x: 25, y: 25)], red: 0, green: 0, blue: 0, alpha: 1)

        let renderedAlpha = engine.renderAnnotatedImage(baseImage: alphaImg, canvasSize: CGSize(width: 120, height: 80))
        XCTAssertNotNil(renderedAlpha)
        if let cg = renderedAlpha?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cg)
            let transparentCorner = rep.colorAt(x: max(0, rep.pixelsWide - 2), y: max(0, rep.pixelsHigh - 2))
            XCTAssertEqual(transparentCorner?.alphaComponent ?? 1.0, 0.0, accuracy: 0.05, "Прозрачная область PNG должна оставаться прозрачной")
        }

        // 4. Проверка Undo/Redo в RU ('я') и EN ('z'), подсветки Shift и Delete без выделения
        let countBefore = engine.annotations.count
        XCTAssertEqual(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: "я", keyCode: 6), true)
        XCTAssertEqual(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: "z", keyCode: 6), true)
        XCTAssertFalse(ScreenshotEditorEngine.isPureShiftModifier([.command, .shift]))
        XCTAssertTrue(ScreenshotEditorEngine.isPureShiftModifier([.shift]))
        engine.undo()
        XCTAssertEqual(engine.annotations.count, countBefore - 1)
        engine.redo()
        XCTAssertEqual(engine.annotations.count, countBefore)

        engine.selectedAnnotationId = nil
        engine.editingTextAnnotationId = nil
        engine.deleteSelectedAnnotation()
        XCTAssertEqual(engine.annotations.count, countBefore, "Delete без выделения не должен удалять аннотации")

        // Ступенчатый Esc
        engine.activeSubmenu = .text
        XCTAssertEqual(engine.handleEscape(), .closedSubmenu)
        engine.editingTextAnnotationId = tid
        XCTAssertEqual(engine.handleEscape(), .committedText)
        engine.selectedAnnotationId = tid
        XCTAssertEqual(engine.handleEscape(), .clearedSelection)
        XCTAssertEqual(engine.handleEscape(), .closeEditor)
    }

    // MARK: - ШАГ 3.1: Буфер и память (экстремальные строки, \0, 5 МБ, SQLi, сиротские файлы, 1000 записей)

    func testStep3_1_NullByteAndEmptyAndHuge5MBAndSQLInjectionAndOrphanFiles() async throws {
        let db = DatabaseManager.shared
        let supportDir = try DatabaseManager.pasteVaultSupportDirectory()
        try? await db.initializeDatabase()
        try await db.clearAllHistory()
        let monitor = ClipboardMonitor.shared
        monitor.clearAllHistoryInMemory()
        defer { monitor.clearAllHistory() }

        // 1. Нуль-байт \0 в SQLite: sqlite3_bind_text(..., -1, ...) обрезает строку по \0!
        let textWithNull = "prefix_part\0secret_after_null"
        let nullId = "null_byte_test_\(UUID().uuidString)"
        _ = try await db.upsertItem(
            id: nullId,
            contentType: .text,
            textPreview: textWithNull,
            rawPayload: Data(textWithNull.utf8),
            sourceBundleId: nil,
            sourceAppName: "Test",
            isSensitive: false,
            secretKind: nil,
            ttlSeconds: nil
        )
        let fetchedNull = try await db.queryItems(searchQuery: "prefix_part", limit: 10).first(where: { $0.id == nullId })
        XCTAssertEqual(
            fetchedNull?.textPreview,
            textWithNull,
            "БАГ #5: SQLite обрезал строку с нуль-байтом \\0 (ожидалось '\(textWithNull.debugDescription)', получено '\(fetchedNull?.textPreview.debugDescription ?? "nil")')!"
        )
        try? await db.deleteItem(id: nullId)

        // 2. Огромный текст 5 МБ (усечение captureTextItem до 500_000) и RTL / Zalgo
        let huge5MB = String(repeating: "X", count: 5_242_880)
        monitor.captureTextItem(huge5MB, appName: "HugeApp")
        XCTAssertEqual(monitor.items.first?.textPreview.count, 500_000)

        let rtlZalgo = "مرحبا\u{200F} 世界 e\u{0301}\u{0302}\u{0303}\u{0308}"
        monitor.captureTextItem(rtlZalgo, appName: "RTLApp")
        XCTAssertEqual(monitor.items.first?.textPreview, rtlZalgo)

        // 3. Пустая строка и пробелы — captureTextItem через pollPasteboard / check empty
        monitor.captureTextItem("   \t\n  ", appName: "BlankApp")

        // 4. SQL-инъекции и спецсимволы LIKE ("' OR 1=1 --", "%", "_")
        let sqliQueries = ["' OR 1=1 --", "%", "_"]
        for q in sqliQueries {
            let res = try await db.queryItems(searchQuery: q, limit: 50)
            XCTAssertFalse(
                res.contains(where: { $0.textPreview == rtlZalgo }),
                "LIKE-запрос '\(q)' не должен срабатывать как wildcard на несовпадающую запись"
            )
        }

        // 5. Проверка утечки медиафайлов в Screenshots/ при вытеснении старых картинок через enforceHistoryLimit()
        let screenshotsDir = supportDir.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
        let prevLimit = monitor.maxHistoryLimit
        monitor.maxHistoryLimit = 2
        defer { monitor.maxHistoryLimit = prevLimit }

        let (img1, _) = try makeTransparentPNGImage(size: NSSize(width: 40, height: 40))
        let img1Tiff = try XCTUnwrap(img1.tiffRepresentation)
        monitor.captureImageItem(img1, tiffData: img1Tiff, appName: "Shot1")
        let shot1Id = try XCTUnwrap(monitor.items.first?.id)
        let shot1File = screenshotsDir.appendingPathComponent("\(shot1Id).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: shot1File)

        // Вытесняем img1 двумя новыми текстовыми вставками (enforceHistoryLimit -> Task { deleteItem })
        monitor.captureTextItem("push_out_1", appName: "Test")
        monitor.captureTextItem("push_out_2", appName: "Test")
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: shot1File.path),
            "При вытеснении картинки по maxHistoryLimit файл в Screenshots/ должен удаляться"
        )

        // 6. Производительность поиска и фильтрации при 1000 записях в БД SQLite
        for i in 0..<1000 {
            _ = try await db.upsertItem(
                id: "perf_\(i)",
                contentType: .text,
                textPreview: "Stress record number \(i) payload_\(i % 17)",
                rawPayload: Data("Stress \(i)".utf8),
                sourceBundleId: nil,
                sourceAppName: "Stress",
                isSensitive: false,
                secretKind: nil,
                ttlSeconds: nil
            )
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        let searchHits = try await db.queryItems(searchQuery: "payload_7", limit: 200)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        XCTAssertGreaterThan(searchHits.count, 10)
        XCTAssertLessThan(elapsedMs, 500.0, "Поиск по 1000 записям в SQLite должен выполняться быстрее 500 мс (факт: \(elapsedMs) мс)")
        try await db.clearAllHistory()
    }

    // MARK: - ШАГ 3.2: PassGen граничные длины, 100 генераций, SecretDetector, гонка секретов

    func testStep3_2_PassGenBoundaries100RunsAndSecretDetectorFalsePositives() {
        // Граничная длина 1 при 4 включённых классах должна возвращать ровно запрошенный 1 символ
        let tiny = PassGenerator.generatePassword(length: 1, includeUppercase: true, includeDigits: true, includeSymbols: true)
        XCTAssertEqual(tiny.secret.count, 1, "PassGenerator должен возвращать точную запрошенную длину даже если length < числа классов символов")

        var seenPasswords = Set<String>()
        var seenMnemonics = Set<String>()
        for _ in 0..<100 {
            let p = PassGenerator.generatePassword(length: 18, includeUppercase: true, includeDigits: true, includeSymbols: true)
            XCTAssertEqual(p.secret.count, 18)
            seenPasswords.insert(p.secret)

            let m = PassGenerator.generateMnemonic(wordCount: 5)
            XCTAssertEqual(m.secret.split(separator: "-").count, 5)
            seenMnemonics.insert(m.secret)
        }
        XCTAssertEqual(seenPasswords.count, 100, "100 сгенерированных паролей должны быть уникальны")
        XCTAssertEqual(seenMnemonics.count, 100, "100 мнемонических фраз должны быть уникальны")

        // Ложные срабатывания SecretDetector: обычные русские/английские фразы без цифр не должны становиться Паролем!
        let benignSamples = [
            "Привет, как твои дела? Всё отлично!",
            "Hello world! How are you doing today?",
            "/Users/alex/Documents/my-file.txt",
            "user.name+tag@company.co.uk",
            "https://api.example.com/v1/users",
            #"{"status":"ok","items":[1,2,3]}"#,
            "Привет,Мир!" // Русская фраза без пробелов со знаком препинания — проверяем, не сломается ли!
        ]
        for s in benignSamples {
            let res = SecretDetector.inspect(s)
            XCTAssertFalse(
                res.isSensitive,
                "Обычная строка '\(s)' не должна ложно помечаться как секрет (secretKind=\(res.secretKind ?? "nil"))"
            )
        }

        // Длинный ключ > 2000 символов (PKCS#8 PRIVATE KEY)
        let longBody = String(repeating: "ABCD1234efgh5678", count: 140)
        let pkcs8 = "-----BEGIN PRIVATE KEY-----\n\(longBody)\n-----END PRIVATE KEY-----"
        XCTAssertGreaterThan(pkcs8.count, 2000)
        XCTAssertTrue(SecretDetector.inspect(pkcs8, language: .en).isSensitive)

        // Быстрая смена статуса секрета и удаление
        let monitor = ClipboardMonitor.shared
        monitor.clearAllHistory()
        defer { monitor.clearAllHistory() }
        let id = monitor.recordGeneratedPassword("RacePass!2026#99", ttlSeconds: 60)
        let innocentId = monitor.recordGeneratedPassword("InnocentPass!2026#11", ttlSeconds: 60)
        monitor.toggleSecretStatus(for: id)
        monitor.toggleSecretStatus(for: id)
        XCTAssertTrue(monitor.hasPendingDestructWorkItem(for: innocentId), "Отмена/переключение чужого секрета не должно трогать другой")
        monitor.clearAllHistory()
    }

    // MARK: - ШАГ 3.3: Категории, Редактор фрагментов, !AXIsProcessTrusted, Экспорт

    func testStep3_3_CategoriesSnippetsExportEdgeCases() async throws {
        let db = DatabaseManager.shared
        try? await db.initializeDatabase()

        // Категории с пробелами, 100+ символами, эмодзи, NFD/NFC, резерв
        let emojiName = sanitizeCategoryNameInput("🚀 Космос   ")
        XCTAssertEqual(emojiName, "🚀 Космос")
        let long100 = sanitizeCategoryNameInput(String(repeating: "Я", count: 120))
        XCTAssertEqual(long100.count, 20)

        let reserved = ["Все", "All", "Нет категорий", "All Categories", "No Categories"]
        for r in reserved {
            let check = SnippetCategoryValidator.validateCandidate(r, existingCategories: [])
            XCTAssertFalse(check.isValid)
            XCTAssertTrue(check.isReserved)
        }

        // Удаление ВСЕХ категорий до 0 и пересоздание
        let allCats = await db.fetchSnippetCategories()
        for cat in allCats {
            try await db.deleteSnippetCategoryAndSnippets(id: cat.id)
        }
        let afterZero = await db.fetchSnippetCategories()
        XCTAssertEqual(afterZero.count, 0)
        let recreated = await db.createSnippetCategory(name: "Восстановленная", iconName: "folder.fill")
        XCTAssertNotNil(recreated)

        // Вставка фото в SnippetNSTextView через Cmd+V первый и второй раз
        let tv = SnippetNSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var callbackCount = 0
        tv.onPasteImage = { _ in callbackCount += 1 }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let (img, _) = try makeTransparentPNGImage(size: NSSize(width: 16, height: 16))
        pb.clearContents()
        pb.writeObjects([img])
        tv.handlePaste(from: pb) {}
        tv.handlePaste(from: pb) {}
        XCTAssertEqual(callbackCount, 2)

        // Экспорт с опасными символами "../../hack:test*" и пустым текстом
        let dangerousName = CardFileExporter.defaultFileName(for: "../../hack:test*", format: .txt)
        XCTAssertFalse(dangerousName.contains("/"), "Имя экспортируемого файла не должно содержать '/'")
        XCTAssertFalse(dangerousName.contains(":"), "Имя экспортируемого файла не должно содержать ':'")
        XCTAssertFalse(dangerousName.contains("*"), "Имя экспортируемого файла не должно содержать '*'")
        XCTAssertFalse(dangerousName.contains(".."), "БАГ #6: В имени файла '../../hack:test*' остались двойные точки '..'!")

        for fmt in CardExportFormat.allCases {
            XCTAssertFalse(CardFileExporter.defaultFileName(for: "   \n  ", format: fmt).isEmpty)
            let emptyData = try CardFileExporter.generateExportData(from: "", format: fmt, isCode: false)
            if fmt == .docx {
                XCTAssertTrue(emptyData.starts(with: Data([0x50, 0x4B])), ".docx должен генерировать валидный OOXML ZIP даже для пустой строки")
            }
        }

        // Проверка очистки сиротских snippet_img_* файлов на диске
        let supportDir = try DatabaseManager.pasteVaultSupportDirectory()
        let imagesDir = supportDir.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let orphanFile = imagesDir.appendingPathComponent("snippet_img_orphan_\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: orphanFile)
        await db.cleanupUnusedSnippetImageFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanFile.path), "Осиротевший snippet_img_* должен удаляться с диска")

        // Восстановим/почистим за собой временную категорию
        if let recreated { try? await db.deleteSnippetCategoryAndSnippets(id: recreated.id) }
    }

    func testStep3_5_HistoryStress100CapturesConcurrentPinDeleteAndHotkeysAndLegacyBackup() async throws {
        let monitor = ClipboardMonitor.shared
        monitor.clearAllHistory()
        defer { monitor.clearAllHistory() }

        // 1. 100 быстрых вставок + переполнение лимита (с закреплённым элементом) + параллельный pin/delete
        let prevLimit = monitor.maxHistoryLimit
        monitor.maxHistoryLimit = 25
        defer { monitor.maxHistoryLimit = prevLimit }

        monitor.captureTextItem("Pinned survivor", appName: "Test")
        let pinnedId = try XCTUnwrap(monitor.items.first?.id)
        monitor.togglePin(for: pinnedId)

        for i in 0..<100 {
            monitor.captureTextItem("Rapid burst item #\(i)", appName: "StressApp")
            if i % 7 == 0, let toDelete = monitor.items.last(where: { !$0.isPinned })?.id {
                monitor.items.removeAll { $0.id == toDelete }
                Task { try? await DatabaseManager.shared.deleteItem(id: toDelete) }
            }
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertLessThanOrEqual(monitor.items.count, 25, "enforceHistoryLimit должен удерживать историю в пределах maxHistoryLimit")
        XCTAssertTrue(monitor.items.contains(where: { $0.id == pinnedId }), "Закреплённый элемент должен пережить переполнение буфера")

        // 2. Хоткеи: конфликты, одиночная клавиша без модификаторов, раскладки RU/EN
        let sm = ShortcutManager.shared
        defer { sm.resetToDefaults() }
        sm.resetToDefaults()

        // Конфликт с уже занятой комбинацией (по умолчанию openPassGen == config[.openPassGen])
        let existingPassCombo = sm.config[.openPassGen]
        let conflictRes = sm.validate(combo: existingPassCombo, for: .openSnippets, in: .ru)
        if case .internalConflict = conflictRes { } else {
            XCTFail("Ожидался внутренний конфликт хоткея, получено: \(conflictRes)")
        }

        // Одиночная клавиша 'A' без модификаторов для togglePanel запрещается,
        // проверяем также для clearHistory (опасное действие может быть привязано на одну букву 'A'!)
        let bareA = KeyCombo(keyCode: 0, modifiers: 0, displayString: "A")
        let togglePanelBare = sm.validate(combo: bareA, for: .togglePanel, in: .ru)
        if case .missingModifier("A") = togglePanelBare { } else {
            XCTFail("Для togglePanel одиночная клавиша без модификаторов должна отклоняться как .missingModifier(\"A\"), получено: \(togglePanelBare)")
        }
        let clearHistoryBare = sm.validate(combo: bareA, for: .clearHistory, in: .ru)
        if case .valid = clearHistoryBare {
            XCTFail("БАГ (Хоткеи): В настройках разрешено назначить одиночную клавишу 'A' без модификаторов (⌘/⌥/⌃) на опасное действие clearHistory!")
        }

        // Раскладко-независимое распознавание Cmd+Z при русской раскладке ('я', keyCode=6)
        let cmdZ = KeyCombo(keyCode: 6, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘Z")
        if let ruZEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "я",
            charactersIgnoringModifiers: "я",
            isARepeat: false,
            keyCode: 6
        ) {
            XCTAssertTrue(cmdZ.matches(event: ruZEvent), "Cmd+Z должен срабатывать в русской раскладке по keyCode=6")
        }

        // 3. Проверка импорта старого JSON v1 (Double timestamp) и PVENC1: в режимах Merge и Replace,
        // плюс проверка restoreArchive с path traversal "../../etc/passwd"
        let db = DatabaseManager.shared
        try? await db.initializeDatabase()

        // 3a. Проверяем legacy JSON v1 БЕЗ поля useCount (ожидаем обратную совместимость, ловим поломку!)
        let v1WithoutUseCount = """
        {
          "version": 1,
          "createdAt": 1700000000.0,
          "appVersion": "1.0.0",
          "clipboardItems": [
            {
              "id": "v1_old_item",
              "contentType": 0,
              "textPreview": "Legacy v1 without useCount",
              "contentHash": "abc123old",
              "isSensitive": false,
              "isPinned": true,
              "createdAt": 1700000000.0
            }
          ]
        }
        """
        let oldV1URL = FileManager.default.temporaryDirectory.appendingPathComponent("destructive_oldv1_\(UUID().uuidString).pastevaultbackup")
        defer { try? FileManager.default.removeItem(at: oldV1URL) }
        try Data(v1WithoutUseCount.utf8).write(to: oldV1URL)
        do {
            _ = try BackupManager.loadArchiveFromFile(from: oldV1URL, password: nil)
        } catch {
            XCTFail("БАГ (Обратная совместимость бэкапов): Старый архив v1 без поля useCount не декодируется: \(error)")
        }

        // 3b. Проверяем JSON v1 (с useCount) + PVENC1: в режимах Merge и Replace + DupBackupCat + ../../etc/passwd
        let v1Json = """
        {
          "version": 1,
          "createdAt": 1700000000.0,
          "appVersion": "1.0.0",
          "clipboardItems": [
            {
              "id": "v1_item_1",
              "contentType": 0,
              "textPreview": "Legacy v1 text",
              "contentHash": "abc123",
              "isSensitive": false,
              "isPinned": true,
              "useCount": 1,
              "createdAt": 1700000000.0
            }
          ],
          "snippets": [
            {
              "id": "v1_snip_1",
              "title": "V1 Snip",
              "content": "hello v1",
              "category": "DupBackupCat",
              "isPinned": false,
              "imagePath": "../../etc/passwd",
              "useCount": 2,
              "createdAt": 1700000000.0
            },
            {
              "id": "v1_snip_2",
              "title": "V1 Snip 2",
              "content": "hello v1 second",
              "category": "DupBackupCat",
              "isPinned": false,
              "useCount": 1,
              "createdAt": 1700000000.0
            }
          ]
        }
        """
        let v1URL = FileManager.default.temporaryDirectory.appendingPathComponent("destructive_v1_\(UUID().uuidString).pastevaultbackup")
        let pvenc1URL = FileManager.default.temporaryDirectory.appendingPathComponent("destructive_pvenc1_\(UUID().uuidString).pastevaultbackup")
        defer {
            try? FileManager.default.removeItem(at: v1URL)
            try? FileManager.default.removeItem(at: pvenc1URL)
        }
        do {
            try Data(v1Json.utf8).write(to: v1URL)
            let v1Archive = try BackupManager.loadArchiveFromFile(from: v1URL, password: nil)
            XCTAssertEqual(v1Archive.clipboardItems?.first?.textPreview, "Legacy v1 text")

            // Проверяем также legacy PVENC1: архив (режим Merge + Replace) — payload кодируется в base64 после 'PVENC1:'
            let legacyKey = SymmetricKey(data: SHA256.hash(data: Data("com.pastevault.app.backup.aesgcm.v1".utf8)))
            let sealedV1 = try AES.GCM.seal(Data(v1Json.utf8), using: legacyKey)
            var pvenc1Data = Data("PVENC1:".utf8)
            pvenc1Data.append((sealedV1.combined ?? Data()).base64EncodedData())
            try pvenc1Data.write(to: pvenc1URL)
            let loadedPVENC1 = try BackupManager.loadArchiveFromFile(from: pvenc1URL, password: nil)
            XCTAssertEqual(loadedPVENC1.snippets?.first?.title, "V1 Snip")

            // Восстанавливаем в режиме Merge
            var restoredSnippets: [QuickSnippetItem] = []
            try await BackupManager.restoreArchive(
                v1Archive,
                restoreClipboard: true,
                restoreSnippets: true,
                restoreSettings: false,
                mergeMode: true,
                monitor: monitor,
                currentSnippets: [],
                onUpdateSnippets: { restoredSnippets = $0 }
            )
            XCTAssertNil(restoredSnippets.first?.imagePath, "Path traversal '../../etc/passwd' должен отбрасываться при restoreArchive")

            // Проверяем, не создались ли дубликаты категории "DupBackupCat" при восстановлении 2 фрагментов одной новой категории
            let catsAfterRestore = await db.fetchSnippetCategories()
            let dupMatches = catsAfterRestore.filter { $0.name == "DupBackupCat" }
            XCTAssertLessThanOrEqual(dupMatches.count, 1, "Восстановление не должно плодить дубликаты категории (найдено \(dupMatches.count))")

            // Восстанавливаем в режиме Replace
            try await BackupManager.restoreArchive(
                loadedPVENC1,
                restoreClipboard: true,
                restoreSnippets: true,
                restoreSettings: false,
                mergeMode: false,
                monitor: monitor,
                currentSnippets: restoredSnippets,
                onUpdateSnippets: { restoredSnippets = $0 }
            )
            XCTAssertEqual(restoredSnippets.count, 2)
        } catch {
            XCTFail("Ошибка на шаге v1/PVENC1 бэкапа: \(error)")
        }

        // Уберём тестовую категорию DupBackupCat
        for cat in await db.fetchSnippetCategories() where cat.name == "DupBackupCat" {
            try? await db.deleteSnippetCategoryAndSnippets(id: cat.id)
        }

        // Проверка: при вставке фрагмента без Accessibility checkAccessibilityPermission() возвращает false
        if !AXIsProcessTrusted() {
            XCTAssertFalse(monitor.checkAccessibilityPermission())
        }

        // Проверка .docx в тёмном интерфейсе (NSAppearanceName.darkAqua) — проверка цвета текста
        var darkDocx = Data()
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            darkDocx = (try? CardFileExporter.generateExportData(from: "Dark mode test text", format: .docx, isCode: false)) ?? Data()
        }
        XCTAssertTrue(darkDocx.starts(with: Data([0x50, 0x4B])))

        await db.deleteAllSnippets()
        monitor.clearAllHistory()
    }

    // MARK: - ШАГ 3.4: Бэкапы PVENC2/PVENC1/v1, Хоткеи и Локализация RU/EN

    func testStep3_4_BackupsCorruptedAndTraversalAndShortcutsAndLocalizationLeaks() async throws {
        let db = DatabaseManager.shared
        try? await db.initializeDatabase()

        // 1. PVENC2 с паролем со смайлами и пробелами, 50% обрезание и path traversal в imagePath
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("destructive_pvenc2_\(UUID().uuidString).pastevaultbackup")
        let truncatedURL = FileManager.default.temporaryDirectory.appendingPathComponent("destructive_trunc_\(UUID().uuidString).pastevaultbackup")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: truncatedURL)
        }

        let emojiPassword = "🔐 Пароль 2026! 🚀"
        let snippetId = "evil_snip_\(UUID().uuidString)"
        let archive = PasteVaultBackupArchive(
            version: 2,
            createdAt: Date(),
            appVersion: "1.0.2",
            clipboardItems: [],
            snippets: [
                QuickSnippetItem(
                    id: snippetId,
                    title: "Traversal Snippet",
                    content: "safe body",
                    category: "Work",
                    isPinned: false,
                    imagePath: "../../etc/passwd"
                )
            ],
            settings: nil
        )
        try BackupManager.exportArchiveToFile(archive: archive, to: tempURL, password: emojiPassword)
        let loaded = try BackupManager.loadArchiveFromFile(from: tempURL, password: emojiPassword)
        XCTAssertEqual(loaded.snippets?.first?.title, "Traversal Snippet")

        // Обрезанный на 50% файл должен честно кидать ошибку
        let fullData = try Data(contentsOf: tempURL)
        let halfData = fullData.prefix(fullData.count / 2)
        try halfData.write(to: truncatedURL)
        XCTAssertThrowsError(try BackupManager.loadArchiveFromFile(from: truncatedURL, password: emojiPassword))

        // 2. Проверка утечки русского текста в режиме appLanguage == "en"
        let prevLang = AppDefaults.shared.string(forKey: "appLanguage")
        AppDefaults.shared.set("en", forKey: "appLanguage")
        defer {
            if let prevLang { AppDefaults.shared.set(prevLang, forKey: "appLanguage") }
            else { AppDefaults.shared.removeObject(forKey: "appLanguage") }
        }

        // Проверяем: при включённом appLanguage == "en" не просачиваются ли русские строки в моделях/теговых хелперах
        let colorTags = SmartClassifier.tags(for: "#AABBCC", contentType: .color, isSensitive: false, language: .en)
        XCTAssertFalse(colorTags.contains("Color") || colorTags.contains("Цвет"), "У карточки цвета не должно быть дублирующего тега Color/Цвет: \(colorTags)")

        let enUtmTags = SmartClassifier.tags(for: "https://example.com/?utm_source=1", contentType: .url, isSensitive: false, language: .en)
        XCTAssertTrue(enUtmTags.contains("#UTM-tracker"), "В EN тег ссылки должен быть '#UTM-tracker', получено: \(enUtmTags)")

        let enFileTags = SmartClassifier.tags(for: "[File: demo.pdf]", contentType: .file, isSensitive: false, language: .en)
        XCTAssertTrue(enFileTags.contains("#File"), "В EN тег файла должен быть '#File', получено: \(enFileTags)")

        let macroExpandedEn = SnippetMacroEngine.expand(
            "App={{app}} Day={{weekday}}",
            targetAppName: nil,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            locale: Locale(identifier: "en_US")
        )
        XCTAssertFalse(macroExpandedEn.contains("Мак"), "При EN не должно быть кириллицы в {{app}}")

        // 3. Проверка дефолтов MainPanelView (selectedSnippetCategory, newSnippetCategory):
        // В MainPanelView.swift:3239-3252 состояния инициализируются хардкодом "Все" и "Разработка" вместо "All" / базовой категории!
        // Проверим это живым окном при appLanguage = "en": отобразится ли кириллица в фильтре сниппетов / модале создания!
        let monitor = ClipboardMonitor.shared
        let hosting = NSHostingController(rootView: MainPanelView(monitor: monitor))
        let win = NSWindow(contentViewController: hosting)
        win.setContentSize(NSSize(width: 920, height: 640))
        win.makeKeyAndOrderFront(nil)
        defer { win.close() }
        pumpRunLoop(0.2)

        let enButtons = collectAccessibilityButtons(from: hosting.view)
        if let snBtn = enButtons.first(where: { $0.combinedText.contains("Snippets") }) {
            _ = snBtn.press()
            pumpRunLoop(0.2)
        } else {
            NotificationCenter.default.post(name: Notification.Name("pasteVaultOpenSnippets"), object: nil)
            pumpRunLoop(0.2)
        }
        // Нажимаем '+' создания нового фрагмента на вкладке Snippets в EN-режиме:
        let addBtn = collectAccessibilityButtons(from: hosting.view).first(where: {
            $0.combinedText.contains("New Snippet") || $0.combinedText.contains("Создать") || $0.combinedText.contains("Add") || $0.combinedText.contains("plus")
        })
        _ = addBtn?.press()
        pumpRunLoop(0.15)
        let textsAfterOpen = (collectAccessibilityButtons(from: hosting.view).map(\.combinedText) + collectAllAccessibilityText()).joined(separator: " | ")
        XCTAssertFalse(
            textsAfterOpen.contains("Разработка") || textsAfterOpen.contains("Все"),
            "БАГ #7 (EN локализация): При открытом EN-интерфейсе на вкладке Snippets просочилась кириллица: \(textsAfterOpen)"
        )
    }
}
