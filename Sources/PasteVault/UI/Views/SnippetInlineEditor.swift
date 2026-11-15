import SwiftUI
import AppKit

// MARK: - Content segments ([[img:file.png]] markers)

/// Последовательный блок содержимого фрагмента: кусок текста или картинка (в порядке, заданном пользователем).
public enum SnippetContentSegment: Equatable {
    case text(String)
    case image(String)
}

/// Утилиты для работы с компактными маркерами `[[img:имя_файла.png]]` внутри текста фрагмента.
public enum SnippetInlineContent {
    private static let markerRegex = try! NSRegularExpression(pattern: "\\[\\[img:([^\\[\\]\\n]+)\\]\\]")

    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48
        return cache
    }()

    public static func marker(forFileName name: String) -> String {
        "[[img:\(name)]]"
    }

    public static func fileName(fromPath path: String) -> String {
        (path as NSString).lastPathComponent
    }

    public static func imagesDirectory() -> URL? {
        try? DatabaseManager.pasteVaultSupportDirectory()
            .appendingPathComponent("Images")
    }

    /// Имя файла (snippet_img_<UUID>.png) или абсолютный путь (старые фрагменты) → URL файла
    public static func fileURL(forName name: String) -> URL? {
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }
        return imagesDirectory()?.appendingPathComponent(name)
    }

    public static func fullPath(forName name: String) -> String? {
        fileURL(forName: name)?.path
    }

    public static func image(forName name: String) -> NSImage? {
        let key = name as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let url = fileURL(forName: name), let img = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(img, forKey: key)
        return img
    }

    public static func containsMarker(_ content: String) -> Bool {
        guard content.contains("[[img:") else { return false }
        let range = NSRange(location: 0, length: (content as NSString).length)
        return markerRegex.firstMatch(in: content, options: [], range: range) != nil
    }

    /// Разбирает содержимое на блоки «текст → картинка → текст».
    /// Для старых фрагментов без маркеров, но с `imagePath`, картинка добавляется после текста.
    public static func segments(of content: String, legacyImagePath: String? = nil) -> [SnippetContentSegment] {
        var result: [SnippetContentSegment] = []
        if content.contains("[[img:") {
            let ns = content as NSString
            var cursor = 0
            for m in markerRegex.matches(in: content, options: [], range: NSRange(location: 0, length: ns.length)) {
                if m.range.location > cursor {
                    let t = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                    if !t.isEmpty { result.append(.text(t)) }
                }
                result.append(.image(ns.substring(with: m.range(at: 1))))
                cursor = m.range.location + m.range.length
            }
            if cursor < ns.length {
                result.append(.text(ns.substring(from: cursor)))
            }
        } else if !content.isEmpty {
            result.append(.text(content))
        }

        let hasInlineImage = result.contains { if case .image = $0 { return true } else { return false } }
        if !hasInlineImage, let legacy = legacyImagePath, !legacy.isEmpty {
            result.append(.image(legacy))
        }
        return result
    }

    /// Имена картинок, вставленных маркерами в текст
    public static func imageNames(in content: String) -> [String] {
        segments(of: content).compactMap { if case .image(let n) = $0 { return n } else { return nil } }
    }

    /// Текст без технических маркеров `[[img:...]]`
    public static func plainText(of content: String) -> String {
        guard content.contains("[[img:") else { return content }
        let range = NSRange(location: 0, length: (content as NSString).length)
        return markerRegex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
    }

    /// Масштабирует картинку с сохранением пропорций (по умолчанию max 260×140 pt)
    public static func scaled(_ image: NSImage, maxWidth: CGFloat = 260, maxHeight: CGFloat = 140) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let ratio = min(maxWidth / size.width, maxHeight / size.height, 1.0)
        let target = NSSize(width: max(1, size.width * ratio), height: max(1, size.height * ratio))
        let out = NSImage(size: target)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1.0)
        out.unlockFocus()
        return out
    }
}

// MARK: - NSTextAttachment с привязкой к файлу

public final class SnippetImageAttachment: NSTextAttachment {
    public var imageFileName: String = ""
}

// MARK: - Кодек: строка с маркерами ⇄ NSAttributedString с вложениями

public enum SnippetInlineTextCodec {
    public static func attachmentString(fileName: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attachment = SnippetImageAttachment()
        attachment.imageFileName = fileName
        if let img = SnippetInlineContent.image(forName: fileName) {
            attachment.image = SnippetInlineContent.scaled(img)
        } else {
            attachment.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        }
        let s = NSMutableAttributedString(attachment: attachment)
        s.addAttributes(attributes.filter { $0.key != .attachment }, range: NSRange(location: 0, length: s.length))
        return s
    }

    public static func attributedString(from raw: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for seg in SnippetInlineContent.segments(of: raw) {
            switch seg {
            case .text(let t):
                result.append(NSAttributedString(string: t, attributes: attributes))
            case .image(let name):
                result.append(attachmentString(fileName: name, attributes: attributes))
            }
        }
        return result
    }

    public static func rawString(from attributed: NSAttributedString) -> String {
        var out = ""
        let ns = attributed.string as NSString
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.attachment, in: full, options: []) { value, range, _ in
            if let att = value as? SnippetImageAttachment {
                out += SnippetInlineContent.marker(forFileName: att.imageFileName)
            } else if value != nil {
                // Чужие вложения игнорируем
            } else {
                out += ns.substring(with: range)
            }
        }
        return out
    }
}

// MARK: - Контроллер редактора (вставка картинки / макроса в позицию курсора)

@MainActor
public final class SnippetInlineEditorController {
    weak var textView: NSTextView?
    var baseAttributes: [NSAttributedString.Key: Any] = [:]

    public init() {}

    /// Вставляет картинку (NSTextAttachment) ровно в текущую позицию курсора
    public func insertImage(fileName: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let attr = SnippetInlineTextCodec.attachmentString(fileName: fileName, attributes: baseAttributes)
        let range = clamped(tv.selectedRange(), length: storage.length)
        if tv.shouldChangeText(in: range, replacementString: attr.string) {
            storage.replaceCharacters(in: range, with: attr)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: range.location + attr.length, length: 0))
            tv.typingAttributes = baseAttributes
        }
        tv.window?.makeFirstResponder(tv)
    }

    /// Вставляет текст (например, макрос) в текущую позицию курсора
    public func insertText(_ string: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let attr = NSAttributedString(string: string, attributes: baseAttributes)
        let range = clamped(tv.selectedRange(), length: storage.length)
        if tv.shouldChangeText(in: range, replacementString: string) {
            storage.replaceCharacters(in: range, with: attr)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: range.location + attr.length, length: 0))
            tv.typingAttributes = baseAttributes
        }
        tv.window?.makeFirstResponder(tv)
    }

    private func clamped(_ r: NSRange, length: Int) -> NSRange {
        let loc = min(max(0, r.location), length)
        let len = min(max(0, r.length), length - loc)
        return NSRange(location: loc, length: len)
    }
}

// MARK: - NSTextView (вставка из буфера — только простой текст или картинка)

final class SnippetNSTextView: NSTextView {
    var onPasteImage: ((NSImage) -> Void)?

    override func paste(_ sender: Any?) {
        handlePaste(from: .general) { [weak self] in
            self?.pasteAsPlainText(sender)
        }
    }

    func handlePaste(from pb: NSPasteboard, pastePlainTextAction: () -> Void) {
        if let s = pb.string(forType: .string), !s.isEmpty {
            pastePlainTextAction()
        } else if let img = NSImage(pasteboard: pb) {
            onPasteImage?(img)
        }
    }
}

// MARK: - SwiftUI-обёртка

public struct SnippetInlineTextView: NSViewRepresentable {
    @Binding public var text: String
    public let controller: SnippetInlineEditorController
    public let font: NSFont
    public let textColor: NSColor
    public let onPasteImage: ((NSImage) -> Void)?

    public init(
        text: Binding<String>,
        controller: SnippetInlineEditorController,
        font: NSFont,
        textColor: NSColor,
        onPasteImage: ((NSImage) -> Void)? = nil
    ) {
        self._text = text
        self.controller = controller
        self.font = font
        self.textColor = textColor
        self.onPasteImage = onPasteImage
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: textColor]
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = SnippetNSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        tv.isFieldEditor = false
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset = NSSize(width: 6, height: 8)

        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.font = font
        tv.textColor = textColor
        tv.insertionPointColor = textColor
        tv.typingAttributes = baseAttributes
        tv.delegate = context.coordinator
        tv.unregisterDraggedTypes()
        tv.registerForDraggedTypes([.string])

        let coordinator = context.coordinator
        tv.onPasteImage = { [weak coordinator] image in
            coordinator?.handlePastedImage(image)
        }

        tv.textStorage?.setAttributedString(SnippetInlineTextCodec.attributedString(from: text, attributes: baseAttributes))
        tv.setSelectedRange(NSRange(location: tv.textStorage?.length ?? 0, length: 0))

        scroll.documentView = tv
        controller.textView = tv
        controller.baseAttributes = baseAttributes
        context.coordinator.lastAppliedFont = font
        context.coordinator.lastAppliedTextColor = textColor
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? SnippetNSTextView else { return }
        context.coordinator.parent = self
        controller.textView = tv
        controller.baseAttributes = baseAttributes

        guard let storage = tv.textStorage else { return }
        let fontChanged = (context.coordinator.lastAppliedFont != font)
        let colorChanged = (context.coordinator.lastAppliedTextColor != textColor)

        let currentRaw = SnippetInlineTextCodec.rawString(from: storage)
        if currentRaw != text {
            context.coordinator.isProgrammaticUpdate = true
            storage.setAttributedString(SnippetInlineTextCodec.attributedString(from: text, attributes: baseAttributes))
            tv.setSelectedRange(NSRange(location: storage.length, length: 0))
            tv.font = font
            tv.textColor = textColor
            tv.insertionPointColor = textColor
            tv.typingAttributes = baseAttributes
            context.coordinator.lastAppliedFont = font
            context.coordinator.lastAppliedTextColor = textColor
            context.coordinator.isProgrammaticUpdate = false
        } else if fontChanged || colorChanged {
            let savedSelection = tv.selectedRange()
            context.coordinator.isProgrammaticUpdate = true
            if fontChanged {
                tv.font = font
            }
            if colorChanged {
                tv.textColor = textColor
                tv.insertionPointColor = textColor
            }
            if storage.length > 0 {
                let fullRange = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                if fontChanged {
                    storage.addAttribute(.font, value: font, range: fullRange)
                }
                if colorChanged {
                    storage.addAttribute(.foregroundColor, value: textColor, range: fullRange)
                }
                storage.endEditing()
            }
            let maxLen = storage.length
            let safeLoc = min(savedSelection.location, maxLen)
            let safeLen = min(savedSelection.length, maxLen - safeLoc)
            tv.setSelectedRange(NSRange(location: safeLoc, length: safeLen))
            tv.typingAttributes = baseAttributes
            context.coordinator.lastAppliedFont = font
            context.coordinator.lastAppliedTextColor = textColor
            context.coordinator.isProgrammaticUpdate = false
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SnippetInlineTextView
        var isProgrammaticUpdate = false
        var lastAppliedFont: NSFont?
        var lastAppliedTextColor: NSColor?

        init(_ parent: SnippetInlineTextView) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let tv = notification.object as? NSTextView, let storage = tv.textStorage else { return }
            let raw = SnippetInlineTextCodec.rawString(from: storage)
            if raw != parent.text {
                parent.text = raw
            }
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Текст, набранный сразу после картинки, не должен наследовать атрибут вложения
            tv.typingAttributes = parent.baseAttributes
        }

        func handlePastedImage(_ image: NSImage) {
            // Строго 1 фрагмент = 1 фото в слоте миниатюры: не создаём PNG и не вставляем [[img:...]] внутри текста
            parent.onPasteImage?(image)
        }
    }
}
