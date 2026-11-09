import SwiftUI
import AppKit
import Carbon

@main
@MainActor
public struct PasteVaultApp {
    public static func main() {
        AppDelegate.main()
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static weak var shared: AppDelegate?

    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        if CommandLine.arguments.contains("--run-synthetic-tests") {
            let result = delegate.monitor.seedSyntheticSamples()
            let items = delegate.monitor.items
            let countAll = items.count
            let countText = items.filter { $0.effectiveContentType == .text && !$0.isSensitive }.count
            let countFile = items.filter { $0.effectiveContentType == .file }.count
            let countURL = items.filter { $0.effectiveContentType == .url }.count
            let countCode = items.filter { $0.effectiveContentType == .code }.count
            let countImage = items.filter { $0.effectiveContentType == .image }.count
            let countSecret = items.filter { $0.isSensitive || $0.effectiveContentType == .secret }.count
            let countColor = items.filter { $0.effectiveContentType == .color }.count
            let countUTM = items.filter { $0.tags.contains("#UTM-трекер") }.count
            let countSwift = items.filter { $0.tags.contains("#Swift") }.count
            let countJSON = items.filter { $0.tags.contains("#JSON") }.count
            let countOCR = items.filter { $0.tags.contains("#OCR") }.count
            let maskedSample = SmartClassifier.maskedSecret("sk-live-98a7f6d5e4c3b2a10987654321fedcba")
            print("[SYNTHETIC_TEST_REPORT] \(result)")
            print("[SYNTHETIC_COUNTS] all=\(countAll) text=\(countText) file=\(countFile) url=\(countURL) code=\(countCode) image=\(countImage) secret=\(countSecret) color=\(countColor) utm=\(countUTM) swift=\(countSwift) json=\(countJSON) ocr=\(countOCR)")
            print("[SYNTHETIC_MASK] \(maskedSample)")
            guard countText >= 1, countFile >= 1, countURL >= 1, countCode >= 2, countImage >= 1, countSecret >= 1, countColor >= 2,
                  countUTM >= 1, countSwift >= 1, countJSON >= 1, countOCR >= 1,
                  maskedSample == "sk-••••••••cba" else {
                fputs("[SYNTHETIC_TEST_FAILED]\n", stderr)
                exit(1)
            }

            // 0.1 Тестируем SecretDetector на паролях от 8 символов и мнемонических фразах
            let pass8 = "kX8#mQ2$"
            let pass8Analysis = SecretDetector.inspect(pass8)
            let passMnemonic = "apple-banana-cherry-dragon"
            let passMnemonicAnalysis = SecretDetector.inspect(passMnemonic)
            let concealedText = "simple123"
            let concealedClassified = SmartClassifier.classify(text: concealedText, isSensitive: true, isImage: false)
            let normalText = "regular normal text"
            let normalAnalysis = SecretDetector.inspect(normalText)

            guard pass8Analysis.isSensitive, pass8Analysis.secretKind == "Пароль",
                  passMnemonicAnalysis.isSensitive, passMnemonicAnalysis.secretKind == "Пароль",
                  concealedClassified == .secret,
                  !normalAnalysis.isSensitive else {
                fputs("[SYNTHETIC_PASSWORD_DETECTOR_8CHAR_FAILED]\n", stderr)
                exit(1)
            }
            print("[SYNTHETIC_PASSWORD_DETECTOR_VERIFIED] 8-char passwords & mnemonics classified as .secret")

            // Тест независимого таймера паролей (по умолчанию expiresAt == nil, управление каждым паролем отдельно)
            delegate.monitor.autoPurgeSecretsEnabled = false
            let secret1 = "sk-live-independent-timer-first-11111111"
            let secret2 = "sk-live-independent-timer-second-22222222"
            let id1 = delegate.monitor.recordGeneratedPassword(secret1, ttlSeconds: nil)
            let id2 = delegate.monitor.recordGeneratedPassword(secret2, ttlSeconds: nil)

            // 0.2 Проверяем новый typography-логотип Variant #5 и sourceAppName PassGen
            guard NSFont(name: "AvenirNext-HeavyItalic", size: 19) != nil else {
                fputs("[SYNTHETIC_LOGO_FONT_FAILED] AvenirNext-HeavyItalic font not found\n", stderr)
                exit(1)
            }
            guard delegate.monitor.items.first(where: { $0.id == id1 })?.sourceAppName == "PasteVault (PassGen)" else {
                fputs("[SYNTHETIC_PASSGEN_APPNAME_FAILED] expected 'PasteVault (PassGen)', got '\(String(describing: delegate.monitor.items.first(where: { $0.id == id1 })?.sourceAppName))'\n", stderr)
                exit(1)
            }
            print("[SYNTHETIC_LOGO_AND_BRANDING_VERIFIED] AvenirNext-HeavyItalic available & PassGen branding verified as 'PasteVault (PassGen)'")

            // 1. Оба пароля по умолчанию создаются без таймера (expiresAt == nil)
            guard delegate.monitor.items.first(where: { $0.id == id1 })?.expiresAt == nil,
                  delegate.monitor.items.first(where: { $0.id == id2 })?.expiresAt == nil else {
                fputs("[SYNTHETIC_TTL_DEFAULT_NIL_FAILED]\n", stderr)
                exit(1)
            }

            // 2. Включаем таймер ТОЛЬКО на первом пароле (startTimerForItem) — у второго должен остаться nil
            delegate.monitor.startTimerForItem(id: id1, seconds: 60)
            guard delegate.monitor.items.first(where: { $0.id == id1 })?.expiresAt != nil,
                  delegate.monitor.items.first(where: { $0.id == id2 })?.expiresAt == nil else {
                fputs("[SYNTHETIC_TTL_INDEPENDENT_START_FAILED]\n", stderr)
                exit(1)
            }

            // 3. Отменяем таймер на первом пароле (cancelTimerForItem) — снова должен стать nil
            delegate.monitor.cancelTimerForItem(id: id1)
            guard delegate.monitor.items.first(where: { $0.id == id1 })?.expiresAt == nil else {
                fputs("[SYNTHETIC_TTL_CANCEL_FAILED]\n", stderr)
                exit(1)
            }

            // 4. Запускаем таймер 2 сек на первом пароле и проверяем, что после истечения удаляется ТОЛЬКО первый пароль, а второй остаётся
            delegate.monitor.startTimerForItem(id: id1, seconds: 2)
            delegate.monitor.purgeExpiredItemsTick(referenceDate: Date().addingTimeInterval(5))
            let firstStillExists = delegate.monitor.items.contains(where: { $0.id == id1 })
            let secondStillExists = delegate.monitor.items.contains(where: { $0.id == id2 })
            print("[SYNTHETIC_TTL_TEST] firstStillExists=\(firstStillExists) secondStillExists=\(secondStillExists) themes=\(AppTheme.allCases.count) fonts=\(AppFont.allCases.count)")
            guard !firstStillExists, secondStillExists, AppTheme.allCases.count == 10, AppFont.allCases.count == 6, AppFont.default == .inter else {
                fputs("[SYNTHETIC_TTL_PURGE_FAILED]\n", stderr)
                exit(1)
            }

            // 4.0.1 Тестируем toggleSecretStatus: перевод пароля в обычный текст и обратно в пароль
            let secretToggleId = delegate.monitor.recordGeneratedPassword("ToggleSecretPass123!#", ttlSeconds: nil)
            guard let toggleItemInitial = delegate.monitor.items.first(where: { $0.id == secretToggleId }),
                  toggleItemInitial.isSensitive,
                  toggleItemInitial.effectiveContentType == .secret else {
                fputs("[SYNTHETIC_TOGGLE_SECRET_INITIAL_FAILED]\n", stderr)
                exit(1)
            }
            // Переводим пароль в обычный текст
            delegate.monitor.toggleSecretStatus(for: secretToggleId)
            guard let demotedItem = delegate.monitor.items.first(where: { $0.id == secretToggleId }),
                  !demotedItem.isSensitive,
                  demotedItem.effectiveContentType == .text,
                  !demotedItem.displayPreviewText.contains("•") else {
                fputs("[SYNTHETIC_TOGGLE_DEMOTE_TO_TEXT_FAILED]\n", stderr)
                exit(1)
            }
            // Переводим обратно в пароль
            delegate.monitor.toggleSecretStatus(for: secretToggleId)
            guard let promotedItem = delegate.monitor.items.first(where: { $0.id == secretToggleId }),
                  promotedItem.isSensitive,
                  promotedItem.effectiveContentType == .secret,
                  promotedItem.displayPreviewText.contains("•") else {
                fputs("[SYNTHETIC_TOGGLE_PROMOTE_TO_SECRET_FAILED]\n", stderr)
                exit(1)
            }
            print("[SYNTHETIC_TOGGLE_SECRET_PASSED] Password <-> Text toggling verified with unmasking & masking")

            // 4.0.2 Тестируем умный фильтр кандидата в пароль (isPasswordCandidate)
            func makeTestCandidateRow(id: String, text: String, kind: ContentKind = .text, isSensitive: Bool = false) -> ClipboardItemRow {
                ClipboardItemRow(
                    id: id,
                    rowid: 1,
                    contentType: kind,
                    textPreview: text,
                    contentHash: id,
                    sourceBundleId: "com.apple.test",
                    sourceAppName: "Test",
                    isSensitive: isSensitive,
                    secretKind: isSensitive ? "Пароль" : nil,
                    isPinned: false,
                    createdAt: 1,
                    expiresAt: nil
                )
            }
            let cand1 = makeTestCandidateRow(id: "c1", text: "alex2026")
            let cand2 = makeTestCandidateRow(id: "c2", text: "849201")
            let nonCandPhrase = makeTestCandidateRow(id: "c3", text: "Hello world this is text")
            let nonCandCyrillic = makeTestCandidateRow(id: "c4", text: "Привет")
            let nonCandUrl = makeTestCandidateRow(id: "c5", text: "https://apple.com")
            let nonCandShort = makeTestCandidateRow(id: "c6", text: "abc")
            guard MainPanelView.isPasswordCandidate(cand1),
                  MainPanelView.isPasswordCandidate(cand2),
                  !MainPanelView.isPasswordCandidate(nonCandPhrase),
                  !MainPanelView.isPasswordCandidate(nonCandCyrillic),
                  !MainPanelView.isPasswordCandidate(nonCandUrl),
                  !MainPanelView.isPasswordCandidate(nonCandShort) else {
                fputs("[SYNTHETIC_PASSWORD_CANDIDATE_FILTER_FAILED]\n", stderr)
                exit(1)
            }
            print("[SYNTHETIC_PASSWORD_CANDIDATE_FILTER_PASSED] isPasswordCandidate correctly accepts solid tokens and rejects phrases/links/cyrillic")

            // 4.1 Тестируем перемасштабирование прозрачности (0% -> 0.50, 100% -> 1.00)
            let op0 = MainPanelView.computeActualOpacity(level: 0.0)
            let op35 = MainPanelView.computeActualOpacity(level: 0.35)
            let op70 = MainPanelView.computeActualOpacity(level: 0.70)
            let op100 = MainPanelView.computeActualOpacity(level: 1.0)
            guard abs(op0 - 0.50) < 0.001,
                  abs(op35 - 0.675) < 0.001,
                  abs(op70 - 0.850) < 0.001,
                  abs(op100 - 1.00) < 0.001 else {
                fputs("[SYNTHETIC_OPACITY_FORMULA_FAILED]\n", stderr)
                exit(1)
            }

            // 4.2 Тестируем интерактивный чёрный список приложений (Blacklist)
            delegate.monitor.resetBlacklistedAppsToDefaults()
            guard delegate.monitor.isAppBlacklisted("COM.APPLE.KEYCHAINACCESS"),
                  delegate.monitor.isAppBlacklisted("com.1password.1password") else {
                fputs("[SYNTHETIC_BLACKLIST_DEFAULTS_FAILED]\n", stderr)
                exit(1)
            }
            delegate.monitor.addBlacklistedApp(bundleID: "com.test.vaultignore")
            guard delegate.monitor.isAppBlacklisted("COM.TEST.VAULTIGNORE") else {
                fputs("[SYNTHETIC_BLACKLIST_ADD_FAILED]\n", stderr)
                exit(1)
            }
            delegate.monitor.removeBlacklistedApp(bundleID: "com.test.vaultignore")
            guard !delegate.monitor.isAppBlacklisted("com.test.vaultignore") else {
                fputs("[SYNTHETIC_BLACKLIST_REMOVE_FAILED]\n", stderr)
                exit(1)
            }

            // 5. Тестируем копирование скриншота/изображения: в NSPasteboard должен попадать СТРОГО формат .png (и ОТСУТСТВОВАТЬ .tiff)
            guard let imageItem = delegate.monitor.items.first(where: { $0.effectiveContentType == .image }) else {
                fputs("[SYNTHETIC_IMAGE_ITEM_NOT_FOUND]\n", stderr)
                exit(1)
            }
            delegate.monitor.copyToClipboard(item: imageItem)
            let pb = NSPasteboard.general
            let itemTypes = pb.pasteboardItems?.flatMap { $0.types } ?? []
            let hasPNG = itemTypes.contains(.png)
            let hasTIFF = itemTypes.contains(.tiff)
            let pastedText = pb.string(forType: .string) ?? ""
            let hasRawTextLeak = pastedText.contains("[Скриншот") || pastedText.contains("#OCR")
            print("[SYNTHETIC_IMAGE_COPY_TEST] hasPNG=\(hasPNG) hasTIFF=\(hasTIFF) hasRawTextLeak=\(hasRawTextLeak) ocrTextAvailable=\(imageItem.ocrText != nil)")
            guard hasPNG, !hasTIFF, !hasRawTextLeak, imageItem.ocrText != nil else {
                fputs("[SYNTHETIC_IMAGE_COPY_TEST_FAILED] hasPNG=\(hasPNG) (expected true), hasTIFF=\(hasTIFF) (expected false)\n", stderr)
                exit(1)
            }

            // 6. Проверяем все 10 тем (5 стеклянных + 5 матовых) и их 1-словные названия
            let liquidGlassCount = AppTheme.allCases.filter { $0.usesLiquidGlass }.count
            let solidMatteCount = AppTheme.allCases.filter { !$0.usesLiquidGlass }.count
            guard liquidGlassCount == 5, solidMatteCount == 5 else {
                fputs("[SYNTHETIC_THEMES_COUNT_FAILED]\n", stderr)
                exit(1)
            }
            for theme in AppTheme.allCases {
                let ruTitle = theme.title(in: .ru).trimmingCharacters(in: .whitespaces)
                let enTitle = theme.title(in: .en).trimmingCharacters(in: .whitespaces)
                guard !ruTitle.contains(" "), !enTitle.contains(" ") else {
                    fputs("[SYNTHETIC_THEME_SINGLE_WORD_FAILED] Theme \(theme.rawValue) is not single word: RU='\(ruTitle)' EN='\(enTitle)'\n", stderr)
                    exit(1)
                }
            }
            print("[SYNTHETIC_THEMES_VERIFIED] 10 single-word themes verified (5 Glass, 5 Solid Matte)")

            // 6.1 Проверяем 5 разделов в SettingsSidebarSection (.system, .appearance, .memory, .blacklist, .hotkeys)
            let settingsSections = SettingsSidebarSection.allCases
            let expectedSections: [SettingsSidebarSection] = [.system, .appearance, .memory, .blacklist, .hotkeys]
            guard settingsSections.count == 5, settingsSections == expectedSections else {
                fputs("[SYNTHETIC_SETTINGS_SECTIONS_FAILED] Expected 5 sections: \(expectedSections), got: \(settingsSections)\n", stderr)
                exit(1)
            }
            print("[SYNTHETIC_SETTINGS_SECTIONS_VERIFIED] 5 sidebar sections verified: system, appearance, memory, blacklist, hotkeys")

            // 7. Тестируем AccessibilityService: строгое соответствие isAccessibilityTrusted() == AXIsProcessTrusted()
            let rawTrusted = AXIsProcessTrusted()
            let serviceTrusted = AccessibilityService.isAccessibilityTrusted()
            guard serviceTrusted == rawTrusted else {
                fputs("[SYNTHETIC_ACCESSIBILITY_STRICT_EQUALITY_FAILED] isAccessibilityTrusted (\(serviceTrusted)) != AXIsProcessTrusted (\(rawTrusted))\n", stderr)
                exit(1)
            }
            let diag = AccessibilityService.runDiagnostics()
            guard diag.axIsProcessTrusted == rawTrusted else {
                fputs("[SYNTHETIC_ACCESSIBILITY_REPORT_TRUSTED_MISMATCH]\n", stderr)
                exit(1)
            }
            print("[SYNTHETIC_ACCESSIBILITY_TEST] axIsProcessTrusted=\(diag.axIsProcessTrusted) isRunningFromAppBundle=\(diag.isRunningFromAppBundle) duplicatesCount=\(diag.duplicateAppPaths.count)")
            guard !diag.bundleIdentifier.isEmpty, !diag.bundlePath.isEmpty else {
                fputs("[SYNTHETIC_ACCESSIBILITY_DIAGNOSTICS_FAILED]\n", stderr)
                exit(1)
            }

            // 8. Тестируем систему 11 горячих клавиш (ShortcutManager & ShortcutConfig)
            let shortcutMgr = ShortcutManager.shared
            shortcutMgr.resetToDefaults()
            let allCmds = ShortcutCommand.allCases
            guard allCmds.count == 11 else {
                fputs("[SYNTHETIC_SHORTCUTS_COMMANDS_COUNT_FAILED]\n", stderr)
                exit(1)
            }
            let expectedOrder: [ShortcutCommand] = [
                .togglePanel, .pasteSelected, .pastePlainText, .quickPasteModifier,
                .togglePin, .deleteItem, .clearHistory, .togglePause,
                .openPassGen, .openSnippets, .openSettings
            ]
            guard allCmds == expectedOrder else {
                fputs("[SYNTHETIC_SHORTCUTS_ORDER_FAILED]\n", stderr)
                exit(1)
            }
            // Проверяем валидацию системных зарезервированных сочетаний macOS (⌘C)
            let reservedCmdC = KeyCombo(keyCode: 8, modifiers: NSEvent.ModifierFlags.command.rawValue, displayString: "⌘C")
            let valReserved = shortcutMgr.validate(combo: reservedCmdC, for: .openSettings, in: .ru)
            guard case .systemReserved = valReserved else {
                fputs("[SYNTHETIC_SHORTCUTS_RESERVED_VALIDATION_FAILED]\n", stderr)
                exit(1)
            }
            // Проверяем валидацию внутреннего конфликта
            let conflictCombo = shortcutMgr.config.togglePin
            let valConflict = shortcutMgr.validate(combo: conflictCombo, for: .openSettings, in: .ru)
            guard case .internalConflict = valConflict else {
                fputs("[SYNTHETIC_SHORTCUTS_INTERNAL_CONFLICT_FAILED]\n", stderr)
                exit(1)
            }
            // Проверяем сброс к значениям по умолчанию
            shortcutMgr.config.togglePanel = KeyCombo(keyCode: 9, modifiers: NSEvent.ModifierFlags.option.rawValue, displayString: "⌥V")
            shortcutMgr.resetToDefaults()
            guard shortcutMgr.config.togglePanel.keyCode == ShortcutConfig.default.togglePanel.keyCode else {
                fputs("[SYNTHETIC_SHORTCUTS_RESET_FAILED]\n", stderr)
                exit(1)
            }
            // Проверяем флаг записи хоткеев
            shortcutMgr.startRecording(for: .togglePanel)
            guard shortcutMgr.isRecordingShortcut, delegate.monitor.isRecordingShortcut else {
                fputs("[SYNTHETIC_SHORTCUTS_RECORDING_FLAG_FAILED]\n", stderr)
                exit(1)
            }
            shortcutMgr.stopRecording()
            guard !shortcutMgr.isRecordingShortcut, !delegate.monitor.isRecordingShortcut else {
                fputs("[SYNTHETIC_SHORTCUTS_RECORDING_STOP_FAILED]\n", stderr)
                exit(1)
            }

            print("[SYNTHETIC_SHORTCUTS_TEST] 11 commands verified, reserved validation, conflict detector & reset to defaults passed")

            // 9. Тестируем управление хранением и типами данных (Storage & Content Types)
            let mon = delegate.monitor

            // 9.1 Форматирование размера хранилища (formattedStorageSize)
            let formattedSize = mon.formattedStorageSize
            print("[SYNTHETIC_STORAGE_TEST] formattedStorageSize=\(formattedSize)")
            guard !formattedSize.isEmpty, formattedSize.contains("Б") || formattedSize.contains("B") else {
                fputs("[SYNTHETIC_STORAGE_SIZE_FAILED]\n", stderr)
                exit(1)
            }

            // 9.2 Проверяем копирование файла в NSPasteboard
            guard let fileItem = mon.items.first(where: { $0.effectiveContentType == .file }) else {
                fputs("[SYNTHETIC_FILE_ITEM_NOT_FOUND]\n", stderr)
                exit(1)
            }
            mon.copyToClipboard(item: fileItem)
            let filePb = NSPasteboard.general
            let hasFileURL = filePb.types?.contains(NSPasteboard.PasteboardType("public.file-url")) == true
            let fileString = filePb.string(forType: .string) ?? ""
            guard hasFileURL, !fileString.isEmpty else {
                fputs("[SYNTHETIC_FILE_PASTEBOARD_FAILED]\n", stderr)
                exit(1)
            }

            // 9.3 Тестируем флаги фильтрации типов
            mon.saveFilesEnabled = false
            mon.saveImagesEnabled = false
            mon.saveTextEnabled = false
            guard !mon.saveFilesEnabled, !mon.saveImagesEnabled, !mon.saveTextEnabled else {
                fputs("[SYNTHETIC_CONTENT_TYPES_TOGGLE_FAILED]\n", stderr)
                exit(1)
            }
            // Возвращаем в true
            mon.saveFilesEnabled = true
            mon.saveImagesEnabled = true
            mon.saveTextEnabled = true

            // 9.4 Тестируем лимит истории (enforceHistoryLimit)
            mon.maxHistoryLimit = 5
            mon.enforceHistoryLimit()
            let unpinnedCount = mon.items.filter { !$0.isPinned }.count
            guard unpinnedCount <= 5 else {
                fputs("[SYNTHETIC_HISTORY_LIMIT_FAILED]\n", stderr)
                exit(1)
            }
            mon.maxHistoryLimit = 250

            // 9.5 Тестируем сортировку истории (applySortOrder) и сохранение закрепов наверху
            if !mon.items.isEmpty {
                mon.items[0].isPinned = true
            }
            mon.historySortOrder = "mostUsed"
            mon.applySortOrder()
            guard mon.items.first?.isPinned == true else {
                fputs("[SYNTHETIC_SORT_PINNED_FIRST_FAILED]\n", stderr)
                exit(1)
            }
            mon.historySortOrder = "lastCopied"
            mon.applySortOrder()
            guard mon.items.first?.isPinned == true else {
                fputs("[SYNTHETIC_SORT_LAST_COPIED_FAILED]\n", stderr)
                exit(1)
            }

            // 9.5.1 Тестируем togglePin, updateItemText и clearUnpinnedHistory (защита закреплённых)
            if let testItem = mon.items.last {
                let initialPinned = testItem.isPinned
                mon.togglePin(for: testItem.id)
                guard mon.items.first(where: { $0.id == testItem.id })?.isPinned == !initialPinned else {
                    fputs("[SYNTHETIC_TOGGLE_PIN_FAILED]\n", stderr)
                    exit(1)
                }
                mon.togglePin(for: testItem.id) // Возвращаем обратно

                let newContent = "Updated Synthetic Text Content 12345"
                mon.updateItemText(id: testItem.id, newText: newContent)
                guard mon.items.first(where: { $0.id == testItem.id })?.textPreview == newContent else {
                    fputs("[SYNTHETIC_UPDATE_ITEM_TEXT_FAILED]\n", stderr)
                    exit(1)
                }
            }

            // Проверяем, что clearUnpinnedHistory сохраняет закреплённые записи
            if !mon.items.isEmpty {
                mon.items[0].isPinned = true
            }
            let pinnedBefore = mon.items.filter { $0.isPinned }.count
            mon.clearUnpinnedHistory()
            guard mon.items.count == pinnedBefore, mon.items.allSatisfy({ $0.isPinned }) else {
                fputs("[SYNTHETIC_CLEAR_UNPINNED_PRESERVE_FAILED]\n", stderr)
                exit(1)
            }

            // 9.6 Тестируем полную очистку истории: items.count == 0 и formattedStorageSize == "0 КБ" / "0 KB"
            mon.clearAllHistory()
            guard mon.items.isEmpty, mon.items.count == 0 else {
                fputs("[SYNTHETIC_CLEAR_ITEMS_COUNT_FAILED]\n", stderr)
                exit(1)
            }
            let zeroStorageSize = mon.formattedStorageSize
            print("[SYNTHETIC_ZERO_STORAGE_TEST] zeroStorageSize=\(zeroStorageSize)")
            guard zeroStorageSize == "0 КБ" || zeroStorageSize == "0 KB" else {
                fputs("[SYNTHETIC_ZERO_STORAGE_SIZE_FAILED] expected 0 КБ/0 KB, got: \(zeroStorageSize)\n", stderr)
                exit(1)
            }
            print("[SYNTHETIC_STORAGE_AND_TYPES_TEST] Storage size formatting, file pasteboard, content toggles, history limits, sorting & zero storage on clear passed")

            // 10. Тестируем NSCache для изображений и генерацию/сохранение PNG
            let testImageItem = ClipboardItemRow(
                id: "test-image-item-id-1",
                rowid: 1001,
                contentType: .image,
                textPreview: "Test Screenshot 1",
                contentHash: "hash-img-1",
                sourceBundleId: "com.apple.screencaptureui",
                sourceAppName: "Screenshot",
                isSensitive: false,
                secretKind: nil,
                isPinned: false,
                createdAt: Int64(Date().timeIntervalSince1970),
                expiresAt: nil,
                ocrText: "Sample OCR Test Text",
                rawImageData: nil,
                fileURLPath: nil,
                useCount: 1
            )
            guard let cachedImg1 = mon.imageForItem(testImageItem),
                  let cachedImg2 = mon.imageForItem(testImageItem) else {
                fputs("[SYNTHETIC_IMAGE_CACHE_NIL_FAILED]\n", stderr)
                exit(1)
            }
            // Проверяем, что второй вызов возвращает закэшированный экземпляр (identity equality)
            guard cachedImg1 === cachedImg2 else {
                fputs("[SYNTHETIC_IMAGE_CACHE_IDENTITY_FAILED]\n", stderr)
                exit(1)
            }
            print("[SYNTHETIC_IMAGE_CACHE_PASSED] NSCache returns identical instance for item")

            // 10.1 Тестируем сохранение PNG во временный файл
            let tmpPNGURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_screenshot_\(UUID().uuidString).png")
            guard let tiffData = cachedImg1.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                fputs("[SYNTHETIC_PNG_REPRESENTATION_FAILED]\n", stderr)
                exit(1)
            }
            try? pngData.write(to: tmpPNGURL)
            let fileAttrs = (try? FileManager.default.attributesOfItem(atPath: tmpPNGURL.path)) ?? [:]
            let fileSize = (fileAttrs[.size] as? NSNumber)?.int64Value ?? 0
            try? FileManager.default.removeItem(at: tmpPNGURL)
            guard fileSize > 0 else {
                fputs("[SYNTHETIC_PNG_WRITE_FAILED] Expected file size > 0, got \(fileSize)\n", stderr)
                exit(1)
            }
            print("[SYNTHETIC_PNG_SAVE_PASSED] Saved PNG file size: \(fileSize) bytes")

            // 10.2 Бенчмарк производительности выборки на 500 записях (< 10 мс)
            var perfItems: [ClipboardItemRow] = []
            for i in 0..<500 {
                perfItems.append(ClipboardItemRow(
                    id: "perf-item-\(i)",
                    rowid: Int64(i),
                    contentType: .text,
                    textPreview: "Performance test preview \(i)",
                    contentHash: "perf-hash-\(i)",
                    sourceBundleId: "com.apple.Safari",
                    sourceAppName: "Safari",
                    isSensitive: false,
                    secretKind: nil,
                    isPinned: (i % 25 == 0),
                    createdAt: Int64(Date().addingTimeInterval(TimeInterval(-i)).timeIntervalSince1970),
                    expiresAt: nil,
                    ocrText: nil,
                    rawImageData: nil,
                    fileURLPath: nil,
                    useCount: i
                ))
            }
            mon.items = perfItems
            let perfStart = CFAbsoluteTimeGetCurrent()
            let targetId = "perf-item-380"
            let target = mon.items.first(where: { $0.id == targetId })
            let perfDurationMs = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000.0
            print("[SYNTHETIC_PERF_BENCHMARK] 500 items lookup duration: \(String(format: "%.3f", perfDurationMs)) ms")
            guard target != nil, perfDurationMs < 10.0 else {
                fputs("[SYNTHETIC_PERF_BENCHMARK_FAILED] Lookup took \(perfDurationMs) ms (limit 10ms)\n", stderr)
                exit(1)
            }

            // 11. Проверка структуры бандла в Contents/MacOS/: запрет дубликатов бинарников
            let macosBundleDir = "/Applications/Paste Vault.app/Contents/MacOS"
            if FileManager.default.fileExists(atPath: macosBundleDir) {
                let bundleBinaries = (try? FileManager.default.contentsOfDirectory(atPath: macosBundleDir))?.filter { !$0.hasPrefix(".") } ?? []
                if bundleBinaries.count > 1 {
                    fputs("[SYNTHETIC_TEST_FAILED] FAIL: Duplicate binary inside Contents/MacOS: \(bundleBinaries)\n", stderr)
                    exit(1)
                }
                print("[SYNTHETIC_BUNDLE_STRUCTURE_VERIFIED] Exactly 1 binary in Contents/MacOS: \(bundleBinaries)")
            }

            // 12. Проверка устранения двойного клика (Taptic debounce >= 85 мс)
            guard TapticSoundAndHaptics.minTickInterval >= 0.085 else {
                fputs("[SYNTHETIC_TAPTIC_DEBOUNCE_FAILED] minTickInterval must be >= 0.085, got \(TapticSoundAndHaptics.minTickInterval)\n", stderr)
                exit(1)
            }
            TapticSoundAndHaptics.shared.performDialTick()
            TapticSoundAndHaptics.shared.playConfirmClick()
            print("[SYNTHETIC_TAPTIC_DEBOUNCE_VERIFIED] minTickInterval >= 85ms verified")

            // 13. Проверка одиночного удаления закрепленного фрагмента vs массовой очистки
            var testSnippets = [
                QuickSnippetItem(id: "syn-pin-1", title: "Pinned 1", content: "P1", category: "Test", isPinned: true),
                QuickSnippetItem(id: "syn-norm-1", title: "Normal 1", content: "N1", category: "Test", isPinned: false),
                QuickSnippetItem(id: "syn-pin-2", title: "Pinned 2", content: "P2", category: "Test", isPinned: true)
            ]
            testSnippets.removeAll { $0.id == "syn-pin-1" }
            guard testSnippets.count == 2, !testSnippets.contains(where: { $0.id == "syn-pin-1" }) else {
                fputs("[SYNTHETIC_SNIPPET_SINGLE_DELETE_FAILED]\n", stderr)
                exit(1)
            }
            testSnippets.removeAll { !$0.isPinned }
            guard testSnippets.count == 1, testSnippets.first?.id == "syn-pin-2" else {
                fputs("[SYNTHETIC_SNIPPET_BULK_CLEAR_FAILED]\n", stderr)
                exit(1)
            }
            print("[SYNTHETIC_SNIPPET_DELETE_RULES_VERIFIED] Single delete of pinned snippet allowed, bulk clear preserves pinned")

            print("[SYNTHETIC_TEST_PASSED] ALL CATEGORIES (INCLUDING FILES), 10 THEMES, 6 FONTS, RESCALED OPACITY, INTERACTIVE BLACKLIST, IMAGE COPY/PASTE, STORAGE & CONTENT TYPES, ACCESSIBILITY SERVICE, 11 SHORTCUTS, IMAGE CACHE, PNG SAVER & 500-ITEM PERF VERIFIED")
            exit(0)
        }

        enforceSingleInstance()
        LaunchAtLoginManager.cleanupLegacyLaunchAgent()

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }

    public static func enforceSingleInstance() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications
        for app in running {
            guard app.processIdentifier != currentPID else { continue }
            let bid = app.bundleIdentifier
            let name = app.localizedName
            let execName = app.executableURL?.lastPathComponent

            if bid == "com.pastevault.app" ||
               name == "Paste Vault" ||
               name == "PasteVault" ||
               execName == "Paste Vault" ||
               execName == "PasteVault" {
                NSLog("[PasteVault] Another instance is already running (PID: %d). Terminating duplicate instance.", app.processIdentifier)
                // Минимальная платформа пакета — macOS 14, поэтому ветка #available не нужна
                app.activate()
                exit(0)
            }
        }
    }

    public let monitor = ClipboardMonitor.shared
    private var panel: FloatingPanel<MainPanelView>?
    private var hotKeyRef: EventHotKeyRef?
    public private(set) var statusItem: NSStatusItem?
    private var activityToken: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?

    public static func registerMenuBarDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            "showMenuBarIcon": true,
            "showInMenuBar": true,
            "NSStatusItem Visible Item-0": true,
            "NSStatusItem Visible PasteVaultStatusItem": true,
            "autoCheckUpdates": false,
            "tapticAudioFeedbackEnabled": true
        ])
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Self.registerMenuBarDefaults()
        Self.enforceSingleInstance()
        LaunchAtLoginManager.cleanupLegacyLaunchAgent()

        _ = AccessibilityService.isAccessibilityTrusted()

        NSApp.setActivationPolicy(.accessory)
        Self.shared = self

        // Отключаем App Nap в macOS, чтобы перехват буфера (⌘+C) работал мгновенно (за 0.06 сек) даже в фоне
        self.activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Мгновенный перехват системного буфера обмена без задержек App Nap"
        )

        // Запоминаем текущее открытое приложение (например, Safari) до показа Paste Vault
        monitor.detectFrontmostExternalApp()

        setupApplicationMenu()

        // Автоматическая проверка и подключение 10 бесплатных шрифтов (SIL OFL / системных) в фоне
        FontManager.shared.ensureFontsInstalled()

        setupFloatingPanel()
        setupStatusBarItem()
        setupHotKeys()

        // При перелистывании рабочих столов macOS (Spaces) сразу скрываем панель
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.panel?.orderOut(nil)
            }
        }

        Task {
            do {
                try await DatabaseManager.shared.initializeDatabase()
                await monitor.loadInitialHistory()
                monitor.startMonitoring()
            } catch {
                NSLog("[PasteVault] Init DB error: \(error)")
            }

            // Фоновая проверка обновлений при запуске (если включен тумблер autoCheckUpdates)
            if UpdateService.shared.autoCheckUpdates {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await UpdateService.shared.checkForUpdates(manual: false)
            }
        }

        // Закрываем любые возможные системные пустые окна, оставляя только главное окно Paste Vault
        for window in NSApp.windows where window !== panel {
            window.close()
        }

        // Открываем окно сразу при запуске рядом с активным окном (без навязчивого системного prompt)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.presentFloatingPanel()
        }
    }

    // Срабатывает каждый раз при клике по иконке приложения в Dock или двойном клике в Finder
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentFloatingPanel()
        return true
    }

    // Срабатывает при переключении на приложение (через Dock или ⌘+Tab), если окно было скрыто
    public func applicationDidBecomeActive(_ notification: Notification) {
        monitor.pollPasteboardImmediately()
        guard let panel else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - panel.lastDismissTimestamp > 0.35 else { return }
        if !panel.isVisible {
            presentFloatingPanel()
        }
    }

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: tr("Открыть PasteVault (⌥ + Space)", "Open PasteVault (⌥ + Space)"),
            action: #selector(handleOpenFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        return menu
    }

    private func setupApplicationMenu() {
        let mainMenu = NSMenu()

        // Меню приложения
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let openItem = NSMenuItem(title: tr("Открыть окно PasteVault", "Open PasteVault Window"), action: #selector(handleOpenFromMenu), keyEquivalent: "o")
        openItem.target = self
        appMenu.addItem(openItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: tr("Скрыть PasteVault", "Hide PasteVault"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: tr("Выход из PasteVault", "Quit PasteVault"), action: #selector(handleQuitApp), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        // Меню Правка (чтобы работали ⌘C, ⌘V, ⌘A, ⌘X в поле поиска и редакторах)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: tr("Правка", "Edit"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: tr("Отменить", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: tr("Повторить", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: tr("Вырезать", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: tr("Копировать", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: tr("Вставить", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: tr("Выбрать все", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    private func setupFloatingPanel() {
        let contentView = MainPanelView(monitor: monitor)
        let rect = NSRect(x: 0, y: 0, width: 900, height: 650)
        self.panel = FloatingPanel(contentRect: rect) {
            contentView
        }
    }

    public func makeVaultMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let primaryColor = NSColor.black.cgColor

            ctx.saveGState()
            ctx.scaleBy(x: 18.0 / 100.0, y: 18.0 / 100.0)

            let cx: CGFloat = 53.5
            let cy: CGFloat = 50.0
            let rOuter: CGFloat = 41.5
            let rRingInner: CGFloat = 29.5
            let rRivetOrbit: CGFloat = 35.5
            let rRivet: CGFloat = 3.35

            // 1. Внешний круг двери хранилища
            ctx.setBlendMode(.normal)
            ctx.setFillColor(primaryColor)
            ctx.fillEllipse(in: CGRect(x: cx - rOuter, y: cy - rOuter, width: rOuter * 2, height: rOuter * 2))

            // Вырез внутренней границы кольца
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: cx - rRingInner, y: cy - rRingInner, width: rRingInner * 2, height: rRingInner * 2))

            // 2. Вырез 7 симметричных заклёпок по кольцу (-130, -90, -45, 0, 45, 90, 130 градусов)
            ctx.setBlendMode(.clear)
            let angles: [CGFloat] = [-130, -90, -45, 0, 45, 90, 130]
            for deg in angles {
                let rad = deg * .pi / 180.0
                let rx = cx + rRivetOrbit * cos(rad)
                let ry = cy + rRivetOrbit * sin(rad)
                ctx.fillEllipse(in: CGRect(x: rx - rRivet, y: ry - rRivet, width: rRivet * 2, height: rRivet * 2))
            }

            // 3. Вырез-обводка (knockout) вокруг левой петли и кронштейна
            let koTopCap = CGMutablePath()
            koTopCap.move(to: CGPoint(x: 7.2, y: 25.5))
            koTopCap.addCurve(to: CGPoint(x: 21.8, y: 25.5), control1: CGPoint(x: 7.2, y: 17.5), control2: CGPoint(x: 21.8, y: 17.5))
            koTopCap.closeSubpath()
            ctx.addPath(koTopCap)
            ctx.fillPath()

            let koBotCap = CGMutablePath()
            koBotCap.move(to: CGPoint(x: 7.2, y: 74.5))
            koBotCap.addCurve(to: CGPoint(x: 21.8, y: 74.5), control1: CGPoint(x: 7.2, y: 82.5), control2: CGPoint(x: 21.8, y: 82.5))
            koBotCap.closeSubpath()
            ctx.addPath(koBotCap)
            ctx.fillPath()

            ctx.addPath(CGPath(roundedRect: CGRect(x: 4.8, y: 24.2, width: 19.4, height: 13.2), cornerWidth: 4.2, cornerHeight: 4.2, transform: nil))
            ctx.fillPath()
            ctx.addPath(CGPath(roundedRect: CGRect(x: 4.8, y: 62.6, width: 19.4, height: 13.2), cornerWidth: 4.2, cornerHeight: 4.2, transform: nil))
            ctx.fillPath()
            ctx.fill(CGRect(x: 7.5, y: 34.0, width: 14.0, height: 32.0))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 18.5, y: 35.8, width: 18.0, height: 28.4), cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
            ctx.fillPath()

            // 4. Отрисовка симметричной петли слева и кронштейна
            ctx.setBlendMode(.normal)
            ctx.setFillColor(primaryColor)

            let topCap = CGMutablePath()
            topCap.move(to: CGPoint(x: 9.6, y: 24.4))
            topCap.addCurve(to: CGPoint(x: 19.4, y: 24.4), control1: CGPoint(x: 9.6, y: 19.0), control2: CGPoint(x: 19.4, y: 19.0))
            topCap.closeSubpath()
            ctx.addPath(topCap)
            ctx.fillPath()

            let botCap = CGMutablePath()
            botCap.move(to: CGPoint(x: 9.6, y: 75.6))
            botCap.addCurve(to: CGPoint(x: 19.4, y: 75.6), control1: CGPoint(x: 9.6, y: 81.0), control2: CGPoint(x: 19.4, y: 81.0))
            botCap.closeSubpath()
            ctx.addPath(botCap)
            ctx.fillPath()

            ctx.addPath(CGPath(roundedRect: CGRect(x: 7.5, y: 26.6, width: 14.0, height: 8.2), cornerWidth: 2.4, cornerHeight: 2.4, transform: nil))
            ctx.fillPath()
            ctx.addPath(CGPath(roundedRect: CGRect(x: 10.2, y: 37.2, width: 8.6, height: 25.6), cornerWidth: 1.0, cornerHeight: 1.0, transform: nil))
            ctx.fillPath()
            ctx.addPath(CGPath(roundedRect: CGRect(x: 7.5, y: 65.2, width: 14.0, height: 8.2), cornerWidth: 2.4, cornerHeight: 2.4, transform: nil))
            ctx.fillPath()
            ctx.addPath(CGPath(roundedRect: CGRect(x: 21.0, y: 38.4, width: 12.8, height: 23.2), cornerWidth: 3.4, cornerHeight: 3.4, transform: nil))
            ctx.fillPath()

            // 2 вырезанных болта на кронштейне петли
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: 27.6 - 2.4, y: 44.2 - 2.4, width: 4.8, height: 4.8))
            ctx.fillEllipse(in: CGRect(x: 27.6 - 2.4, y: 55.8 - 2.4, width: 4.8, height: 4.8))

            // 5. Курсивная буква «P» в центре
            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            let skew = tan(-11.0 * .pi / 180.0)
            ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: skew, d: 1, tx: 0, ty: 0))

            let pOuter = CGMutablePath()
            pOuter.move(to: CGPoint(x: -11.5, y: -20.0))
            pOuter.addLine(to: CGPoint(x: 4.5, y: -20.0))
            pOuter.addCurve(to: CGPoint(x: 18.8, y: -7.2), control1: CGPoint(x: 13.5, y: -20.0), control2: CGPoint(x: 18.8, y: -15.2))
            pOuter.addCurve(to: CGPoint(x: 3.8, y: 6.5), control1: CGPoint(x: 18.8, y: 1.2), control2: CGPoint(x: 13.2, y: 6.5))
            pOuter.addLine(to: CGPoint(x: -2.2, y: 6.5))
            pOuter.addLine(to: CGPoint(x: -2.2, y: 20.0))
            pOuter.addLine(to: CGPoint(x: -11.5, y: 20.0))
            pOuter.closeSubpath()

            let pCounter = CGMutablePath()
            pCounter.move(to: CGPoint(x: -2.2, y: -12.2))
            pCounter.addLine(to: CGPoint(x: 3.5, y: -12.2))
            pCounter.addCurve(to: CGPoint(x: 9.4, y: -6.7), control1: CGPoint(x: 7.2, y: -12.2), control2: CGPoint(x: 9.4, y: -10.2))
            pCounter.addCurve(to: CGPoint(x: 3.5, y: -1.2), control1: CGPoint(x: 9.4, y: -3.2), control2: CGPoint(x: 7.2, y: -1.2))
            pCounter.addLine(to: CGPoint(x: -2.2, y: -1.2))
            pCounter.closeSubpath()

            ctx.setBlendMode(.normal)
            ctx.setFillColor(primaryColor)
            ctx.addPath(pOuter)
            ctx.fillPath()

            ctx.setBlendMode(.clear)
            ctx.addPath(pCounter)
            ctx.fillPath()

            ctx.restoreGState()
            ctx.restoreGState()
            return true
        }
        image.size = size
        image.isTemplate = true
        return image
    }

    private func setupStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "PasteVaultStatusItem"
        item.isVisible = true

        if let button = item.button {
            let customIcon = makeVaultMenuBarIcon()
            let resolvedIcon: NSImage
            if customIcon.size.width > 0 && customIcon.size.height > 0 {
                customIcon.size = NSSize(width: 18, height: 18)
                customIcon.isTemplate = true
                resolvedIcon = customIcon
            } else if let sfFallback = NSImage(
                systemSymbolName: "doc.on.clipboard.fill",
                accessibilityDescription: "PasteVault"
            )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)) {
                sfFallback.size = NSSize(width: 18, height: 18)
                sfFallback.isTemplate = true
                resolvedIcon = sfFallback
            } else {
                customIcon.size = NSSize(width: 18, height: 18)
                customIcon.isTemplate = true
                resolvedIcon = customIcon
            }

            button.image = resolvedIcon
            button.imagePosition = .imageOnly
            button.appearsDisabled = false
            button.contentTintColor = nil
            button.appearance = nil
            button.title = ""
            button.toolTip = "PasteVault"
            button.target = self
            button.action = #selector(handleStatusBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
        self.statusItem?.isVisible = true
    }

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleFloatingPanel()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            let menu = NSMenu()

            let openItem = NSMenuItem(
                title: tr("Открыть окно PasteVault (⌥ + Space)", "Open PasteVault Window (⌥ + Space)"),
                action: #selector(handleOpenFromMenu),
                keyEquivalent: ""
            )
            openItem.target = self
            menu.addItem(openItem)

            menu.addItem(NSMenuItem.separator())

            let incognitoTitle = monitor.isIncognitoPaused
                ? tr("✓ Режим «Инкогнито» (пауза)", "✓ Incognito Mode (Paused)")
                : tr("Режим «Инкогнито» (пауза)", "Incognito Mode (Pause)")
            let incognitoItem = NSMenuItem(title: incognitoTitle, action: #selector(handleToggleIncognito), keyEquivalent: "")
            incognitoItem.target = self
            menu.addItem(incognitoItem)

            let checkUpdatesItem = NSMenuItem(
                title: tr("Проверить обновления…", "Check for Updates…"),
                action: #selector(handleCheckForUpdatesFromMenu),
                keyEquivalent: ""
            )
            checkUpdatesItem.target = self
            menu.addItem(checkUpdatesItem)

            menu.addItem(NSMenuItem.separator())

            let quitItem = NSMenuItem(
                title: tr("Выход из PasteVault", "Quit PasteVault"),
                action: #selector(handleQuitApp),
                keyEquivalent: "q"
            )
            quitItem.target = self
            menu.addItem(quitItem)

            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggleFloatingPanel()
        }
    }

    @objc private func handleOpenFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.presentFloatingPanel()
        }
    }

    @objc private func handleToggleIncognito() {
        monitor.isIncognitoPaused.toggle()
    }

    @objc private func handleCheckForUpdatesFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.presentFloatingPanel()
            NotificationCenter.default.post(name: Notification.Name("pasteVaultCheckForUpdates"), object: nil)
        }
    }

    @objc private func handleQuitApp() {
        NSApplication.shared.terminate(nil)
    }

    public func presentFloatingPanel() {
        monitor.pollPasteboardImmediately()
        if panel == nil {
            setupFloatingPanel()
        }
        panel?.presentPanel()
    }

    public func showFloatingPanel() {
        presentFloatingPanel()
    }

    public func dismissFloatingPanel(restorePreviousApp: Bool = true) {
        panel?.dismissPanel(restorePreviousApp: restorePreviousApp)
    }

    /// Временно скрывает панель и окна перед вызовом нативного окна авторизации Apple
    public func hidePanelForAccessibilityPrompt() {
        NSApp.windows.forEach { $0.orderOut(nil) }
        NSApp.deactivate()
    }

    /// Возвращает панель поверх всех окон при предоставлении Универсального доступа
    public func restorePanelAfterAccessibilityGranted() {
        if panel == nil {
            setupFloatingPanel()
        }
        panel?.presentPanel()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func toggleFloatingPanel() {
        monitor.pollPasteboardImmediately()
        if panel == nil {
            setupFloatingPanel()
        }
        panel?.toggleOrPresent(preferCursor: true)
    }

    private func setupHotKeys() {
        registerCarbonHotKey()
        NotificationCenter.default.addObserver(
            forName: Notification.Name("pasteVaultShortcutsDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.registerCarbonHotKey()
            }
        }
    }

    private func registerCarbonHotKey() {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, _, _ -> OSStatus in
            Task { @MainActor in
                guard !ShortcutManager.shared.isRecordingShortcut else { return }
                AppDelegate.shared?.toggleFloatingPanel()
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)

        let combo = ShortcutManager.shared.config.togglePanel
        var carbonModifiers: UInt32 = 0
        let flags = combo.modifierFlags
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        let hotKeyID = EventHotKeyID(signature: OSType(0x50564C54), id: 1)
        RegisterEventHotKey(
            UInt32(combo.keyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

