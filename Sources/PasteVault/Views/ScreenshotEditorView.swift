import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Screenshot Editor Tools & Submenus

public enum HandlePosition: String, Hashable, Sendable {
    case start
    case end
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case stepPointer
    case textCalloutPull
    case textCalloutTip
    case textWidthLeft
    case textWidthRight
}

public enum ScreenshotTool: String, CaseIterable, Identifiable, Sendable {
    case hand = "hand"
    case arrow = "arrow"
    case text = "text"
    case shape = "shape"
    case highlighter = "highlighter"
    case step = "step"
    case pixelate = "pixelate"

    /// Псевдоним для совместимости со спецификацией верхнего инструмента курсора выбора/перемещения
    public static let select: ScreenshotTool = .hand

    public var id: String { rawValue }

    public var hasSubmenu: Bool {
        switch self {
        case .arrow, .text, .shape, .highlighter:
            return true
        case .hand, .step, .pixelate:
            return false
        }
    }

    public var iconName: String {
        switch self {
        case .hand: return "hand.point.up.left.fill"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .shape: return "square.on.circle"
        case .highlighter: return "highlighter"
        case .step: return "mappin.and.ellipse"
        case .pixelate: return "squareshape.split.3x3"
        }
    }

    public func title(in lang: AppLanguage = .current) -> String {
        switch self {
        case .hand:
            return lang == .en ? "Select & Move" : "✋ Рука (Выбор и перемещение)"
        case .arrow:
            return lang == .en ? "Arrow & Stroke Width" : "Стрелка и толщина"
        case .text:
            return lang == .en ? "Text & Font" : "Текст и шрифт"
        case .shape:
            return lang == .en ? "Shapes" : "Фигуры"
        case .highlighter:
            return lang == .en ? "Highlighter" : "Полупрозрачный маркер"
        case .step:
            return lang == .en ? "Step Counter (1, 2, 3...)" : "Шаги-маячки (1, 2, 3...)"
        case .pixelate:
            return lang == .en ? "Fine Pixelate (6px)" : "Мелкая пикселизация"
        }
    }
}

public enum ScreenshotSubmenuKind: String, Equatable, Sendable {
    case arrow
    case text
    case shape
    case highlighter
    case color
}

public enum ScreenshotShapeKind: String, CaseIterable, Identifiable, Sendable {
    case roundedRect = "roundedRect"
    case rect = "rect"
    case ellipse = "ellipse"
    case line = "line"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .roundedRect: return "rectangle.roundedtop"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        }
    }

    public func title(in lang: AppLanguage = .current) -> String {
        switch self {
        case .roundedRect:
            return lang == .en ? "Rounded Rectangle" : "Скруглённый прямоугольник"
        case .rect:
            return lang == .en ? "Rectangle" : "Обычный прямоугольник"
        case .ellipse:
            return lang == .en ? "Circle / Oval" : "Круг / Овал"
        case .line:
            return lang == .en ? "Straight Line" : "Прямая линия"
        }
    }
}

public enum ScreenshotHighlighterMode: String, CaseIterable, Identifiable, Sendable {
    case freehand = "freehand"
    case box = "box"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .freehand: return "scribble"
        case .box: return "rectangle.dashed"
        }
    }

    public func title(in lang: AppLanguage = .current) -> String {
        switch self {
        case .freehand:
            return lang == .en ? "Freehand Highlighter" : "Маркер от руки"
        case .box:
            return lang == .en ? "Box Highlighter" : "Прозрачный прямоугольник"
        }
    }
}

public enum ScreenshotAnnotationColor: String, CaseIterable, Identifiable, Sendable {
    case crimson = "#F43F5E"
    case amber = "#F59E0B"
    case emerald = "#10B981"
    case sky = "#38BDF8"
    case purple = "#A855F7"
    case white = "#FFFFFF"
    case obsidian = "#0F172A"

    public var id: String { rawValue }

    public var nsColor: NSColor {
        SmartClassifier.parseNSColor(rawValue) ?? .systemRed
    }

    public var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }

    public func title(in lang: AppLanguage = .current) -> String {
        switch self {
        case .crimson: return lang == .en ? "Crimson" : "Алый"
        case .amber: return lang == .en ? "Amber" : "Янтарный"
        case .emerald: return lang == .en ? "Emerald" : "Изумрудный"
        case .sky: return lang == .en ? "Sky Blue" : "Голубой"
        case .purple: return lang == .en ? "Purple" : "Фиолетовый"
        case .white: return lang == .en ? "White" : "Белый"
        case .obsidian: return lang == .en ? "Obsidian" : "Чёрный"
        }
    }
}

// MARK: - Annotation Model

public enum ScreenshotAnnotationPayload: Equatable, Sendable {
    case arrow(start: CGPoint, end: CGPoint, color: ScreenshotAnnotationColor, lineWidth: CGFloat)
    case text(position: CGPoint, text: String, font: AppFont, fontSize: CGFloat, color: ScreenshotAnnotationColor, calloutTarget: CGPoint? = nil, maxWidth: CGFloat? = nil)
    case shape(kind: ScreenshotShapeKind, start: CGPoint, end: CGPoint, color: ScreenshotAnnotationColor, lineWidth: CGFloat)
    case highlighterFreehand(points: [CGPoint], color: ScreenshotAnnotationColor, lineWidth: CGFloat)
    case highlighterBox(rect: CGRect, color: ScreenshotAnnotationColor)
    case step(number: Int, position: CGPoint, color: ScreenshotAnnotationColor, pointerAngle: Double)
    case pixelate(rect: CGRect, pixelScale: CGFloat)
}

public struct ScreenshotAnnotationItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var payload: ScreenshotAnnotationPayload

    public init(id: UUID = UUID(), payload: ScreenshotAnnotationPayload) {
        self.id = id
        self.payload = payload
    }

    /// Номер метки-шага (если элемент является маячком-шагом 1, 2, 3...)
    public var stepNumber: Int? {
        if case .step(let num, _, _, _) = payload {
            return num
        }
        return nil
    }
}

// MARK: - Screenshot Editor Engine (ViewModel)

@MainActor
public final class ScreenshotEditorEngine: ObservableObject {
    public static let availableStrokeWidths: [CGFloat] = [2, 4, 6, 8, 12]
    public static let availableFontSizes: [CGFloat] = [12, 14, 16, 18, 24]
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    @Published public var annotations: [ScreenshotAnnotationItem] = []
    @Published public var selectedAnnotationId: UUID? = nil
    @Published public var selectedTool: ScreenshotTool = .hand
    @Published public var selectedShapeKind: ScreenshotShapeKind = .roundedRect
    @Published public var selectedHighlighterMode: ScreenshotHighlighterMode = .box
    @Published public var selectedColor: ScreenshotAnnotationColor = .crimson
    @Published public var selectedStrokeWidth: CGFloat = 4
    @Published public var selectedFontSize: CGFloat = 16
    /// По умолчанию шрифт для текста в редакторе скриншотов всегда Inter
    @Published public var selectedFont: AppFont = .inter
    @Published public var activeSubmenu: ScreenshotSubmenuKind? = nil
    @Published public var lastCanvasSize: CGSize = CGSize(width: 800, height: 600)
    @Published public var editingTextAnnotationId: UUID? = nil {
        didSet {
            ClipboardMonitor.shared.isEditingScreenshotText = (editingTextAnnotationId != nil)
        }
    }
    /// Идентификатор нажатой горячей клавиши для визуальной подсветки и увеличения в нижней строке подсказок
    @Published public var activeShortcutID: String? = nil
    /// Зажата ли сейчас клавиша ⇧ Shift (для непрерывной подсветки бейджа Shift в футере)
    @Published public var isShiftShortcutHeld: Bool = false

    private var undoStack: [[ScreenshotAnnotationItem]] = []
    private var shortcutHighlightResetTask: Task<Void, Never>? = nil

    public init() {}

    /// Активирует визуальную подсветку и пружинное увеличение значка горячей клавиши в нижней панели на `duration` секунд
    public func triggerShortcutHighlight(_ id: String, duration: TimeInterval = 0.28) {
        shortcutHighlightResetTask?.cancel()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            activeShortcutID = id
        }
        guard duration > 0 else { return }
        let nanoseconds = UInt64(max(0.05, duration) * 1_000_000_000)
        shortcutHighlightResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            if self.activeShortcutID == id {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    self.activeShortcutID = nil
                }
            }
        }
    }

    /// Обновляет состояние удержания клавиши `⇧ Shift` для подсветки в нижней строке
    public func setShiftShortcutHeld(_ isHeld: Bool) {
        guard isShiftShortcutHeld != isHeld else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            isShiftShortcutHeld = isHeld
        }
    }

    /// Проверяет, подсвечен ли сейчас указанный хоткей в нижней панели
    public func isShortcutHighlighted(_ id: String) -> Bool {
        if id == "shift" {
            return isShiftShortcutHeld || activeShortcutID == "shift"
        }
        return activeShortcutID == id
    }

    /// Записывает текущее состояние в стек отмены (Undo)
    public func recordUndoSnapshot(_ customState: [ScreenshotAnnotationItem]? = nil) {
        undoStack.append(customState ?? annotations)
        if undoStack.count > 60 {
            undoStack.removeFirst()
        }
    }

    /// Следующий номер маячка-шага (1, 2, 3...), динамически вычисляемый из текущих аннотаций на холсте
    public var nextStepNumber: Int {
        (annotations.compactMap { $0.stepNumber }.max() ?? 0) + 1
    }

    public func selectTool(_ tool: ScreenshotTool) {
        commitActiveTextEditing()
        if tool != .hand {
            selectedAnnotationId = nil
        }
        if selectedTool == tool {
            if let submenu = submenuKind(for: tool) {
                activeSubmenu = (activeSubmenu == submenu) ? nil : submenu
            } else {
                activeSubmenu = nil
            }
        } else {
            selectedTool = tool
            if let submenu = submenuKind(for: tool) {
                activeSubmenu = submenu
            } else {
                activeSubmenu = nil
            }
        }
    }

    public func toggleSubmenu(_ kind: ScreenshotSubmenuKind) {
        if activeSubmenu == kind {
            activeSubmenu = nil
        } else {
            activeSubmenu = kind
        }
    }

    private func submenuKind(for tool: ScreenshotTool) -> ScreenshotSubmenuKind? {
        switch tool {
        case .arrow: return .arrow
        case .text: return .text
        case .shape: return .shape
        case .highlighter: return .highlighter
        case .hand, .step, .pixelate: return nil
        }
    }

    @discardableResult
    public func addArrow(from start: CGPoint, to end: CGPoint, color: ScreenshotAnnotationColor? = nil, lineWidth: CGFloat? = nil) -> UUID {
        recordUndoSnapshot()
        let item = ScreenshotAnnotationItem(
            payload: .arrow(
                start: start,
                end: end,
                color: color ?? selectedColor,
                lineWidth: lineWidth ?? selectedStrokeWidth
            )
        )
        annotations.append(item)
        selectedAnnotationId = nil
        return item.id
    }

    @discardableResult
    public func addText(
        _ text: String,
        at position: CGPoint,
        font: AppFont? = nil,
        fontSize: CGFloat? = nil,
        color: ScreenshotAnnotationColor? = nil,
        calloutTarget: CGPoint? = nil,
        maxWidth: CGFloat? = nil,
        canvasSize: CGSize? = nil
    ) -> UUID {
        recordUndoSnapshot()
        let effectiveFont = font ?? selectedFont
        let effectiveSize = fontSize ?? selectedFontSize
        let effectiveColor = color ?? selectedColor
        let effectiveCanvas = canvasSize ?? lastCanvasSize
        let clampedPos = Self.clampTextPosition(
            position: position,
            text: text,
            font: effectiveFont,
            fontSize: effectiveSize,
            maxWidth: maxWidth,
            canvasSize: effectiveCanvas
        )
        let item = ScreenshotAnnotationItem(
            payload: .text(
                position: clampedPos,
                text: text,
                font: effectiveFont,
                fontSize: effectiveSize,
                color: effectiveColor,
                calloutTarget: calloutTarget,
                maxWidth: maxWidth
            )
        )
        annotations.append(item)
        selectedAnnotationId = nil
        return item.id
    }

    /// Открывает режим редактирования существующей текстовой надписи с синхронизацией её индивидуального шрифта, размера и цвета
    public func beginEditingTextAnnotation(id: UUID) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }),
              case .text(_, _, let font, let fontSize, let color, _, _) = annotations[idx].payload else {
            return
        }
        if let activeId = editingTextAnnotationId, activeId != id {
            commitActiveTextEditing()
        }
        selectedFont = font
        selectedFontSize = fontSize
        selectedColor = color
        selectedAnnotationId = nil
        editingTextAnnotationId = id
        ClipboardMonitor.shared.isEditingScreenshotText = true
    }

    public func updateText(id: UUID, newText: String, canvasSize: CGSize? = nil) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        if case .text(let pos, _, let font, let size, let color, let calloutTarget, let maxWidth) = annotations[idx].payload {
            let effectiveCanvas = canvasSize ?? lastCanvasSize
            let clampedPos = Self.clampTextPosition(
                position: pos,
                text: newText,
                font: font,
                fontSize: size,
                maxWidth: maxWidth,
                canvasSize: effectiveCanvas
            )
            annotations[idx].payload = .text(
                position: clampedPos,
                text: newText,
                font: font,
                fontSize: size,
                color: color,
                calloutTarget: calloutTarget,
                maxWidth: maxWidth
            )
        }
    }

    public func updateTextMaxWidth(id: UUID, maxWidth: CGFloat?, canvasSize: CGSize? = nil) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        if case .text(let pos, let text, let font, let size, let color, let calloutTarget, _) = annotations[idx].payload {
            let clampedMaxW = maxWidth.map { max(Self.minTextBoxWidth, $0) }
            let effectiveCanvas = canvasSize ?? lastCanvasSize
            let clampedPos = Self.clampTextPosition(
                position: pos,
                text: text,
                font: font,
                fontSize: size,
                maxWidth: clampedMaxW,
                canvasSize: effectiveCanvas
            )
            annotations[idx].payload = .text(
                position: clampedPos,
                text: text,
                font: font,
                fontSize: size,
                color: color,
                calloutTarget: calloutTarget,
                maxWidth: clampedMaxW
            )
        }
    }

    public func updateActiveTextStyle(font: AppFont? = nil, fontSize: CGFloat? = nil, color: ScreenshotAnnotationColor? = nil, canvasSize: CGSize? = nil) {
        if let font { selectedFont = font }
        if let fontSize { selectedFontSize = fontSize }
        if let color { selectedColor = color }
        guard let id = editingTextAnnotationId ?? selectedAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == id }),
              case .text(let pos, let text, let oldFont, let oldSize, let oldColor, let calloutTarget, let maxWidth) = annotations[idx].payload else {
            return
        }
        let effectiveFont = font ?? oldFont
        let effectiveSize = fontSize ?? oldSize
        let effectiveColor = color ?? oldColor
        let effectiveCanvas = canvasSize ?? lastCanvasSize
        let clampedPos = Self.clampTextPosition(
            position: pos,
            text: text,
            font: effectiveFont,
            fontSize: effectiveSize,
            maxWidth: maxWidth,
            canvasSize: effectiveCanvas
        )
        annotations[idx].payload = .text(
            position: clampedPos,
            text: text,
            font: effectiveFont,
            fontSize: effectiveSize,
            color: effectiveColor,
            calloutTarget: calloutTarget,
            maxWidth: maxWidth
        )
    }

    public func commitActiveTextEditing() {
        let hadActiveText = (editingTextAnnotationId != nil)
        if let id = editingTextAnnotationId,
            let idx = annotations.firstIndex(where: { $0.id == id }),
            case .text(_, let text, _, _, _, _, _) = annotations[idx].payload {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                annotations.remove(at: idx)
            }
        }
        editingTextAnnotationId = nil
        selectedAnnotationId = nil
        ClipboardMonitor.shared.isEditingScreenshotText = false
        if hadActiveText {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    public func moveAnnotation(id: UUID, to newPosition: CGPoint, canvasSize: CGSize? = nil) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        switch annotations[idx].payload {
        case .step(let number, _, let color, let pointerAngle):
            annotations[idx].payload = .step(number: number, position: newPosition, color: color, pointerAngle: pointerAngle)
        case .text(_, let text, let font, let fontSize, let color, let calloutTarget, let maxWidth):
            let effectiveCanvas = canvasSize ?? lastCanvasSize
            let clampedPos = Self.clampTextPosition(
                position: newPosition,
                text: text,
                font: font,
                fontSize: fontSize,
                maxWidth: maxWidth,
                canvasSize: effectiveCanvas
            )
            annotations[idx].payload = .text(
                position: clampedPos,
                text: text,
                font: font,
                fontSize: fontSize,
                color: color,
                calloutTarget: calloutTarget,
                maxWidth: maxWidth
            )
        default:
            break
        }
    }

    /// Свободное перемещение тела любого типа аннотаций на холсте на вектор delta (dx, dy)
    public func translateAnnotation(id: UUID, by delta: CGPoint) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        switch annotations[idx].payload {
        case .arrow(let start, let end, let color, let lineWidth):
            annotations[idx].payload = .arrow(
                start: CGPoint(x: start.x + delta.x, y: start.y + delta.y),
                end: CGPoint(x: end.x + delta.x, y: end.y + delta.y),
                color: color,
                lineWidth: lineWidth
            )
        case .shape(let kind, let start, let end, let color, let lineWidth):
            annotations[idx].payload = .shape(
                kind: kind,
                start: CGPoint(x: start.x + delta.x, y: start.y + delta.y),
                end: CGPoint(x: end.x + delta.x, y: end.y + delta.y),
                color: color,
                lineWidth: lineWidth
            )
        case .highlighterFreehand(let points, let color, let lineWidth):
            let shifted = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            annotations[idx].payload = .highlighterFreehand(points: shifted, color: color, lineWidth: lineWidth)
        case .highlighterBox(let rect, let color):
            annotations[idx].payload = .highlighterBox(rect: rect.offsetBy(dx: delta.x, dy: delta.y), color: color)
        case .pixelate(let rect, let scale):
            annotations[idx].payload = .pixelate(rect: rect.offsetBy(dx: delta.x, dy: delta.y), pixelScale: scale)
        case .step(let number, let position, let color, let pointerAngle):
            annotations[idx].payload = .step(
                number: number,
                position: CGPoint(x: position.x + delta.x, y: position.y + delta.y),
                color: color,
                pointerAngle: pointerAngle
            )
        case .text(let position, let text, let font, let fontSize, let color, let calloutTarget, let maxWidth):
            let rawPos = CGPoint(x: position.x + delta.x, y: position.y + delta.y)
            let clampedPos = Self.clampTextPosition(
                position: rawPos,
                text: text,
                font: font,
                fontSize: fontSize,
                maxWidth: maxWidth,
                canvasSize: lastCanvasSize
            )
            annotations[idx].payload = .text(
                position: clampedPos,
                text: text,
                font: font,
                fontSize: fontSize,
                color: color,
                calloutTarget: calloutTarget,
                maxWidth: maxWidth
            )
        }
    }

    /// Обновление целевой точки выносной стрелки текста (с опциональным сворачиванием при возврате внутрь рамки текста)
    public func updateTextCalloutTarget(id: UUID, to target: CGPoint?, retractIfInside: Bool = false) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }),
              case .text(let position, let text, let font, let fontSize, let color, _, let maxWidth) = annotations[idx].payload else {
            return
        }
        var resolvedTarget = target
        if retractIfInside, let pt = target {
            let rect = Self.textBoundingRect(position: position, text: text, font: font, fontSize: fontSize, maxWidth: maxWidth)
            if rect.insetBy(dx: -12, dy: -12).contains(pt) {
                resolvedTarget = nil
            }
        }
        annotations[idx].payload = .text(
            position: position,
            text: text,
            font: font,
            fontSize: fontSize,
            color: color,
            calloutTarget: resolvedTarget,
            maxWidth: maxWidth
        )
    }

    /// Завершение перетаскивания выносной стрелки текста: если остриё вернули внутрь (или ближе 12 pt к рамке текста), стрелка убирается
    public func finalizeTextCalloutDrag(id: UUID) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }),
              case .text(let position, let text, let font, let fontSize, let color, let calloutTarget, let maxWidth) = annotations[idx].payload,
              let pt = calloutTarget else {
            return
        }
        let rect = Self.textBoundingRect(position: position, text: text, font: font, fontSize: fontSize, maxWidth: maxWidth)
        if rect.insetBy(dx: -12, dy: -12).contains(pt) {
            annotations[idx].payload = .text(
                position: position,
                text: text,
                font: font,
                fontSize: fontSize,
                color: color,
                calloutTarget: nil,
                maxWidth: maxWidth
            )
        }
    }

    /// Изменение геометрии выбранного объекта через интерактивные точки редактирования (●)
    public func updateAnnotationHandle(
        id: UUID,
        handle: HandlePosition,
        to point: CGPoint,
        isShiftPressed: Bool,
        canvasSize: CGSize = CGSize(width: 800, height: 600)
    ) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        switch annotations[idx].payload {
        case .arrow(let start, let end, let color, let lineWidth):
            if handle == .start {
                let adjusted = Self.adjustedDragEndPoint(start: end, rawEnd: point, tool: .arrow, shapeKind: .line, isShiftPressed: isShiftPressed)
                annotations[idx].payload = .arrow(start: adjusted, end: end, color: color, lineWidth: lineWidth)
            } else if handle == .end {
                let adjusted = Self.adjustedDragEndPoint(start: start, rawEnd: point, tool: .arrow, shapeKind: .line, isShiftPressed: isShiftPressed)
                annotations[idx].payload = .arrow(start: start, end: adjusted, color: color, lineWidth: lineWidth)
            }

        case .shape(let kind, let start, let end, let color, let lineWidth):
            if kind == .line {
                if handle == .start {
                    let adjusted = Self.adjustedDragEndPoint(start: end, rawEnd: point, tool: .shape, shapeKind: .line, isShiftPressed: isShiftPressed)
                    annotations[idx].payload = .shape(kind: kind, start: adjusted, end: end, color: color, lineWidth: lineWidth)
                } else if handle == .end {
                    let adjusted = Self.adjustedDragEndPoint(start: start, rawEnd: point, tool: .shape, shapeKind: .line, isShiftPressed: isShiftPressed)
                    annotations[idx].payload = .shape(kind: kind, start: start, end: adjusted, color: color, lineWidth: lineWidth)
                }
            } else {
                let (newStart, newEnd) = Self.calculateResizedCorners(start: start, end: end, handle: handle, to: point, isShiftPressed: isShiftPressed)
                annotations[idx].payload = .shape(kind: kind, start: newStart, end: newEnd, color: color, lineWidth: lineWidth)
            }

        case .highlighterBox(let rect, let color):
            let start = CGPoint(x: rect.minX, y: rect.minY)
            let end = CGPoint(x: rect.maxX, y: rect.maxY)
            let (newStart, newEnd) = Self.calculateResizedCorners(start: start, end: end, handle: handle, to: point, isShiftPressed: isShiftPressed)
            let newRect = CGRect(
                x: min(newStart.x, newEnd.x),
                y: min(newStart.y, newEnd.y),
                width: max(4, abs(newEnd.x - newStart.x)),
                height: max(4, abs(newEnd.y - newStart.y))
            )
            annotations[idx].payload = .highlighterBox(rect: newRect, color: color)

        case .pixelate(let rect, let scale):
            let start = CGPoint(x: rect.minX, y: rect.minY)
            let end = CGPoint(x: rect.maxX, y: rect.maxY)
            let (newStart, newEnd) = Self.calculateResizedCorners(start: start, end: end, handle: handle, to: point, isShiftPressed: isShiftPressed)
            let newRect = CGRect(
                x: min(newStart.x, newEnd.x),
                y: min(newStart.y, newEnd.y),
                width: max(4, abs(newEnd.x - newStart.x)),
                height: max(4, abs(newEnd.y - newStart.y))
            )
            annotations[idx].payload = .pixelate(rect: newRect, pixelScale: scale)

        case .step(let number, let position, let color, _):
            if handle == .stepPointer {
                let center = position
                var angle = atan2(point.y - center.y, point.x - center.x)
                if isShiftPressed {
                    let step = Double.pi / 4.0
                    angle = round(angle / step) * step
                }
                annotations[idx].payload = .step(number: number, position: position, color: color, pointerAngle: angle)
            }

        case .text(let position, let text, let font, let fontSize, let color, let calloutTarget, let maxWidth):
            if handle == .textCalloutPull || handle == .textCalloutTip {
                var target = point
                if isShiftPressed {
                    target = Self.adjustedDragEndPoint(start: position, rawEnd: point, tool: .arrow, shapeKind: .line, isShiftPressed: true)
                }
                annotations[idx].payload = .text(
                    position: position,
                    text: text,
                    font: font,
                    fontSize: fontSize,
                    color: color,
                    calloutTarget: target,
                    maxWidth: maxWidth
                )
            } else if handle == .textWidthRight || handle == .textWidthLeft {
                let currentRect = Self.textBoundingRect(
                    position: position,
                    text: text,
                    font: font,
                    fontSize: fontSize,
                    maxWidth: maxWidth,
                    canvasSize: canvasSize
                )
                let minBoxWidth = Self.minTextBoxWidth
                let maxBoxWidth = max(minBoxWidth, canvasSize.width - 24.0)
                let newMaxWidth: CGFloat
                let newPosition: CGPoint
                if handle == .textWidthRight {
                    let fixedLeft = currentRect.minX
                    newMaxWidth = min(maxBoxWidth, max(minBoxWidth, point.x - fixedLeft))
                    let updatedRect = Self.textBoundingRect(
                        position: position,
                        text: text,
                        font: font,
                        fontSize: fontSize,
                        maxWidth: newMaxWidth,
                        canvasSize: canvasSize
                    )
                    newPosition = CGPoint(x: fixedLeft + updatedRect.width * 0.5, y: position.y)
                } else {
                    let fixedRight = currentRect.maxX
                    newMaxWidth = min(maxBoxWidth, max(minBoxWidth, fixedRight - point.x))
                    let updatedRect = Self.textBoundingRect(
                        position: position,
                        text: text,
                        font: font,
                        fontSize: fontSize,
                        maxWidth: newMaxWidth,
                        canvasSize: canvasSize
                    )
                    newPosition = CGPoint(x: fixedRight - updatedRect.width * 0.5, y: position.y)
                }
                let clampedPos = Self.clampTextPosition(
                    position: newPosition,
                    text: text,
                    font: font,
                    fontSize: fontSize,
                    maxWidth: newMaxWidth,
                    canvasSize: canvasSize
                )
                annotations[idx].payload = .text(
                    position: clampedPos,
                    text: text,
                    font: font,
                    fontSize: fontSize,
                    color: color,
                    calloutTarget: calloutTarget,
                    maxWidth: newMaxWidth
                )
            }

        case .highlighterFreehand:
            break
        }
    }

    /// Поворот направления острого носика нумерованного маячка шага
    public func updateStepPointerAngle(id: UUID, to angle: Double) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        if case .step(let number, let position, let color, _) = annotations[idx].payload {
            recordUndoSnapshot()
            annotations[idx].payload = .step(number: number, position: position, color: color, pointerAngle: angle)
        }
    }

    /// Удаление текущего выделенного элемента по Backspace / Delete
    public func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }
        recordUndoSnapshot()
        let wasStep: Bool
        if case .step = annotations[idx].payload {
            wasStep = true
        } else {
            wasStep = false
        }
        annotations.remove(at: idx)
        selectedAnnotationId = nil
        if wasStep {
            renumberStepPinsSequentially()
        }
    }

    /// Удаление конкретной аннотации по ID
    public func deleteAnnotation(id: UUID) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        recordUndoSnapshot()
        let wasStep: Bool
        if case .step = annotations[idx].payload {
            wasStep = true
        } else {
            wasStep = false
        }
        annotations.remove(at: idx)
        if selectedAnnotationId == id {
            selectedAnnotationId = nil
        }
        if wasStep {
            renumberStepPinsSequentially()
        }
    }

    private func renumberStepPinsSequentially() {
        var currentStep = 1
        for i in annotations.indices {
            if case .step(_, let pos, let color, let angle) = annotations[i].payload {
                annotations[i].payload = .step(number: currentStep, position: pos, color: color, pointerAngle: angle)
                currentStep += 1
            }
        }
    }

    /// Живая смена цвета выделенного элемента на лету при клике по палитре
    public func updateSelectedAnnotationColor(_ color: ScreenshotAnnotationColor) {
        selectedColor = color
        guard let id = selectedAnnotationId ?? editingTextAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        recordUndoSnapshot()
        switch annotations[idx].payload {
        case .arrow(let s, let e, _, let w):
            annotations[idx].payload = .arrow(start: s, end: e, color: color, lineWidth: w)
        case .shape(let k, let s, let e, _, let w):
            annotations[idx].payload = .shape(kind: k, start: s, end: e, color: color, lineWidth: w)
        case .step(let n, let p, _, let a):
            annotations[idx].payload = .step(number: n, position: p, color: color, pointerAngle: a)
        case .text(let p, let t, let f, let sz, _, let calloutTarget, let maxWidth):
            annotations[idx].payload = .text(position: p, text: t, font: f, fontSize: sz, color: color, calloutTarget: calloutTarget, maxWidth: maxWidth)
        case .highlighterBox(let r, _):
            annotations[idx].payload = .highlighterBox(rect: r, color: color)
        case .highlighterFreehand(let pts, _, let w):
            annotations[idx].payload = .highlighterFreehand(points: pts, color: color, lineWidth: w)
        case .pixelate:
            break
        }
    }

    /// Живая смена толщины линии выделенного элемента
    public func updateSelectedAnnotationStrokeWidth(_ width: CGFloat) {
        selectedStrokeWidth = width
        guard let id = selectedAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        recordUndoSnapshot()
        switch annotations[idx].payload {
        case .arrow(let s, let e, let c, _):
            annotations[idx].payload = .arrow(start: s, end: e, color: c, lineWidth: width)
        case .shape(let k, let s, let e, let c, _):
            annotations[idx].payload = .shape(kind: k, start: s, end: e, color: c, lineWidth: width)
        case .highlighterFreehand(let pts, let c, _):
            annotations[idx].payload = .highlighterFreehand(points: pts, color: c, lineWidth: max(14, width * 3.2))
        default:
            break
        }
    }

    /// Живая смена шрифта текста выделенного элемента
    public func updateSelectedAnnotationFont(_ font: AppFont) {
        selectedFont = font
        guard let id = selectedAnnotationId ?? editingTextAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        if case .text(let p, let t, _, let sz, let c, let calloutTarget, let maxWidth) = annotations[idx].payload {
            recordUndoSnapshot()
            annotations[idx].payload = .text(position: p, text: t, font: font, fontSize: sz, color: c, calloutTarget: calloutTarget, maxWidth: maxWidth)
        }
    }

    /// Живая смена размера шрифта текста выделенного элемента
    public func updateSelectedAnnotationFontSize(_ size: CGFloat) {
        selectedFontSize = size
        guard let id = selectedAnnotationId ?? editingTextAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        if case .text(let p, let t, let f, _, let c, let calloutTarget, let maxWidth) = annotations[idx].payload {
            recordUndoSnapshot()
            annotations[idx].payload = .text(position: p, text: t, font: f, fontSize: size, color: c, calloutTarget: calloutTarget, maxWidth: maxWidth)
        }
    }

    /// Живая смена типа фигуры выделенного элемента
    public func updateSelectedAnnotationShapeKind(_ kind: ScreenshotShapeKind) {
        selectedShapeKind = kind
        guard let id = selectedAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        if case .shape(_, let s, let e, let c, let w) = annotations[idx].payload {
            recordUndoSnapshot()
            annotations[idx].payload = .shape(kind: kind, start: s, end: e, color: c, lineWidth: w)
        }
    }

    @discardableResult
    public func addShape(
        kind: ScreenshotShapeKind? = nil,
        from start: CGPoint,
        to end: CGPoint,
        color: ScreenshotAnnotationColor? = nil,
        lineWidth: CGFloat? = nil
    ) -> UUID {
        recordUndoSnapshot()
        let item = ScreenshotAnnotationItem(
            payload: .shape(
                kind: kind ?? selectedShapeKind,
                start: start,
                end: end,
                color: color ?? selectedColor,
                lineWidth: lineWidth ?? selectedStrokeWidth
            )
        )
        annotations.append(item)
        selectedAnnotationId = nil
        return item.id
    }

    @discardableResult
    public func addFreehandHighlighter(
        points: [CGPoint],
        color: ScreenshotAnnotationColor? = nil,
        lineWidth: CGFloat? = nil
    ) -> UUID {
        recordUndoSnapshot()
        let width = max(14, (lineWidth ?? selectedStrokeWidth) * 3.2)
        let item = ScreenshotAnnotationItem(
            payload: .highlighterFreehand(
                points: points,
                color: color ?? selectedColor,
                lineWidth: width
            )
        )
        annotations.append(item)
        selectedAnnotationId = nil
        return item.id
    }

    @discardableResult
    public func addBoxHighlighter(
        rect: CGRect,
        color: ScreenshotAnnotationColor? = nil
    ) -> UUID {
        recordUndoSnapshot()
        let normalized = rect.standardized
        let item = ScreenshotAnnotationItem(
            payload: .highlighterBox(
                rect: normalized,
                color: color ?? selectedColor
            )
        )
        annotations.append(item)
        selectedAnnotationId = nil
        return item.id
    }

    @discardableResult
    public func addStepPin(
        at position: CGPoint,
        color: ScreenshotAnnotationColor? = nil,
        pointerAngle: Double = .pi / 4.0
    ) -> Int {
        recordUndoSnapshot()
        let number = nextStepNumber
        let item = ScreenshotAnnotationItem(
            payload: .step(
                number: number,
                position: position,
                color: color ?? selectedColor,
                pointerAngle: pointerAngle
            )
        )
        annotations.append(item)
        selectedAnnotationId = nil
        return number
    }

    @discardableResult
    public func addPixelate(rect: CGRect, pixelScale: CGFloat = 6.0) -> UUID {
        recordUndoSnapshot()
        let normalized = rect.standardized
        let item = ScreenshotAnnotationItem(
            payload: .pixelate(
                rect: normalized,
                pixelScale: max(2.0, pixelScale)
            )
        )
        annotations.append(item)
        selectedAnnotationId = nil
        return item.id
    }

    public func undo() {
        commitActiveTextEditing()
        guard let previous = undoStack.popLast() else {
            if !annotations.isEmpty {
                annotations.removeLast()
            }
            return
        }
        annotations = previous
        if let sel = selectedAnnotationId, !annotations.contains(where: { $0.id == sel }) {
            selectedAnnotationId = nil
        }
    }

    public func clearAll() {
        if !annotations.isEmpty {
            recordUndoSnapshot()
        }
        editingTextAnnotationId = nil
        selectedAnnotationId = nil
        activeSubmenu = nil
        annotations.removeAll()
    }

    // MARK: - Geometry & Hit-Testing Helpers

    public static let textHorizontalPadding: CGFloat = 12.0
    public static let textVerticalPadding: CGFloat = 8.0
    public static let minTextBoxWidth: CGFloat = 110.0

    /// Вычисляет точный габаритный прямоугольник текстовой плашки в координатах холста с учётом шрифта, размера и многострочного переноса по `maxWidth`
    public static func textBoundingRect(
        position: CGPoint,
        text: String,
        font: AppFont = .inter,
        fontSize: CGFloat,
        maxWidth: CGFloat? = nil,
        canvasSize: CGSize = CGSize(width: 800, height: 600)
    ) -> CGRect {
        let displayString = text.isEmpty ? " " : text
        let nsFont = font.nsFont(size: fontSize, weight: .bold)
        let horizontalPadding: CGFloat = textHorizontalPadding // 12 pt (суммарно 24 pt слева и справа)
        let verticalPadding: CGFloat = textVerticalPadding     // 8 pt (суммарно 16 pt сверху и снизу)
        let minBoxWidth: CGFloat = minTextBoxWidth             // 110 pt
        let defaultMaxBoxWidth: CGFloat = min(340.0, max(180.0, canvasSize.width * 0.65))
        let maxAllowedBoxWidth: CGFloat = max(minBoxWidth, canvasSize.width - 24.0)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .paragraphStyle: paragraphStyle
        ]

        let singleLineRect = (displayString as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let singleLineWidth = ceil(singleLineRect.width) + 10.0

        let targetBoxWidth: CGFloat
        if let customMaxWidth = maxWidth {
            targetBoxWidth = min(max(customMaxWidth, minBoxWidth), maxAllowedBoxWidth)
        } else {
            if !displayString.contains("\n") && (singleLineWidth + horizontalPadding * 2.0) <= defaultMaxBoxWidth {
                targetBoxWidth = max(minBoxWidth, singleLineWidth + horizontalPadding * 2.0)
            } else {
                targetBoxWidth = defaultMaxBoxWidth
            }
        }

        let innerTextWidth = max(60.0, targetBoxWidth - horizontalPadding * 2.0)

        let multiLineRect = (displayString as NSString).boundingRect(
            with: NSSize(width: innerTextWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let conservativeWrapRect = (displayString as NSString).boundingRect(
            with: NSSize(width: max(50.0, innerTextWidth - 6.0), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let isWrappedOrMultiline = displayString.contains("\n") || singleLineWidth > innerTextWidth
        let effectiveMultiLineHeight = isWrappedOrMultiline
            ? max(multiLineRect.height, conservativeWrapRect.height)
            : multiLineRect.height

        let fontLineHeight = ceil(nsFont.ascender - nsFont.descender + max(0.0, nsFont.leading))
        let boxHeight = max(
            fontLineHeight + verticalPadding * 2.0,
            ceil(effectiveMultiLineHeight) + verticalPadding * 2.0 + 6.0
        )

        return CGRect(
            x: position.x - targetBoxWidth * 0.5,
            y: position.y - boxHeight * 0.5,
            width: targetBoxWidth,
            height: boxHeight
        )
    }

    /// Автоматически корректирует координаты центра текстовой аннотации (`position`),
    /// чтобы вся плашка `textRect` целиком помещалась внутри границ холста скриншота (`canvasSize`) с отступом `margin = 8 pt`
    public static func clampTextPosition(
        position: CGPoint,
        text: String,
        font: AppFont = .inter,
        fontSize: CGFloat,
        maxWidth: CGFloat? = nil,
        canvasSize: CGSize = CGSize(width: 800, height: 600),
        margin: CGFloat = 8.0
    ) -> CGPoint {
        var pos = position
        let textRect = textBoundingRect(
            position: pos,
            text: text.isEmpty ? " " : text,
            font: font,
            fontSize: fontSize,
            maxWidth: maxWidth,
            canvasSize: canvasSize
        )
        if textRect.minX < margin {
            pos.x += (margin - textRect.minX)
        }
        if textRect.maxX > canvasSize.width - margin {
            pos.x -= (textRect.maxX - (canvasSize.width - margin))
        }
        if textRect.minY < margin {
            pos.y += (margin - textRect.minY)
        }
        if textRect.maxY > canvasSize.height - margin {
            pos.y -= (textRect.maxY - (canvasSize.height - margin))
        }
        return pos
    }

    // MARK: - Step Pin Geometry & Offset Helpers

    /// Смещение острия носика метки-шага относительно центра метки
    public static func stepPinTipOffset(for pointerAngle: Double = .pi / 4.0) -> CGPoint {
        // В PasteVaultPointerPinShape: halfSize = 13.0, beakLength = 6.0
        // tip = (maxX + beakLength * 0.9, maxY + beakLength * 0.9)
        // maxX - center.x = 13.0, maxY - center.y = 13.0
        // При beakLength = 6.0: 13.0 + 6.0 * 0.9 = 18.4 pt
        let baseOffset: CGFloat = 13.0 + 6.0 * 0.9 // 18.4 pt
        let tipRadius = baseOffset * sqrt(2.0)
        return CGPoint(
            x: tipRadius * cos(pointerAngle),
            y: tipRadius * sin(pointerAngle)
        )
    }

    /// Смещение острия носика метки-шага относительно центра метки по умолчанию (при pointerAngle = .pi / 4.0)
    public static let stepPinTipOffsetFromCenter: CGPoint = stepPinTipOffset(for: .pi / 4.0)

    /// Вычисляет позицию центра метки-шага так, чтобы её острый носик точно указывал в целевую точку tipPoint
    public static func stepPinCenter(forTipPoint tipPoint: CGPoint, pointerAngle: Double = .pi / 4.0) -> CGPoint {
        let offset = stepPinTipOffset(for: pointerAngle)
        return CGPoint(x: tipPoint.x - offset.x, y: tipPoint.y - offset.y)
    }

    /// Габаритный прямоугольник метки-шага (включая корпус 26x26 и остриё носика) вокруг annotation.position
    public static func stepPinBoundingRect(at position: CGPoint, pointerAngle: Double = .pi / 4.0) -> CGRect {
        let center = position
        let tipOffset = stepPinTipOffset(for: pointerAngle)
        let minX = min(center.x - 14.0, center.x + tipOffset.x)
        let maxX = max(center.x + 14.0, center.x + tipOffset.x)
        let minY = min(center.y - 14.0, center.y + tipOffset.y)
        let maxY = max(center.y + 14.0, center.y + tipOffset.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Вычисляет точку СНАРУЖИ за правым краем текстовой рамки (на расстоянии 8 pt от внешней границы), за которую можно вытянуть стрелку от текста
    public static func textCalloutPullHandlePosition(
        position: CGPoint,
        text: String,
        font: AppFont = .inter,
        fontSize: CGFloat,
        maxWidth: CGFloat? = nil,
        canvasSize: CGSize = CGSize(width: 800, height: 600)
    ) -> CGPoint {
        let rect = textBoundingRect(
            position: position,
            text: text,
            font: font,
            fontSize: fontSize,
            maxWidth: maxWidth,
            canvasSize: canvasSize
        )
        return CGPoint(x: rect.maxX + 18.0, y: rect.midY)
    }

    /// Вычисляет ближайшую опорную точку на границе скруглённого прямоугольника `textRect` к точке острия `target`
    /// (так что даже на широком текстовом блоке стрелка выходит ровно из ближайшего участка края/угла, а не тянется от центра)
    public static func calloutAnchorPoint(for textRect: CGRect, target: CGPoint, cornerRadius: CGFloat = 7.0) -> CGPoint {
        let r = min(cornerRadius, min(textRect.width, textRect.height) * 0.45)
        let coreMinX = textRect.minX + r
        let coreMaxX = max(coreMinX, textRect.maxX - r)
        let coreMinY = textRect.minY + r
        let coreMaxY = max(coreMinY, textRect.maxY - r)

        let clampedCore = CGPoint(
            x: min(max(target.x, coreMinX), coreMaxX),
            y: min(max(target.y, coreMinY), coreMaxY)
        )

        let dx = target.x - clampedCore.x
        let dy = target.y - clampedCore.y
        let dist = hypot(dx, dy)
        if dist < 0.0001 {
            return CGPoint(x: textRect.maxX, y: textRect.midY)
        }

        let ux = dx / dist
        let uy = dy / dist
        return CGPoint(
            x: clampedCore.x + ux * r,
            y: clampedCore.y + uy * r
        )
    }

    /// Строит единый замкнутый контур (`Path`) для скруглённого текстового окна (`pillRect`) и выносной стрелки к `calloutTarget` через булево объединение (`CGPath.union`) без преломления углов и без перекоса на широких текстовых блоках
    public static func unifiedTextCalloutPath(
        pillRect: CGRect,
        cornerRadius: CGFloat = 7.0,
        calloutTarget: CGPoint?
    ) -> Path {
        let r = min(cornerRadius, min(pillRect.width, pillRect.height) * 0.45)
        let boxCGPath = CGPath(roundedRect: pillRect, cornerWidth: r, cornerHeight: r, transform: nil)

        guard let target = calloutTarget,
              !pillRect.insetBy(dx: -4, dy: -4).contains(target) else {
            return Path(boxCGPath)
        }

        // Находим ближайшую опорную точку на границе скруглённого прямоугольника pillRect к точке острия target
        let anchorPt = calloutAnchorPoint(for: pillRect, target: target, cornerRadius: r)

        let rawDX = target.x - anchorPt.x
        let rawDY = target.y - anchorPt.y
        let rawDist = hypot(rawDX, rawDY)
        guard rawDist > 3.5 else {
            return Path(boxCGPath)
        }

        let rawUX = rawDX / rawDist
        let rawUY = rawDY / rawDist

        // Заводим внутренний центр основания клина внутрь pillRect на 7–9 pt с безопасным отступом от углов,
        // чтобы булево объединение CGPath.union идеально сливало плашку и стрелку без зазоров и без преломления углов
        let safeInset = min(max(r + 2.5, 9.5), min(pillRect.width, pillRect.height) * 0.45)
        let innerBaseCenter = CGPoint(
            x: min(max(anchorPt.x - rawUX * 8.0, pillRect.minX + safeInset), pillRect.maxX - safeInset),
            y: min(max(anchorPt.y - rawUY * 8.0, pillRect.minY + safeInset), pillRect.maxY - safeInset)
        )

        let dx = target.x - anchorPt.x
        let dy = target.y - anchorPt.y
        let dist = hypot(dx, dy)
        let ux = dx / dist
        let uy = dy / dist
        let nx = -uy
        let ny = ux

        let innerHalfWidth = min(7.5, min(pillRect.width, pillRect.height) * 0.32)
        let innerBaseLeft = CGPoint(
            x: innerBaseCenter.x + nx * innerHalfWidth,
            y: innerBaseCenter.y + ny * innerHalfWidth
        )
        let innerBaseRight = CGPoint(
            x: innerBaseCenter.x - nx * innerHalfWidth,
            y: innerBaseCenter.y - ny * innerHalfWidth
        )

        // Геометрия классического наконечника стрелки (усики + остриё в точке calloutTarget)
        let headLength = min(11.5, max(7.5, dist * 0.42))
        let headHalfWidth = min(6.2, max(4.4, headLength * 0.55))
        let barbBackset = min(1.8, headLength * 0.18)
        let neckDist = max(2.0, dist - headLength + barbBackset)
        let neckHalfWidth: CGFloat = 2.1

        let neckCenter = CGPoint(
            x: anchorPt.x + ux * neckDist,
            y: anchorPt.y + uy * neckDist
        )
        let barbBase = CGPoint(
            x: target.x - ux * headLength,
            y: target.y - uy * headLength
        )

        let neckLeft = CGPoint(
            x: neckCenter.x + nx * neckHalfWidth,
            y: neckCenter.y + ny * neckHalfWidth
        )
        let neckRight = CGPoint(
            x: neckCenter.x - nx * neckHalfWidth,
            y: neckCenter.y - ny * neckHalfWidth
        )
        let wingLeft = CGPoint(
            x: barbBase.x + nx * headHalfWidth,
            y: barbBase.y + ny * headHalfWidth
        )
        let wingRight = CGPoint(
            x: barbBase.x - nx * headHalfWidth,
            y: barbBase.y - ny * headHalfWidth
        )

        // Контрольные точки вогнутых кривых Безье от широкого основания (~15 pt) к тонкой шейке перед наконечником
        let ctrlDist = min(10.0, neckDist * 0.36)
        let ctrlHalfWidth: CGFloat = 3.8
        let ctrlLeft = CGPoint(
            x: anchorPt.x + ux * ctrlDist + nx * ctrlHalfWidth,
            y: anchorPt.y + uy * ctrlDist + ny * ctrlHalfWidth
        )
        let ctrlRight = CGPoint(
            x: anchorPt.x + ux * ctrlDist - nx * ctrlHalfWidth,
            y: anchorPt.y + uy * ctrlDist - ny * ctrlHalfWidth
        )

        let arrowCGPath = CGMutablePath()
        arrowCGPath.move(to: innerBaseLeft)
        arrowCGPath.addQuadCurve(to: neckLeft, control: ctrlLeft)
        arrowCGPath.addLine(to: wingLeft)
        arrowCGPath.addLine(to: target)
        arrowCGPath.addLine(to: wingRight)
        arrowCGPath.addLine(to: neckRight)
        arrowCGPath.addQuadCurve(to: innerBaseRight, control: ctrlRight)
        arrowCGPath.closeSubpath()

        let combinedCGPath = boxCGPath.union(arrowCGPath, using: .winding)
        return Path(combinedCGPath)
    }

    /// Расстояние от точки p до отрезка [a, b]
    public static func distanceToSegment(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSq = dx * dx + dy * dy
        if lengthSq < 0.0001 {
            return hypot(p.x - a.x, p.y - a.y)
        }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq
        t = max(0, min(1, t))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(p.x - projX, p.y - projY)
    }

    /// Проверка попадания клика в интерактивную точку-ручку (●) выбранного элемента
    public static func hitTestHandle(point: CGPoint, in item: ScreenshotAnnotationItem, handleRadius: CGFloat = 12.0) -> HandlePosition? {
        switch item.payload {
        case .arrow(let start, let end, _, _):
            if hypot(point.x - start.x, point.y - start.y) <= handleRadius { return .start }
            if hypot(point.x - end.x, point.y - end.y) <= handleRadius { return .end }
            return nil

        case .shape(let kind, let start, let end, _, _):
            if kind == .line {
                if hypot(point.x - start.x, point.y - start.y) <= handleRadius { return .start }
                if hypot(point.x - end.x, point.y - end.y) <= handleRadius { return .end }
                return nil
            }
            let minX = min(start.x, end.x)
            let maxX = max(start.x, end.x)
            let minY = min(start.y, end.y)
            let maxY = max(start.y, end.y)
            if hypot(point.x - minX, point.y - minY) <= handleRadius { return .topLeft }
            if hypot(point.x - maxX, point.y - minY) <= handleRadius { return .topRight }
            if hypot(point.x - minX, point.y - maxY) <= handleRadius { return .bottomLeft }
            if hypot(point.x - maxX, point.y - maxY) <= handleRadius { return .bottomRight }
            return nil

        case .highlighterBox(let rect, _), .pixelate(let rect, _):
            let minX = rect.minX
            let maxX = rect.maxX
            let minY = rect.minY
            let maxY = rect.maxY
            if hypot(point.x - minX, point.y - minY) <= handleRadius { return .topLeft }
            if hypot(point.x - maxX, point.y - minY) <= handleRadius { return .topRight }
            if hypot(point.x - minX, point.y - maxY) <= handleRadius { return .bottomLeft }
            if hypot(point.x - maxX, point.y - maxY) <= handleRadius { return .bottomRight }
            return nil

        case .step(_, let position, _, let pointerAngle):
            let center = position
            let handlePt = CGPoint(x: center.x + cos(pointerAngle) * 28.0, y: center.y + sin(pointerAngle) * 28.0)
            if hypot(point.x - handlePt.x, point.y - handlePt.y) <= handleRadius { return .stepPointer }
            return nil

        case .text(let position, let text, let font, let fontSize, _, let calloutTarget, let maxWidth):
            let rect = textBoundingRect(position: position, text: text, font: font, fontSize: fontSize, maxWidth: maxWidth)
            // 1. Сначала проверяем кружок острия стрелки или кружок вытягивания стрелки (↗) снаружи справа
            if let tip = calloutTarget {
                if hypot(point.x - tip.x, point.y - tip.y) <= max(handleRadius, 14.0) {
                    return .textCalloutTip
                }
            } else {
                let pullPt = textCalloutPullHandlePosition(position: position, text: text, font: font, fontSize: fontSize, maxWidth: maxWidth)
                if hypot(point.x - pullPt.x, point.y - pullPt.y) <= max(handleRadius, 13.0) {
                    return .textCalloutPull
                }
            }
            // 2. Проверяем боковые ползунки изменения ширины текстового окна (слева и справа)
            let leftHandlePt = CGPoint(x: rect.minX - 3.0, y: rect.midY)
            let rightHandlePt = CGPoint(x: rect.maxX + 3.0, y: rect.midY)
            let verticalHitSpan = max(14.0, min(rect.height * 0.45, 24.0))
            if abs(point.x - leftHandlePt.x) <= 7.5 && abs(point.y - leftHandlePt.y) <= verticalHitSpan {
                return .textWidthLeft
            }
            if abs(point.x - rightHandlePt.x) <= 7.5 && abs(point.y - rightHandlePt.y) <= verticalHitSpan {
                return .textWidthRight
            }
            return nil

        case .highlighterFreehand:
            return nil
        }
    }

    /// Проверка попадания клика в тело любого созданного объекта на холсте
    public static func hitTestBody(point: CGPoint, in annotations: [ScreenshotAnnotationItem]) -> UUID? {
        for item in annotations.reversed() {
            switch item.payload {
            case .arrow(let start, let end, _, let lineWidth):
                if distanceToSegment(p: point, a: start, b: end) <= max(14.0, lineWidth * 2.2) {
                    return item.id
                }

            case .shape(let kind, let start, let end, _, let lineWidth):
                if kind == .line {
                    if distanceToSegment(p: point, a: start, b: end) <= max(14.0, lineWidth * 2.0) {
                        return item.id
                    }
                } else if kind == .ellipse {
                    let rect = CGRect(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y),
                        width: max(8, abs(end.x - start.x)),
                        height: max(8, abs(end.y - start.y))
                    )
                    let rx = max(4.0, rect.width * 0.5) + 6.0
                    let ry = max(4.0, rect.height * 0.5) + 6.0
                    let dx = point.x - rect.midX
                    let dy = point.y - rect.midY
                    if (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1.0 {
                        return item.id
                    }
                } else {
                    let rect = CGRect(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y),
                        width: max(8, abs(end.x - start.x)),
                        height: max(8, abs(end.y - start.y))
                    )
                    if rect.insetBy(dx: -8, dy: -8).contains(point) {
                        return item.id
                    }
                }

            case .highlighterFreehand(let points, _, let lineWidth):
                guard points.count >= 2 else { continue }
                let threshold = max(14.0, lineWidth * 0.8)
                for i in 0..<(points.count - 1) {
                    if distanceToSegment(p: point, a: points[i], b: points[i + 1]) <= threshold {
                        return item.id
                    }
                }

            case .highlighterBox(let rect, _):
                if rect.insetBy(dx: -6, dy: -6).contains(point) {
                    return item.id
                }

            case .pixelate(let rect, _):
                if rect.insetBy(dx: -6, dy: -6).contains(point) {
                    return item.id
                }

            case .step(_, let position, _, let pointerAngle):
                let badgeRect = stepPinBoundingRect(at: position, pointerAngle: pointerAngle).insetBy(dx: -5, dy: -5)
                if badgeRect.contains(point) || hypot(point.x - position.x, point.y - position.y) <= 28.0 {
                    return item.id
                }

            case .text(let position, let text, let font, let fontSize, _, let calloutTarget, let maxWidth):
                let rect = textBoundingRect(position: position, text: text, font: font, fontSize: fontSize, maxWidth: maxWidth)
                if rect.insetBy(dx: -6, dy: -6).contains(point) {
                    return item.id
                }
                if let target = calloutTarget {
                    let anchor = calloutAnchorPoint(for: rect, target: target)
                    let strokeWidth = max(2.5, fontSize * 0.14)
                    if distanceToSegment(p: point, a: anchor, b: target) <= max(14.0, strokeWidth * 2.4) {
                        return item.id
                    }
                }
            }
        }
        return nil
    }

    /// Расчёт новых углов прямоугольника при изменении через угловые ручки
    public static func calculateResizedCorners(
        start: CGPoint,
        end: CGPoint,
        handle: HandlePosition,
        to rawPoint: CGPoint,
        isShiftPressed: Bool
    ) -> (CGPoint, CGPoint) {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)

        var fixedAnchor: CGPoint
        var targetPoint = rawPoint

        switch handle {
        case .topLeft:
            fixedAnchor = CGPoint(x: maxX, y: maxY)
        case .topRight:
            fixedAnchor = CGPoint(x: minX, y: maxY)
        case .bottomLeft:
            fixedAnchor = CGPoint(x: maxX, y: minY)
        case .bottomRight:
            fixedAnchor = CGPoint(x: minX, y: minY)
        default:
            return (start, end)
        }

        if isShiftPressed {
            let dx = targetPoint.x - fixedAnchor.x
            let dy = targetPoint.y - fixedAnchor.y
            let side = max(abs(dx), abs(dy))
            let signX: CGFloat = dx >= 0 ? 1.0 : -1.0
            let signY: CGFloat = dy >= 0 ? 1.0 : -1.0
            targetPoint = CGPoint(x: fixedAnchor.x + signX * side, y: fixedAnchor.y + signY * side)
        }

        let p1 = fixedAnchor
        let p2 = targetPoint
        return (
            CGPoint(x: min(p1.x, p2.x), y: min(p1.y, p2.y)),
            CGPoint(x: max(p1.x, p2.x), y: max(p1.y, p2.y))
        )
    }

    public func hitTest(point: CGPoint) -> UUID? {
        Self.hitTestBody(point: point, in: annotations)
    }

    /// Вычисляет конечную точку перетаскивания мыши с учётом зажатой клавиши `⇧ Shift`:
    /// - Для фигур (`.ellipse`, `.rect`, `.roundedRect`): ширина и высота становятся строго равными по большей стороне (идеальный круг / квадрат).
    /// - Для прямой линии (`.shape` с `.line`) и стрелки (`.arrow`): угол наклона примагничивается к ближайшим `0°`, `45°` или `90°`.
    public static func adjustedDragEndPoint(
        start: CGPoint,
        rawEnd: CGPoint,
        tool: ScreenshotTool,
        shapeKind: ScreenshotShapeKind = .roundedRect,
        isShiftPressed: Bool
    ) -> CGPoint {
        guard isShiftPressed else { return rawEnd }
        let dx = rawEnd.x - start.x
        let dy = rawEnd.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0.001 else { return rawEnd }

        switch tool {
        case .shape where shapeKind != .line:
            let side = max(abs(dx), abs(dy))
            let signX: CGFloat = dx >= 0 ? 1.0 : -1.0
            let signY: CGFloat = dy >= 0 ? 1.0 : -1.0
            return CGPoint(
                x: start.x + signX * side,
                y: start.y + signY * side
            )

        case .arrow,
             .shape where shapeKind == .line:
            let angle = atan2(dy, dx)
            let step = CGFloat.pi / 4.0 // шаг 45°
            let snappedIndex = Int(round(angle / step))
            let normalizedMod = ((snappedIndex % 8) + 8) % 8
            switch normalizedMod {
            case 0, 4:
                // Строго горизонтальная линия (0° или 180°)
                return CGPoint(x: rawEnd.x, y: start.y)
            case 2, 6:
                // Строго вертикальная линия (90° или -90°)
                return CGPoint(x: start.x, y: rawEnd.y)
            default:
                // Строго диагональная линия под 45° (|dx| == |dy|)
                let side = max(abs(dx), abs(dy))
                let signX: CGFloat = dx >= 0 ? 1.0 : -1.0
                let signY: CGFloat = dy >= 0 ? 1.0 : -1.0
                return CGPoint(
                    x: start.x + signX * side,
                    y: start.y + signY * side
                )
            }

        default:
            return rawEnd
        }
    }

    /// Вычисляет видимый прямоугольник в координатах базового холста (0...canvasSize.width, 0...canvasSize.height)
    /// при заданном коэффициенте приближения `zoomScale` и смещении `panOffset`
    public static func visibleCropRect(
        in canvasSize: CGSize,
        zoomScale: CGFloat,
        panOffset: CGSize = .zero
    ) -> CGRect {
        let clampedZoom = max(1.0, zoomScale)
        let visibleW = canvasSize.width / clampedZoom
        let visibleH = canvasSize.height / clampedZoom
        let maxOffsetX = max(0, (canvasSize.width - visibleW) * 0.5)
        let maxOffsetY = max(0, (canvasSize.height - visibleH) * 0.5)
        let shiftedX = min(max(-maxOffsetX, -panOffset.width / clampedZoom), maxOffsetX)
        let shiftedY = min(max(-maxOffsetY, -panOffset.height / clampedZoom), maxOffsetY)
        let originX = (canvasSize.width - visibleW) * 0.5 + shiftedX
        let originY = (canvasSize.height - visibleH) * 0.5 + shiftedY
        return CGRect(x: originX, y: originY, width: visibleW, height: visibleH)
    }

    /// Рендерит итоговое изображение со всеми областями мелкой пикселизации (6px) и векторными слоями.
    /// Если `zoomScale > 1.0`, вырезает ровно приближенный фрагмент, видимый в рамке окна редактора, и сохраняет его крупным планом.
    public func renderAnnotatedImage(
        baseImage: NSImage,
        canvasSize: CGSize,
        zoomScale: CGFloat = 1.0,
        panOffset: CGSize = .zero
    ) -> NSImage? {
        commitActiveTextEditing()
        let targetCanvasSize = (canvasSize.width > 10 && canvasSize.height > 10) ? canvasSize : baseImage.size
        guard targetCanvasSize.width > 0, targetCanvasSize.height > 0 else { return nil }

        // Определяем Retina-масштаб относительно размера холста (с учётом zoomScale для максимальной чёткости при кропе)
        var pixelWidth = Int(baseImage.size.width * 2)
        if let cgImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pixelWidth = max(cgImage.width, Int(baseImage.size.width))
        }
        let effectiveZoom = max(1.0, zoomScale)
        let renderScale = max(2.0, (CGFloat(pixelWidth) / max(1.0, targetCanvasSize.width)) * effectiveZoom)

        // 1. Применяем все слои пикселизации к базовому изображению
        let pixelatedBaseImage = Self.applyPixelateLayers(
            to: baseImage,
            annotations: annotations,
            canvasSize: targetCanvasSize
        )

        // 2. Рендерим полный кадр со всеми векторными аннотациями
        let exportView = ScreenshotExportCanvasView(
            image: pixelatedBaseImage,
            annotations: annotations,
            canvasSize: targetCanvasSize
        )
        .frame(width: targetCanvasSize.width, height: targetCanvasSize.height)

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = renderScale
        renderer.isOpaque = true

        guard let fullCGImage = renderer.cgImage else {
            return nil
        }

        // 3. Если масштаб увеличен (zoomScale > 1.0), вырезаем (crop) ровно видимый в viewport приближенный фрагмент
        if effectiveZoom > 1.001 {
            let visibleRect = Self.visibleCropRect(
                in: targetCanvasSize,
                zoomScale: effectiveZoom,
                panOffset: panOffset
            )
            let normX = visibleRect.minX / targetCanvasSize.width
            let normY = visibleRect.minY / targetCanvasSize.height
            let normW = visibleRect.width / targetCanvasSize.width
            let normH = visibleRect.height / targetCanvasSize.height

            let fullPixelW = CGFloat(fullCGImage.width)
            let fullPixelH = CGFloat(fullCGImage.height)
            let cropPixelRect = CGRect(
                x: round(normX * fullPixelW),
                y: round(normY * fullPixelH),
                width: max(1, round(normW * fullPixelW)),
                height: max(1, round(normH * fullPixelH))
            ).intersection(CGRect(x: 0, y: 0, width: fullPixelW, height: fullPixelH))

            if let croppedCG = fullCGImage.cropping(to: cropPixelRect) {
                // Новые размеры вырезанного фрагмента (пропорционально приближенной области)
                let croppedPointSize = CGSize(
                    width: max(1, round(baseImage.size.width / effectiveZoom)),
                    height: max(1, round(baseImage.size.height / effectiveZoom))
                )
                // Создаём NSImage с полноразмерным Retina-представлением (масштабированным в zoomScale),
                // чтобы фрагмент вставлялся и отображался крупным планом 1-в-1 как на экране редактора
                let rep = NSBitmapImageRep(cgImage: croppedCG)
                rep.size = croppedPointSize
                let outImage = NSImage(size: croppedPointSize)
                outImage.addRepresentation(rep)
                return outImage
            }
        }

        let rep = NSBitmapImageRep(cgImage: fullCGImage)
        rep.size = baseImage.size
        let renderedNSImage = NSImage(size: baseImage.size)
        renderedNSImage.addRepresentation(rep)
        return renderedNSImage
    }

    /// Применяет фильтр мелкой пикселизации (CIPixellate, scale = 6.0) ко всем выделенным прямоугольным участкам
    public static func applyPixelateLayers(
        to sourceImage: NSImage,
        annotations: [ScreenshotAnnotationItem],
        canvasSize: CGSize
    ) -> NSImage {
        let pixelateRects: [(CGRect, CGFloat)] = annotations.compactMap { item in
            if case .pixelate(let rect, let scale) = item.payload, rect.width > 2, rect.height > 2 {
                return (rect, scale)
            }
            return nil
        }
        guard !pixelateRects.isEmpty else { return sourceImage }
        guard let cgSource = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return sourceImage
        }

        let imgW = CGFloat(cgSource.width)
        let imgH = CGFloat(cgSource.height)
        guard imgW > 0, imgH > 0, canvasSize.width > 0, canvasSize.height > 0 else { return sourceImage }

        var currentCIImage = CIImage(cgImage: cgSource)
        let fullExtent = currentCIImage.extent

        let scaleX = imgW / canvasSize.width
        let scaleY = imgH / canvasSize.height

        for (rect, pixelScale) in pixelateRects {
            // Переводим из координат SwiftUI (верхний левый угол) в координаты CoreImage (нижний левый угол)
            let ciX = rect.minX * scaleX
            let ciY = imgH - (rect.maxY * scaleY)
            let ciW = rect.width * scaleX
            let ciH = rect.height * scaleY
            let targetRect = CGRect(x: ciX, y: ciY, width: ciW, height: ciH).intersection(fullExtent)
            guard !targetRect.isNull, targetRect.width > 1, targetRect.height > 1 else { continue }

            let filter = CIFilter.pixellate()
            filter.inputImage = currentCIImage.clampedToExtent()
            filter.center = CGPoint(x: targetRect.midX, y: targetRect.midY)
            filter.scale = Float(max(4.0, pixelScale * ((scaleX + scaleY) * 0.5)))

            if let pixelatedFull = filter.outputImage?.cropped(to: targetRect) {
                currentCIImage = pixelatedFull.composited(over: currentCIImage)
            }
        }

        if let outCG = sharedCIContext.createCGImage(currentCIImage, from: fullExtent) {
            return NSImage(cgImage: outCG, size: sourceImage.size)
        }
        return sourceImage
    }
}

// MARK: - Signature PasteVault Vector Shapes

/// Авторская стрелка PasteVault: плавный клиновидный стержень, расширяющийся к геометричному наконечнику
public struct PasteVaultArrowShape: Shape {
    public var start: CGPoint
    public var end: CGPoint
    public var strokeWidth: CGFloat

    public init(start: CGPoint, end: CGPoint, strokeWidth: CGFloat) {
        self.start = start
        self.end = end
        self.strokeWidth = strokeWidth
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 4 else { return path }

        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux

        let headLength = min(length * 0.55, max(14.0, strokeWidth * 3.8))
        let headWidth = max(12.0, strokeWidth * 3.4)
        let tailHalfWidth = max(1.2, strokeWidth * 0.24)
        let neckHalfWidth = max(2.2, strokeWidth * 0.68)
        let notchDepth = headLength * 0.22

        let neckCenter = CGPoint(
            x: end.x - ux * (headLength - notchDepth),
            y: end.y - uy * (headLength - notchDepth)
        )
        let barbBase = CGPoint(
            x: end.x - ux * headLength,
            y: end.y - uy * headLength
        )

        let tailLeft = CGPoint(x: start.x + px * tailHalfWidth, y: start.y + py * tailHalfWidth)
        let tailRight = CGPoint(x: start.x - px * tailHalfWidth, y: start.y - py * tailHalfWidth)
        let neckLeft = CGPoint(x: neckCenter.x + px * neckHalfWidth, y: neckCenter.y + py * neckHalfWidth)
        let neckRight = CGPoint(x: neckCenter.x - px * neckHalfWidth, y: neckCenter.y - py * neckHalfWidth)
        let wingLeft = CGPoint(x: barbBase.x + px * (headWidth * 0.5), y: barbBase.y + py * (headWidth * 0.5))
        let wingRight = CGPoint(x: barbBase.x - px * (headWidth * 0.5), y: barbBase.y - py * (headWidth * 0.5))

        path.move(to: tailLeft)
        path.addLine(to: neckLeft)
        path.addLine(to: wingLeft)
        path.addLine(to: end)
        path.addLine(to: wingRight)
        path.addLine(to: neckRight)
        path.addLine(to: tailRight)
        path.closeSubpath()
        return path
    }
}

/// Авторский маячок шага PasteVault Pointer Pin:
/// квадратный корпус 26x26 с центром строго в центре rect, и острый клювик-указатель длиной 6pt под углом 45°
public struct PasteVaultPointerPinShape: Shape {
    public var cornerRadius: CGFloat
    public var beakLength: CGFloat

    public init(cornerRadius: CGFloat = 7, beakLength: CGFloat = 6) {
        self.cornerRadius = cornerRadius
        self.beakLength = beakLength
    }

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let halfSize: CGFloat = 13.0 // квадратный корпус 26x26 pt
        let r = min(cornerRadius, halfSize * 0.7)

        let minX = center.x - halfSize
        let maxX = center.x + halfSize
        let minY = center.y - halfSize
        let maxY = center.y + halfSize

        // Острый кончик клювика, направленный строго из угла (45°)
        let tip = CGPoint(x: maxX + beakLength * 0.9, y: maxY + beakLength * 0.9)

        var path = Path()
        path.move(to: CGPoint(x: minX + r, y: minY))
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: minY + r),
            control: CGPoint(x: maxX, y: minY)
        )
        path.addLine(to: CGPoint(x: maxX, y: maxY - r * 0.9))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: maxX - r * 0.9, y: maxY))
        path.addLine(to: CGPoint(x: minX + r, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: minX, y: maxY - r),
            control: CGPoint(x: minX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addQuadCurve(
            to: CGPoint(x: minX + r, y: minY),
            control: CGPoint(x: minX, y: minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Маленький треугольник подменю `◢` в правом нижнем углу кнопки
public struct SubmenuCornerTriangle: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Треугольный указатель («пипка» ◀), направленный влево на выбранную кнопку инструмента
public struct SubmenuLeftPointerShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

public struct SubmenuLeftPointerBorder: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

public struct SubmenuLeftPointerTriangle: View {
    public let theme: AppTheme

    public init(theme: AppTheme) {
        self.theme = theme
    }

    public var body: some View {
        ZStack {
            SubmenuLeftPointerShape()
                .fill(theme.cardColor.opacity(theme.usesLiquidGlass ? 0.92 : 0.98))
            SubmenuLeftPointerBorder()
                .stroke(theme.borderColor, lineWidth: 1)
        }
        .frame(width: 7, height: 12)
    }
}

// MARK: - Shared Annotation Layer Rendering View

public struct ScreenshotAnnotationLayerView: View {
    public let item: ScreenshotAnnotationItem
    public var canvasSize: CGSize = CGSize(width: 800, height: 600)

    public init(item: ScreenshotAnnotationItem, canvasSize: CGSize = CGSize(width: 800, height: 600)) {
        self.item = item
        self.canvasSize = canvasSize
    }

    public var body: some View {
        Group {
            switch item.payload {
            case .arrow(let start, let end, let color, let lineWidth):
                PasteVaultArrowShape(start: start, end: end, strokeWidth: lineWidth)
                    .fill(color.swiftUIColor)
                    .overlay(
                        PasteVaultArrowShape(start: start, end: end, strokeWidth: lineWidth)
                            .stroke(Color.white.opacity(color == .white ? 0.0 : 0.45), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1.5)

            case .shape(let kind, let start, let end, let color, let lineWidth):
                shapeView(kind: kind, start: start, end: end, color: color, lineWidth: lineWidth)
                    .shadow(color: Color.black.opacity(0.35), radius: 2.5, x: 0, y: 1)

            case .highlighterFreehand(let points, let color, let lineWidth):
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for pt in points.dropFirst() {
                        path.addLine(to: pt)
                    }
                }
                .stroke(
                    color.swiftUIColor.opacity(0.35),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )

            case .highlighterBox(let rect, let color):
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.swiftUIColor.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(color.swiftUIColor.opacity(0.65), lineWidth: 1)
                    )
                    .frame(width: max(2, rect.width), height: max(2, rect.height))
                    .position(x: rect.midX, y: rect.midY)

            case .step(let number, let position, let color, let pointerAngle):
                PasteVaultStepPinBadgeView(number: number, color: color, pointerAngle: pointerAngle)
                    .position(position)

            case .text(let position, let text, let font, let fontSize, let color, let calloutTarget, let maxWidth):
                if !text.isEmpty {
                    let horizontalPadding = ScreenshotEditorEngine.textHorizontalPadding
                    let verticalPadding = ScreenshotEditorEngine.textVerticalPadding
                    let pillRect = ScreenshotEditorEngine.textBoundingRect(
                        position: position,
                        text: text,
                        font: font,
                        fontSize: fontSize,
                        maxWidth: maxWidth,
                        canvasSize: canvasSize
                    )
                    let innerTextWidth = max(60.0, pillRect.width - horizontalPadding * 2.0)
                    let innerTextHeight = max(fontSize, pillRect.height - verticalPadding * 2.0)
                    let bubblePath = ScreenshotEditorEngine.unifiedTextCalloutPath(
                        pillRect: pillRect,
                        cornerRadius: 7.0,
                        calloutTarget: calloutTarget
                    )
                    let nsFont = font.nsFont(size: fontSize, weight: .bold)
                    let singleLineWidth = ceil((text as NSString).size(withAttributes: [.font: nsFont]).width) + 10.0
                    let isMultiline = text.contains("\n") || singleLineWidth > innerTextWidth
                    ZStack {
                        bubblePath
                            .fill(Color.black.opacity(color == .obsidian ? 0.22 : 0.68))
                            .overlay(
                                bubblePath
                                    .stroke(
                                        color.swiftUIColor,
                                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1.5)

                        Text(text)
                            .font(font.font(size: fontSize, weight: .bold))
                            .foregroundStyle(color.swiftUIColor)
                            .multilineTextAlignment(isMultiline ? .leading : .center)
                            .lineLimit(nil)
                            .frame(width: innerTextWidth, alignment: isMultiline ? .leading : .center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: innerTextWidth, height: innerTextHeight, alignment: isMultiline ? .leading : .center)
                            .position(x: pillRect.midX, y: pillRect.midY)
                    }
                }

            case .pixelate:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func shapeView(
        kind: ScreenshotShapeKind,
        start: CGPoint,
        end: CGPoint,
        color: ScreenshotAnnotationColor,
        lineWidth: CGFloat
    ) -> some View {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        switch kind {
        case .roundedRect:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.swiftUIColor, lineWidth: lineWidth)
                .frame(width: max(2, rect.width), height: max(2, rect.height))
                .position(x: rect.midX, y: rect.midY)
        case .rect:
            Rectangle()
                .stroke(color.swiftUIColor, lineWidth: lineWidth)
                .frame(width: max(2, rect.width), height: max(2, rect.height))
                .position(x: rect.midX, y: rect.midY)
        case .ellipse:
            Ellipse()
                .stroke(color.swiftUIColor, lineWidth: lineWidth)
                .frame(width: max(2, rect.width), height: max(2, rect.height))
                .position(x: rect.midX, y: rect.midY)
        case .line:
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(
                color.swiftUIColor,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }
}

/// Визуальный компонент маячка шага PasteVault Pointer Pin с двойной контурной обводкой и стеклянным бликом
public struct PasteVaultStepPinBadgeView: View {
    public let number: Int
    public let color: ScreenshotAnnotationColor
    public var pointerAngle: Double = .pi / 4.0
    public var opacity: Double = 1.0

    public init(number: Int, color: ScreenshotAnnotationColor, pointerAngle: Double = .pi / 4.0, opacity: Double = 1.0) {
        self.number = number
        self.color = color
        self.pointerAngle = pointerAngle
        self.opacity = opacity
    }

    public var body: some View {
        ZStack {
            // Вращающийся корпус с острым носиком (вращается вокруг центра 26x26 квадратного корпуса)
            ZStack {
                PasteVaultPointerPinShape(cornerRadius: 7, beakLength: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                color.swiftUIColor,
                                color.swiftUIColor.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        PasteVaultPointerPinShape(cornerRadius: 7, beakLength: 6)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.95),
                                        Color.white.opacity(0.55)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.6
                            )
                    )
                    .overlay(
                        PasteVaultPointerPinShape(cornerRadius: 7, beakLength: 6)
                            .stroke(Color.black.opacity(0.35), lineWidth: 0.6)
                    )
            }
            .frame(width: 36, height: 36)
            .rotationEffect(Angle(radians: pointerAngle - (.pi / 4.0)), anchor: .center)

            // Цифра номера центрируется СТРОГО в геометрическом центре 26x26 корпуса, всегда вертикально!
            Text("\(number)")
                .font(.system(size: number >= 10 ? 11 : 12.5, weight: .heavy, design: .rounded))
                .foregroundStyle(color == .white ? Color.black : Color.white)
                .frame(width: 26, height: 26, alignment: .center)
        }
        .frame(width: 36, height: 36)
        .shadow(color: Color.black.opacity(0.45), radius: 4, x: 0, y: 2)
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Annotation Interactive Control Handle (●) & Selection Overlay

public struct AnnotationControlHandle: View {
    public let position: CGPoint
    public let theme: AppTheme

    public init(position: CGPoint, theme: AppTheme) {
        self.position = position
        self.theme = theme
    }

    public var body: some View {
        Circle()
            .fill(theme.accentColor)
            .frame(width: 8.5, height: 8.5)
            .overlay(
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 2, x: 0, y: 1)
            .position(position)
            .allowsHitTesting(false)
    }
}

public struct AnnotationSelectionOverlayView: View {
    public let item: ScreenshotAnnotationItem
    public let theme: AppTheme
    public var canvasSize: CGSize = CGSize(width: 800, height: 600)

    public init(item: ScreenshotAnnotationItem, theme: AppTheme, canvasSize: CGSize = CGSize(width: 800, height: 600)) {
        self.item = item
        self.theme = theme
        self.canvasSize = canvasSize
    }

    public var body: some View {
        Group {
            switch item.payload {
            case .arrow(let start, let end, _, _):
                ZStack {
                    AnnotationControlHandle(position: start, theme: theme)
                    AnnotationControlHandle(position: end, theme: theme)
                }

            case .shape(let kind, let start, let end, _, _):
                if kind == .line {
                    ZStack {
                        AnnotationControlHandle(position: start, theme: theme)
                        AnnotationControlHandle(position: end, theme: theme)
                    }
                } else {
                    let rect = CGRect(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y),
                        width: max(4, abs(end.x - start.x)),
                        height: max(4, abs(end.y - start.y))
                    )
                    ZStack {
                        RoundedRectangle(cornerRadius: kind == .roundedRect ? 10 : 0, style: .continuous)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                            )
                            .foregroundStyle(theme.accentColor.opacity(0.85))
                            .frame(width: rect.width + 6, height: rect.height + 6)
                            .position(x: rect.midX, y: rect.midY)

                        AnnotationControlHandle(position: CGPoint(x: rect.minX, y: rect.minY), theme: theme)
                        AnnotationControlHandle(position: CGPoint(x: rect.maxX, y: rect.minY), theme: theme)
                        AnnotationControlHandle(position: CGPoint(x: rect.minX, y: rect.maxY), theme: theme)
                        AnnotationControlHandle(position: CGPoint(x: rect.maxX, y: rect.maxY), theme: theme)
                    }
                }

            case .highlighterBox(let rect, _), .pixelate(let rect, _):
                ZStack {
                    Rectangle()
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                        )
                        .foregroundStyle(theme.accentColor.opacity(0.85))
                        .frame(width: rect.width + 6, height: rect.height + 6)
                        .position(x: rect.midX, y: rect.midY)

                    AnnotationControlHandle(position: CGPoint(x: rect.minX, y: rect.minY), theme: theme)
                    AnnotationControlHandle(position: CGPoint(x: rect.maxX, y: rect.minY), theme: theme)
                    AnnotationControlHandle(position: CGPoint(x: rect.minX, y: rect.maxY), theme: theme)
                    AnnotationControlHandle(position: CGPoint(x: rect.maxX, y: rect.maxY), theme: theme)
                }

            case .step(_, let position, _, let pointerAngle):
                let center = position
                let handlePt = CGPoint(x: center.x + cos(pointerAngle) * 28.0, y: center.y + sin(pointerAngle) * 28.0)
                ZStack {
                    Circle()
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                        )
                        .foregroundStyle(theme.accentColor.opacity(0.80))
                        .frame(width: 38, height: 38)
                        .position(center)

                    Path { path in
                        path.move(to: center)
                        path.addLine(to: handlePt)
                    }
                    .stroke(
                        style: StrokeStyle(lineWidth: 1.0, dash: [2, 2])
                    )
                    .foregroundStyle(theme.accentColor.opacity(0.65))

                    AnnotationControlHandle(position: handlePt, theme: theme)
                }

            case .text(let position, let text, let font, let fontSize, _, let calloutTarget, let maxWidth):
                let rect = ScreenshotEditorEngine.textBoundingRect(
                    position: position,
                    text: text,
                    font: font,
                    fontSize: fontSize,
                    maxWidth: maxWidth,
                    canvasSize: canvasSize
                )
                let leftResizePt = CGPoint(x: rect.minX - 3.0, y: rect.midY)
                let rightResizePt = CGPoint(x: rect.maxX + 3.0, y: rect.midY)
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                        )
                        .foregroundStyle(theme.accentColor.opacity(0.85))
                        .frame(width: rect.width + 6, height: rect.height + 6)
                        .position(x: rect.midX, y: rect.midY)

                    // Левый и правый ползунки изменения ширины текстового блока (капсулы 6x18 pt белого цвета с синей обводкой)
                    Capsule(style: .continuous)
                        .fill(Color.white)
                        .frame(width: 6, height: 18)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(theme.accentColor, lineWidth: 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                        .position(leftResizePt)

                    Capsule(style: .continuous)
                        .fill(Color.white)
                        .frame(width: 6, height: 18)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(theme.accentColor, lineWidth: 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                        .position(rightResizePt)

                    if let target = calloutTarget, !rect.insetBy(dx: -4, dy: -4).contains(target) {
                        // Когда стрелка вытянута — рисуем ТОЛЬКО один кружок-ручку (14x14 pt) на самом острие стрелки
                        Circle()
                            .fill(Color(nsColor: ScreenshotAnnotationColor.sky.nsColor))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 1.8)
                            )
                            .shadow(color: Color.black.opacity(0.5), radius: 3, x: 0, y: 1.5)
                            .position(target)
                    } else {
                        let pullPt = ScreenshotEditorEngine.textCalloutPullHandlePosition(
                            position: position,
                            text: text,
                            font: font,
                            fontSize: fontSize,
                            maxWidth: maxWidth,
                            canvasSize: canvasSize
                        )
                        Path { path in
                            path.move(to: CGPoint(x: rect.maxX + 6, y: rect.midY))
                            path.addLine(to: pullPt)
                        }
                        .stroke(
                            style: StrokeStyle(lineWidth: 1.1, dash: [2, 2])
                        )
                        .foregroundStyle(Color(nsColor: ScreenshotAnnotationColor.sky.nsColor).opacity(0.85))

                        // Интерактивный кружок-ручка (20x20 pt) со значком стрелки СНАРУЖИ за правым краем текстовой плашки (на расстоянии 8 pt от внешней границы)
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(nsColor: ScreenshotAnnotationColor.sky.nsColor),
                                            theme.accentColor
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 1.6)
                                )
                                .shadow(color: Color.black.opacity(0.5), radius: 3.5, x: 0, y: 1.5)

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Color.white)
                        }
                        .position(pullPt)
                    }
                }

            case .highlighterFreehand(let points, _, _):
                if let first = points.first {
                    let minX = points.reduce(first.x) { min($0, $1.x) }
                    let maxX = points.reduce(first.x) { max($0, $1.x) }
                    let minY = points.reduce(first.y) { min($0, $1.y) }
                    let maxY = points.reduce(first.y) { max($0, $1.y) }
                    let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                    Rectangle()
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.0, dash: [4, 3])
                        )
                        .foregroundStyle(theme.accentColor.opacity(0.70))
                        .frame(width: rect.width + 10, height: rect.height + 10)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Холст для финального Retina-рендеринга через ImageRenderer
private struct ScreenshotExportCanvasView: View {
    let image: NSImage
    let annotations: [ScreenshotAnnotationItem]
    let canvasSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: canvasSize.width, height: canvasSize.height)

            ForEach(annotations) { item in
                ScreenshotAnnotationLayerView(item: item, canvasSize: canvasSize)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }
}

// MARK: - Step Cursor Preview Tracker & Isolated Overlay View

@MainActor
public final class StepHoverTracker: ObservableObject {
    @Published public var hoverPoint: CGPoint? = nil

    public init() {}

    public func update(_ point: CGPoint) {
        if let current = hoverPoint {
            if hypot(point.x - current.x, point.y - current.y) >= 0.5 {
                hoverPoint = point
            }
        } else {
            hoverPoint = point
        }
    }

    public func clear() {
        if hoverPoint != nil {
            hoverPoint = nil
        }
    }
}

public struct StepCursorPreviewOverlayView: View {
    @ObservedObject public var tracker: StepHoverTracker
    @ObservedObject public var engine: ScreenshotEditorEngine
    public let isDragging: Bool

    public init(
        tracker: StepHoverTracker,
        engine: ScreenshotEditorEngine,
        isDragging: Bool = false
    ) {
        self.tracker = tracker
        self.engine = engine
        self.isDragging = isDragging
    }

    public var body: some View {
        Group {
            if engine.selectedTool == .step,
               !isDragging,
               let canvasPt = tracker.hoverPoint {
                let centerPos = ScreenshotEditorEngine.stepPinCenter(forTipPoint: canvasPt)
                PasteVaultStepPinBadgeView(
                    number: engine.nextStepNumber,
                    color: engine.selectedColor,
                    opacity: 0.72
                )
                // Остриё носика метки точно совпадает с кончиком курсора мыши (нулевой прыжок при клике)
                .position(centerPos)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Interactive Screenshot Editor Canvas & Floating Toolbars

public struct ScreenshotEditorWorkspaceView: View {
    @ObservedObject public var engine: ScreenshotEditorEngine
    public let sourceImage: NSImage
    public let theme: AppTheme
    public let currentFont: AppFont
    public let windowOpacity: Double
    public let scaleToFit: Bool
    public let zoomScale: CGFloat
    @Binding public var lastCanvasSize: CGSize
    @Binding public var panOffset: CGSize

    @State private var activeDragStart: CGPoint? = nil
    @State private var activeDragCurrent: CGPoint? = nil
    @State private var lastDragPoint: CGPoint? = nil
    @State private var freehandPoints: [CGPoint] = []
    @StateObject private var stepHoverTracker = StepHoverTracker()
    @State private var isCanvasHovered: Bool = false
    @State private var currentCanvasCursor: NSCursor = .crosshair
    @State private var isFontDropdownExpanded: Bool = false
    @FocusState private var isInlineTextFieldFocused: Bool

    // Состояния инструмента «✋ Рука» и интерактивных ручек
    @State private var activeDragHandle: HandlePosition? = nil
    @State private var draggedAnnotationId: UUID? = nil
    @State private var dragInitialAnnotation: ScreenshotAnnotationItem? = nil
    @State private var hasMovedDuringDrag: Bool = false
    @State private var hasRecordedUndoForCurrentDrag: Bool = false
    @State private var wasAlreadySelectedOnDragStart: Bool = false

    // Панорамирование увеличенного скриншота (> 100%) и локальный перехват клавиш
    @State private var isPanningImage: Bool = false
    @State private var panOffsetAtDragStart: CGSize = .zero
    @State private var scrollMonitor: Any? = nil
    @State private var keyDownMonitor: Any? = nil
    @State private var flagsChangedMonitor: Any? = nil
    @State private var rightMouseDownMonitor: Any? = nil
    @State private var didDismissSubmenuOnDragStart: Bool = false

    public init(
        engine: ScreenshotEditorEngine,
        sourceImage: NSImage,
        theme: AppTheme,
        currentFont: AppFont,
        windowOpacity: Double,
        scaleToFit: Bool,
        zoomScale: CGFloat = 1.0,
        lastCanvasSize: Binding<CGSize>,
        panOffset: Binding<CGSize> = .constant(.zero)
    ) {
        self.engine = engine
        self.sourceImage = sourceImage
        self.theme = theme
        self.currentFont = currentFont
        self.windowOpacity = windowOpacity
        self.scaleToFit = scaleToFit
        self.zoomScale = zoomScale
        self._lastCanvasSize = lastCanvasSize
        self._panOffset = panOffset
    }

    public var body: some View {
        GeometryReader { geo in
            let availableSize = CGSize(
                width: max(120, geo.size.width - 110),
                height: max(120, geo.size.height - 36)
            )
            // Фиксированный размер видимой рамки (viewport) при 100%, внутри которой происходит приближение
            let baseViewportSize = computeBaseViewportSize(available: availableSize)

            ZStack(alignment: .leading) {
                // Центрированный интерактивный холст скриншота (фиксированное окно предпросмотра с приближением внутри)
                ZStack {
                    interactiveCanvas(viewportSize: baseViewportSize)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.leading, 68)

                // Левая вертикальная панель инструментов (жёстко зафиксирована по вертикали, подменю в overlay не влияет на её геометрию)
                leftVerticalToolbar
                    .overlay(alignment: .topLeading) {
                        if let submenu = engine.activeSubmenu {
                            submenuContainer(for: submenu)
                                .offset(x: 56)
                        }
                    }
                    .padding(.leading, 18)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .zIndex(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                lastCanvasSize = baseViewportSize
                engine.lastCanvasSize = baseViewportSize
                DispatchQueue.main.async {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
                rightMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [engine] event in
                    guard let window = event.window, window === NSApp.keyWindow else { return event }

                    // Если в момент правого клика активно редактирование текста и курсор находится ВНУТРИ NSTextView
                    if engine.editingTextAnnotationId != nil {
                        let hitView = window.contentView?.hitTest(event.locationInWindow)
                        var isInsideTextView = false
                        var v: NSView? = hitView
                        while let curr = v {
                            if curr is NSTextView {
                                isInsideTextView = true
                                break
                            }
                            v = curr.superview
                        }
                        if isInsideTextView {
                            return event
                        }
                    }

                    // Во всех остальных случаях при клике по холсту или вне редактируемого текстового поля:
                    if engine.editingTextAnnotationId != nil {
                        engine.commitActiveTextEditing()
                        isInlineTextFieldFocused = false
                    }

                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        engine.activeSubmenu = nil
                        isFontDropdownExpanded = false
                        engine.selectedTool = .hand
                        engine.selectedAnnotationId = nil
                    }
                    stepHoverTracker.clear()
                    applyStableCursor(.arrow)

                    return nil
                }
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard zoomScale > 1.001 else { return event }
                    guard isCanvasHovered else { return event }

                    let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
                    let stepX = event.scrollingDeltaX * factor
                    let stepY = event.scrollingDeltaY * factor

                    let maxPanX = max(0, baseViewportSize.width * (zoomScale - 1.0) / 2.0)
                    let maxPanY = max(0, baseViewportSize.height * (zoomScale - 1.0) / 2.0)

                    let newX = min(max(-maxPanX, panOffset.width + stepX), maxPanX)
                    let newY = min(max(-maxPanY, panOffset.height + stepY), maxPanY)

                    panOffset = CGSize(width: newX, height: newY)
                    return nil
                }
                flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    let isShift = event.modifierFlags.contains(.shift)
                    engine.setShiftShortcutHeld(isShift)
                    return event
                }
                keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if ShortcutManager.shared.isRecordingShortcut {
                        return event
                    }
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if engine.editingTextAnnotationId != nil {
                        if event.keyCode == 53 && flags.isEmpty {
                            engine.triggerShortcutHighlight("escape")
                            engine.commitActiveTextEditing()
                            isInlineTextFieldFocused = false
                            return nil
                        }
                        return event
                    }
                    // Когда редактирование текста НЕ активно:
                    // ⌘ + Z (keyCode == 6) отменяет последнее действие и подсвечивает бейдж ⌘Z внизу
                    if flags == .command && (event.keyCode == 6 || event.charactersIgnoringModifiers?.lowercased() == "z") {
                        engine.triggerShortcutHighlight("undo")
                        engine.undo()
                        return nil
                    }
                    // Пробел (Space, keyCode == 49) мгновенно включает инструмент «✋ Рука» и подсвечивает хоткей внизу
                    if event.keyCode == 49 && flags.isEmpty {
                        engine.triggerShortcutHighlight("hand")
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                            engine.selectedTool = .hand
                            engine.activeSubmenu = nil
                            isFontDropdownExpanded = false
                        }
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                        return nil
                    }
                    // Backspace (51) или Delete (117) мгновенно удаляет выделенный элемент и подсвечивает хоткей внизу
                    if (event.keyCode == 51 || event.keyCode == 117) && flags.subtracting([.numericPad, .function]).isEmpty {
                        engine.triggerShortcutHighlight("delete")
                        if engine.selectedAnnotationId != nil {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                engine.deleteSelectedAnnotation()
                            }
                            return nil
                        }
                    }
                    return event
                }
            }
            .onDisappear {
                engine.setShiftShortcutHeld(false)
                if let monitor = rightMouseDownMonitor {
                    NSEvent.removeMonitor(monitor)
                    rightMouseDownMonitor = nil
                }
                if let monitor = scrollMonitor {
                    NSEvent.removeMonitor(monitor)
                    scrollMonitor = nil
                }
                if let monitor = keyDownMonitor {
                    NSEvent.removeMonitor(monitor)
                    keyDownMonitor = nil
                }
                if let monitor = flagsChangedMonitor {
                    NSEvent.removeMonitor(monitor)
                    flagsChangedMonitor = nil
                }
            }
            .onChange(of: zoomScale) { _, newZoom in
                if newZoom <= 1.001 {
                    panOffset = .zero
                } else {
                    let maxPanX = max(0, baseViewportSize.width * (newZoom - 1.0) / 2.0)
                    let maxPanY = max(0, baseViewportSize.height * (newZoom - 1.0) / 2.0)
                    panOffset = CGSize(
                        width: min(max(-maxPanX, panOffset.width), maxPanX),
                        height: min(max(-maxPanY, panOffset.height), maxPanY)
                    )
                }
            }
            .onChange(of: baseViewportSize) { _, newSize in
                lastCanvasSize = newSize
                engine.lastCanvasSize = newSize
            }
            .onChange(of: engine.activeSubmenu) { _, _ in
                isFontDropdownExpanded = false
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultEditorSelectHand"))) { _ in
                guard engine.editingTextAnnotationId == nil else { return }
                engine.triggerShortcutHighlight("hand")
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                    engine.selectedTool = .hand
                    engine.activeSubmenu = nil
                    isFontDropdownExpanded = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pasteVaultEditorDeleteSelected"))) { _ in
                guard engine.editingTextAnnotationId == nil else { return }
                engine.triggerShortcutHighlight("delete")
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                    engine.deleteSelectedAnnotation()
                }
            }
        }
    }

    @ViewBuilder
    private func submenuContainer(for kind: ScreenshotSubmenuKind) -> some View {
        let cardOffset = submenuVerticalOffset(for: kind)
        let pointerY = buttonCenterY(for: kind) - cardOffset

        ZStack(alignment: .topLeading) {
            submenuPanel(for: kind)
                .padding(.leading, 6)

            // Треугольный указатель («пипка» ◀), направленный ровно в центр кнопки
            SubmenuLeftPointerTriangle(theme: theme)
                .position(x: 3.5, y: pointerY)
        }
        .offset(y: cardOffset)
        .transition(.scale(scale: 0.92, anchor: .leading).combined(with: .opacity))
    }

    private func submenuVerticalOffset(for kind: ScreenshotSubmenuKind) -> CGFloat {
        switch kind {
        case .arrow: return 0
        case .text: return 18
        case .shape: return 0
        case .highlighter: return 0
        case .color: return 288
        }
    }

    private func buttonCenterY(for kind: ScreenshotSubmenuKind) -> CGFloat {
        switch kind {
        case .arrow: return 67
        case .text: return 109
        case .shape: return 151
        case .highlighter: return 193
        case .color: return 324
        }
    }

    private func computeBaseViewportSize(available: CGSize) -> CGSize {
        let imgW = max(1, sourceImage.size.width)
        let imgH = max(1, sourceImage.size.height)
        if scaleToFit {
            let ratio = min(available.width / imgW, available.height / imgH)
            let baseW = max(60, imgW * ratio)
            let baseH = max(60, imgH * ratio)
            return CGSize(width: baseW, height: baseH)
        } else {
            let ratio = min(1.0, min(available.width / imgW, available.height / imgH))
            return CGSize(width: max(60, imgW * ratio), height: max(60, imgH * ratio))
        }
    }

    /// Переводит точку клика/курсора внутри видимой рамки `viewportSize` в координаты базового холста с учётом `zoomScale` и `panOffset`
    private func viewportPointToCanvasPoint(_ viewportPoint: CGPoint, viewportSize: CGSize) -> CGPoint {
        let clampedZoom = max(1.0, zoomScale)
        guard clampedZoom > 1.001 else {
            return clampPoint(viewportPoint, in: viewportSize)
        }
        let visibleRect = ScreenshotEditorEngine.visibleCropRect(
            in: viewportSize,
            zoomScale: clampedZoom,
            panOffset: panOffset
        )
        let canvasX = visibleRect.minX + (viewportPoint.x / viewportSize.width) * visibleRect.width
        let canvasY = visibleRect.minY + (viewportPoint.y / viewportSize.height) * visibleRect.height
        return clampPoint(CGPoint(x: canvasX, y: canvasY), in: viewportSize)
    }

    // MARK: - Interactive Canvas

    @ViewBuilder
    private func scaledCanvasLayers(
        viewportSize: CGSize,
        clampedZoom: CGFloat,
        previewPixelatedImage: NSImage
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: previewPixelatedImage)
                .resizable()
                .interpolation(.high)
                .frame(width: viewportSize.width, height: viewportSize.height)
                .allowsHitTesting(false)

            // Отрисовка всех зафиксированных слоёв
            ForEach(engine.annotations) { item in
                annotationInteractiveItemView(item: item, canvasSize: viewportSize)
            }

            // Интерактивные узловые точки редактирования (●) и пунктирная рамка выделения активного элемента (включая выносную стрелку текста)
            if let activeOverlayId = engine.selectedAnnotationId ?? engine.editingTextAnnotationId,
               let activeItem = engine.annotations.first(where: { $0.id == activeOverlayId }) {
                AnnotationSelectionOverlayView(item: activeItem, theme: theme, canvasSize: viewportSize)
                    .allowsHitTesting(false)
            }

            // Живое превью рисуемого элемента во время перетаскивания мышью
            if let previewItem = activePreviewAnnotation() {
                ScreenshotAnnotationLayerView(item: itemWithClampedBounds(previewItem), canvasSize: viewportSize)
                    .allowsHitTesting(false)
            }

            // Живая рамка выделения во время мелкой пикселизации
            if engine.selectedTool == .pixelate,
               let start = activeDragStart,
               let cur = activeDragCurrent {
                let rect = CGRect(
                    x: min(start.x, cur.x),
                    y: min(start.y, cur.y),
                    width: abs(cur.x - start.x),
                    height: abs(cur.y - start.y)
                )
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5 / clampedZoom, dash: [5, 3])
                    )
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: max(2, rect.width), height: max(2, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }

            // Изолированный оверлей для полупрозрачной превью-капли следующего шага
            StepCursorPreviewOverlayView(
                tracker: stepHoverTracker,
                engine: engine,
                isDragging: activeDragStart != nil || draggedAnnotationId != nil
            )
            .allowsHitTesting(false)
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .scaleEffect(clampedZoom, anchor: .center)
        .offset(panOffset)
        .allowsHitTesting(engine.editingTextAnnotationId != nil)
    }

    @ViewBuilder
    private func interactiveCanvas(viewportSize: CGSize) -> some View {
        let clampedZoom = max(1.0, zoomScale)
        let previewPixelatedImage = ScreenshotEditorEngine.applyPixelateLayers(
            to: sourceImage,
            annotations: engine.annotations + activePreviewAnnotationAsArray(),
            canvasSize: viewportSize
        )
        let outerBorderColor = theme.isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.32)
        let primaryShadowColor = theme.isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.35)
        let primaryShadowY: CGFloat = theme.isDark ? 0 : 6
        let secondaryShadowColor = theme.isDark ? Color.black.opacity(0.5) : Color.clear

        ZStack(alignment: .topLeading) {
            scaledCanvasLayers(
                viewportSize: viewportSize,
                clampedZoom: clampedZoom,
                previewPixelatedImage: previewPixelatedImage
            )
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .background(CanvasCursorEnforcer(cursor: currentCanvasCursor).allowsHitTesting(false))
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        // 1. Внутренний светлый кант 1 pt непосредственно по границе скриншота (отделяет даже абсолютно чёрный скриншот)
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.white.opacity(0.38), lineWidth: 1.0)
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let pt):
                if !isCanvasHovered {
                    isCanvasHovered = true
                }
                if engine.selectedTool == .step {
                    let canvasPt = viewportPointToCanvasPoint(pt, viewportSize: viewportSize)
                    stepHoverTracker.update(canvasPt)
                } else {
                    stepHoverTracker.clear()
                }
                updateCursor(at: pt, viewportSize: viewportSize)
            case .ended:
                isCanvasHovered = false
                stepHoverTracker.clear()
                applyStableCursor(.arrow)
            }
        }
        .gesture(canvasDragGesture(viewportSize: viewportSize))
        // 2. Двухконтурная внешняя рамка с отступом 2 pt снаружи и адаптивная тень / светлое свечение в тёмной теме
        .padding(2)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(outerBorderColor, lineWidth: 1.5)
                .allowsHitTesting(false)
        )
        .shadow(color: primaryShadowColor, radius: 18, x: 0, y: primaryShadowY)
        .shadow(color: secondaryShadowColor, radius: 6, x: 0, y: 2)
    }

    private func applyStableCursor(_ targetCursor: NSCursor) {
        if currentCanvasCursor !== targetCursor {
            currentCanvasCursor = targetCursor
        }
        if NSCursor.current !== targetCursor {
            targetCursor.set()
        }
    }

    private func updateCursor(at viewportPoint: CGPoint, viewportSize: CGSize) {
        let clampedZoom = max(1.0, zoomScale)
        if activeDragStart != nil {
            if let handle = activeDragHandle {
                if handle == .textWidthLeft || handle == .textWidthRight {
                    applyStableCursor(.resizeLeftRight)
                } else {
                    applyStableCursor(.crosshair)
                }
                return
            }
            if engine.selectedTool == .hand {
                if isPanningImage || draggedAnnotationId != nil {
                    applyStableCursor(.closedHand)
                }
                return
            }
        }
        let canvasPoint = viewportPointToCanvasPoint(viewportPoint, viewportSize: viewportSize)
        if let activeOverlayId = engine.selectedAnnotationId ?? engine.editingTextAnnotationId,
           let activeItem = engine.annotations.first(where: { $0.id == activeOverlayId }),
           let handle = ScreenshotEditorEngine.hitTestHandle(point: canvasPoint, in: activeItem) {
            if handle == .textWidthLeft || handle == .textWidthRight {
                applyStableCursor(.resizeLeftRight)
            } else {
                applyStableCursor(.crosshair)
            }
            return
        }
        if engine.selectedTool == .hand {
            if ScreenshotEditorEngine.hitTestBody(point: canvasPoint, in: engine.annotations) != nil {
                applyStableCursor(.openHand)
                return
            }
            if clampedZoom > 1.001 {
                applyStableCursor(.openHand)
                return
            }
            applyStableCursor(.arrow)
        } else {
            switch engine.selectedTool {
            case .arrow, .shape, .highlighter, .pixelate:
                applyStableCursor(.crosshair)
            case .text:
                applyStableCursor(.iBeam)
            case .step:
                applyStableCursor(.arrow)
            case .hand:
                applyStableCursor(.arrow)
            }
        }
    }

    private func itemWithClampedBounds(_ item: ScreenshotAnnotationItem) -> ScreenshotAnnotationItem {
        item
    }

    @ViewBuilder
    private func annotationInteractiveItemView(item: ScreenshotAnnotationItem, canvasSize: CGSize) -> some View {
        switch item.payload {
        case .step(let number, let position, let color, let pointerAngle):
            PasteVaultStepPinBadgeView(number: number, color: color, pointerAngle: pointerAngle)
                .position(position)
                .allowsHitTesting(false)

        case .text(let position, let text, let font, let fontSize, let color, let calloutTarget, let maxWidth):
            if engine.editingTextAnnotationId == item.id {
                let horizontalPadding = ScreenshotEditorEngine.textHorizontalPadding
                let verticalPadding = ScreenshotEditorEngine.textVerticalPadding
                let displayStr = text.isEmpty ? " " : text
                let editRect = ScreenshotEditorEngine.textBoundingRect(
                    position: position,
                    text: displayStr,
                    font: font,
                    fontSize: fontSize,
                    maxWidth: maxWidth,
                    canvasSize: canvasSize
                )
                let innerTextWidth = max(60.0, editRect.width - horizontalPadding * 2.0)
                let innerTextHeight = max(fontSize, editRect.height - verticalPadding * 2.0)
                let bubblePath = ScreenshotEditorEngine.unifiedTextCalloutPath(
                    pillRect: editRect,
                    cornerRadius: 7.0,
                    calloutTarget: calloutTarget
                )
                let nsFont = font.nsFont(size: fontSize, weight: .bold)
                let singleLineWidth = ceil((displayStr as NSString).size(withAttributes: [.font: nsFont]).width) + 10.0
                let isMultiline = text.contains("\n") || singleLineWidth > innerTextWidth
                ZStack {
                    bubblePath
                        .fill(Color.black.opacity(0.75))
                        .overlay(
                            bubblePath
                                .stroke(
                                    color.swiftUIColor,
                                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                                )
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1.5)
                        .allowsHitTesting(false)

                    TextField(
                        "",
                        text: Binding(
                            get: { text },
                            set: { engine.updateText(id: item.id, newText: $0, canvasSize: canvasSize) }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(font.font(size: fontSize, weight: .bold))
                    .foregroundStyle(color.swiftUIColor)
                    .multilineTextAlignment(isMultiline ? .leading : .center)
                    .lineLimit(nil)
                    .frame(width: innerTextWidth, alignment: isMultiline ? .leading : .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: innerTextWidth, height: innerTextHeight, alignment: isMultiline ? .leading : .center)
                    .environment(\.colorScheme, .dark)
                    .tint(.white)
                    .background(WhiteCaretEnforcer(trigger: text))
                    .focused($isInlineTextFieldFocused)
                    .onSubmit {
                        engine.commitActiveTextEditing()
                    }
                    .position(x: editRect.midX, y: editRect.midY)
                    .onAppear {
                        isInlineTextFieldFocused = true
                    }
                }
            } else {
                ScreenshotAnnotationLayerView(item: item, canvasSize: canvasSize)
                    .allowsHitTesting(false)
            }

        default:
            ScreenshotAnnotationLayerView(item: item, canvasSize: canvasSize)
                .allowsHitTesting(false)
        }
    }

    private func canvasDragGesture(viewportSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = viewportPointToCanvasPoint(value.startLocation, viewportSize: viewportSize)
                let rawCur = viewportPointToCanvasPoint(value.location, viewportSize: viewportSize)
                let isShift = NSEvent.modifierFlags.contains(.shift)
                let clampedZoom = max(1.0, zoomScale)

                if activeDragStart == nil {
                    // Если открыто выпадающее подменю или список шрифтов — первый клик ТОЛЬКО закрывает его!
                    if engine.activeSubmenu != nil || isFontDropdownExpanded {
                        withAnimation(.easeOut(duration: 0.15)) {
                            engine.activeSubmenu = nil
                            isFontDropdownExpanded = false
                        }
                        didDismissSubmenuOnDragStart = true
                        return
                    }

                    // 0. Проверяем попадание в ручку выносной стрелки текста или узловую точку активного/выделенного элемента
                    if let targetId = engine.selectedAnnotationId ?? engine.editingTextAnnotationId,
                       let targetItem = engine.annotations.first(where: { $0.id == targetId }),
                       let handle = ScreenshotEditorEngine.hitTestHandle(point: start, in: targetItem) {
                        if handle == .textCalloutTip {
                            let isDoubleClick = CardClickDetector.registerTap(itemId: "calloutTip_\(targetId.uuidString)")
                            if isDoubleClick {
                                engine.recordUndoSnapshot()
                                engine.updateTextCalloutTarget(id: targetId, to: nil)
                                didDismissSubmenuOnDragStart = true
                                return
                            }
                        }
                        if engine.editingTextAnnotationId != nil {
                            engine.commitActiveTextEditing()
                            isInlineTextFieldFocused = false
                            engine.selectedAnnotationId = targetId
                        }
                        activeDragStart = start
                        lastDragPoint = start
                        hasMovedDuringDrag = false
                        hasRecordedUndoForCurrentDrag = false
                        wasAlreadySelectedOnDragStart = true
                        isPanningImage = false
                        panOffsetAtDragStart = panOffset
                        activeDragHandle = handle
                        draggedAnnotationId = targetId
                        dragInitialAnnotation = targetItem
                        return
                    }

                    // Если сейчас активно редактируется текстовая надпись — клик мимо неё завершает ввод и снимает фокус
                    if let activeTextId = engine.editingTextAnnotationId {
                        let hitId = ScreenshotEditorEngine.hitTestBody(point: start, in: engine.annotations)
                        if hitId != activeTextId {
                            engine.commitActiveTextEditing()
                            isInlineTextFieldFocused = false
                            didDismissSubmenuOnDragStart = true
                            return
                        }
                    }

                    activeDragStart = start
                    lastDragPoint = start
                    hasMovedDuringDrag = false
                    hasRecordedUndoForCurrentDrag = false
                    wasAlreadySelectedOnDragStart = false
                    isPanningImage = false
                    panOffsetAtDragStart = panOffset

                    if engine.selectedTool == .hand {
                        // 1. Попадание в интерактивную ручку (●) текущего выделенного элемента
                        if let selId = engine.selectedAnnotationId,
                           let selItem = engine.annotations.first(where: { $0.id == selId }),
                           let handle = ScreenshotEditorEngine.hitTestHandle(point: start, in: selItem) {
                            activeDragHandle = handle
                            draggedAnnotationId = selId
                            dragInitialAnnotation = selItem
                        }
                        // 2. Попадание в тело любого элемента на холсте (включая клик внутри фигуры или по тексту/стрелке текста)
                        else if let hitId = ScreenshotEditorEngine.hitTestBody(point: start, in: engine.annotations) {
                            wasAlreadySelectedOnDragStart = (engine.selectedAnnotationId == hitId)
                            let isDoubleClick = CardClickDetector.registerTap(itemId: hitId.uuidString)
                            engine.selectedAnnotationId = hitId
                            draggedAnnotationId = hitId
                            activeDragHandle = nil
                            let hitItem = engine.annotations.first(where: { $0.id == hitId })
                            dragInitialAnnotation = hitItem
                            if let item = hitItem,
                               case .text(_, _, let font, let fontSize, let color, _, _) = item.payload {
                                engine.selectedFont = font
                                engine.selectedFontSize = fontSize
                                engine.selectedColor = color
                                if isDoubleClick {
                                    engine.beginEditingTextAnnotation(id: hitId)
                                    isInlineTextFieldFocused = true
                                    didDismissSubmenuOnDragStart = true
                                    return
                                }
                            }
                        }
                        // 3. Клик в пустое место холста / скриншот
                        else {
                            engine.selectedAnnotationId = nil
                            draggedAnnotationId = nil
                            activeDragHandle = nil
                            dragInitialAnnotation = nil
                            DispatchQueue.main.async {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                            }
                            if clampedZoom > 1.001 {
                                isPanningImage = true
                            }
                        }
                    } else if engine.selectedTool == .text {
                        if let hitId = ScreenshotEditorEngine.hitTestBody(point: start, in: engine.annotations),
                           let item = engine.annotations.first(where: { $0.id == hitId }),
                           case .text = item.payload {
                            engine.beginEditingTextAnnotation(id: hitId)
                            isInlineTextFieldFocused = true
                            didDismissSubmenuOnDragStart = true
                            return
                        }
                    }
                }

                if didDismissSubmenuOnDragStart { return }
                guard let effectiveStart = activeDragStart else { return }

                // Обработка перетаскивания интерактивной ручки (включая выносную стрелку текста в любом инструменте)
                if let handle = activeDragHandle, let id = draggedAnnotationId {
                    let totalDist = hypot(rawCur.x - effectiveStart.x, rawCur.y - effectiveStart.y)
                    if totalDist > 2.0 {
                        hasMovedDuringDrag = true
                        if !hasRecordedUndoForCurrentDrag {
                            engine.recordUndoSnapshot()
                            hasRecordedUndoForCurrentDrag = true
                        }
                    }
                    let cur = clampPoint(rawCur, in: viewportSize)
                    engine.updateAnnotationHandle(id: id, handle: handle, to: cur, isShiftPressed: isShift, canvasSize: viewportSize)
                    if handle == .textWidthLeft || handle == .textWidthRight {
                        applyStableCursor(.resizeLeftRight)
                    } else {
                        applyStableCursor(.crosshair)
                    }
                    return
                }

                if engine.selectedTool == .hand {
                    if isPanningImage && clampedZoom > 1.001 {
                        let deltaX = value.location.x - value.startLocation.x
                        let deltaY = value.location.y - value.startLocation.y
                        let proposedX = panOffsetAtDragStart.width + deltaX
                        let proposedY = panOffsetAtDragStart.height + deltaY
                        let maxPanX = max(0, viewportSize.width * (clampedZoom - 1.0) / 2.0)
                        let maxPanY = max(0, viewportSize.height * (clampedZoom - 1.0) / 2.0)
                        panOffset = CGSize(
                            width: min(max(-maxPanX, proposedX), maxPanX),
                            height: min(max(-maxPanY, proposedY), maxPanY)
                        )
                        applyStableCursor(.closedHand)
                        return
                    }

                    let totalDist = hypot(rawCur.x - effectiveStart.x, rawCur.y - effectiveStart.y)
                    if totalDist > 2.0 {
                        hasMovedDuringDrag = true
                        if !hasRecordedUndoForCurrentDrag {
                            engine.recordUndoSnapshot()
                            hasRecordedUndoForCurrentDrag = true
                        }
                    }

                    if let id = draggedAnnotationId, let lastPt = lastDragPoint {
                        let delta = CGPoint(x: rawCur.x - lastPt.x, y: rawCur.y - lastPt.y)
                        if abs(delta.x) > 0.001 || abs(delta.y) > 0.001 {
                            engine.translateAnnotation(id: id, by: delta)
                        }
                        lastDragPoint = rawCur
                        applyStableCursor(.closedHand)
                    }
                } else {
                    let adjustedCur = ScreenshotEditorEngine.adjustedDragEndPoint(
                        start: effectiveStart,
                        rawEnd: rawCur,
                        tool: engine.selectedTool,
                        shapeKind: engine.selectedShapeKind,
                        isShiftPressed: isShift
                    )
                    let cur = clampPoint(adjustedCur, in: viewportSize)
                    activeDragCurrent = cur

                    if engine.selectedTool == .highlighter && engine.selectedHighlighterMode == .freehand {
                        if freehandPoints.isEmpty {
                            freehandPoints.append(effectiveStart)
                        }
                        freehandPoints.append(cur)
                    }
                }
            }
            .onEnded { value in
                if didDismissSubmenuOnDragStart {
                    didDismissSubmenuOnDragStart = false
                    activeDragStart = nil
                    activeDragCurrent = nil
                    return
                }

                let start = activeDragStart ?? viewportPointToCanvasPoint(value.startLocation, viewportSize: viewportSize)
                let rawEnd = viewportPointToCanvasPoint(value.location, viewportSize: viewportSize)
                let isShift = NSEvent.modifierFlags.contains(.shift)
                let adjustedEnd = ScreenshotEditorEngine.adjustedDragEndPoint(
                    start: start,
                    rawEnd: rawEnd,
                    tool: engine.selectedTool,
                    shapeKind: engine.selectedShapeKind,
                    isShiftPressed: isShift
                )
                let end = clampPoint(adjustedEnd, in: viewportSize)
                let distance = hypot(end.x - start.x, end.y - start.y)
                let endedHandle = activeDragHandle
                let endedId = draggedAnnotationId

                defer {
                    activeDragStart = nil
                    activeDragCurrent = nil
                    lastDragPoint = nil
                    activeDragHandle = nil
                    draggedAnnotationId = nil
                    dragInitialAnnotation = nil
                    hasMovedDuringDrag = false
                    hasRecordedUndoForCurrentDrag = false
                    wasAlreadySelectedOnDragStart = false
                    isPanningImage = false
                    panOffsetAtDragStart = .zero
                    freehandPoints.removeAll()
                    updateCursor(at: value.location, viewportSize: viewportSize)
                }

                if let handle = endedHandle, let id = endedId {
                    if handle == .textCalloutPull || handle == .textCalloutTip {
                        engine.finalizeTextCalloutDrag(id: id)
                    }
                    return
                }

                if engine.selectedTool == .hand {
                    // Повторный клик без перетаскивания по уже выбранному тексту открывает режим редактирования этого текста
                    if !hasMovedDuringDrag,
                       wasAlreadySelectedOnDragStart,
                       let hitId = draggedAnnotationId,
                       let item = engine.annotations.first(where: { $0.id == hitId }),
                       case .text = item.payload {
                        engine.beginEditingTextAnnotation(id: hitId)
                        isInlineTextFieldFocused = true
                    }
                    return
                }

                switch engine.selectedTool {
                case .hand:
                    break

                case .step:
                    TapticSoundAndHaptics.shared.performDialTick()
                    let centerPos = ScreenshotEditorEngine.stepPinCenter(forTipPoint: end)
                    _ = engine.addStepPin(at: centerPos)

                case .text:
                    if engine.editingTextAnnotationId != nil {
                        engine.commitActiveTextEditing()
                        isInlineTextFieldFocused = false
                    } else {
                        let newId = engine.addText(
                            tr("Текст", "Text"),
                            at: end,
                            maxWidth: nil,
                            canvasSize: viewportSize
                        )
                        engine.beginEditingTextAnnotation(id: newId)
                        isInlineTextFieldFocused = true
                    }

                case .arrow:
                    if distance >= 6 {
                        _ = engine.addArrow(from: start, to: end)
                    }

                case .shape:
                    if distance >= 6 {
                        _ = engine.addShape(from: start, to: end)
                    }

                case .highlighter:
                    if engine.selectedHighlighterMode == .freehand {
                        if freehandPoints.count >= 2 {
                            _ = engine.addFreehandHighlighter(points: freehandPoints)
                        }
                    } else {
                        let rect = CGRect(
                            x: min(start.x, end.x),
                            y: min(start.y, end.y),
                            width: abs(end.x - start.x),
                            height: abs(end.y - start.y)
                        )
                        if rect.width >= 6 && rect.height >= 4 {
                            _ = engine.addBoxHighlighter(rect: rect)
                        }
                    }

                case .pixelate:
                    let rect = CGRect(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y),
                        width: abs(end.x - start.x),
                        height: abs(end.y - start.y)
                    )
                    if rect.width >= 6 && rect.height >= 6 {
                        _ = engine.addPixelate(rect: rect, pixelScale: 6.0)
                    }
                }
            }
    }

    private func activePreviewAnnotation() -> ScreenshotAnnotationItem? {
        guard let start = activeDragStart, let cur = activeDragCurrent else { return nil }
        let dist = hypot(cur.x - start.x, cur.y - start.y)
        switch engine.selectedTool {
        case .arrow:
            guard dist >= 4 else { return nil }
            return ScreenshotAnnotationItem(
                payload: .arrow(
                    start: start,
                    end: cur,
                    color: engine.selectedColor,
                    lineWidth: engine.selectedStrokeWidth
                )
            )
        case .shape:
            guard dist >= 4 else { return nil }
            return ScreenshotAnnotationItem(
                payload: .shape(
                    kind: engine.selectedShapeKind,
                    start: start,
                    end: cur,
                    color: engine.selectedColor,
                    lineWidth: engine.selectedStrokeWidth
                )
            )
        case .highlighter:
            if engine.selectedHighlighterMode == .freehand {
                guard freehandPoints.count >= 2 else { return nil }
                return ScreenshotAnnotationItem(
                    payload: .highlighterFreehand(
                        points: freehandPoints,
                        color: engine.selectedColor,
                        lineWidth: max(14, engine.selectedStrokeWidth * 3.2)
                    )
                )
            } else {
                let rect = CGRect(
                    x: min(start.x, cur.x),
                    y: min(start.y, cur.y),
                    width: abs(cur.x - start.x),
                    height: abs(cur.y - start.y)
                )
                guard rect.width >= 3, rect.height >= 3 else { return nil }
                return ScreenshotAnnotationItem(
                    payload: .highlighterBox(rect: rect, color: engine.selectedColor)
                )
            }
        case .pixelate:
            let rect = CGRect(
                x: min(start.x, cur.x),
                y: min(start.y, cur.y),
                width: abs(cur.x - start.x),
                height: abs(cur.y - start.y)
            )
            guard rect.width >= 4, rect.height >= 4 else { return nil }
            return ScreenshotAnnotationItem(
                payload: .pixelate(rect: rect, pixelScale: 6.0)
            )
        case .text, .step, .hand:
            return nil
        }
    }

    private func activePreviewAnnotationAsArray() -> [ScreenshotAnnotationItem] {
        if let item = activePreviewAnnotation(), case .pixelate = item.payload {
            return [item]
        }
        return []
    }

    private func clampPoint(_ pt: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, pt.x), size.width),
            y: min(max(0, pt.y), size.height)
        )
    }

    // MARK: - Left Vertical Toolbar

    private var leftVerticalToolbar: some View {
        VStack(spacing: 6) {
            // 1-6. Основные инструменты разметки
            ForEach(ScreenshotTool.allCases) { tool in
                let isSelected = (engine.selectedTool == tool)
                EditorToolButton(
                    isSelected: isSelected,
                    hasSubmenu: tool.hasSubmenu,
                    theme: theme,
                    tooltip: tool.title(),
                    action: {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                            engine.selectTool(tool)
                        }
                    }
                ) {
                    if tool == .step {
                        ZStack {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(engine.nextStepNumber)")
                                .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 3)
                                .background(theme.accentColor)
                                .foregroundStyle(Color.white)
                                .clipShape(Capsule())
                                .offset(x: 8, y: -7)
                        }
                    } else {
                        Image(systemName: tool.iconName)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }

            Divider()
                .frame(width: 26)
                .background(theme.borderColor)
                .padding(.vertical, 2)

            // 7. Единственная нижняя кнопка после разделителя — Палитра цветов (🔴 + уголок ◢)
            EditorToolButton(
                isSelected: engine.activeSubmenu == .color,
                hasSubmenu: true,
                theme: theme,
                tooltip: tr("Цвет разметки", "Annotation Color"),
                action: {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        engine.toggleSubmenu(.color)
                    }
                }
            ) {
                Circle()
                    .fill(engine.selectedColor.swiftUIColor)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .strokeBorder(theme.primaryText.opacity(0.85), lineWidth: 1.5)
                    )
                    .shadow(color: engine.selectedColor.swiftUIColor.opacity(0.5), radius: 3)
            }
        }
        .padding(7)
        .liquidGlassCard(theme: theme, windowOpacity: windowOpacity, cornerRadius: 12)
        .shadow(color: Color.black.opacity(theme.isLight ? 0.18 : 0.50), radius: 14, x: 0, y: 6)
    }

    // MARK: - Submenu Popover Cards

    @ViewBuilder
    private func submenuPanel(for kind: ScreenshotSubmenuKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch kind {
            case .arrow:
                arrowSubmenuContent
            case .text:
                textSubmenuContent
            case .shape:
                shapeSubmenuContent
            case .highlighter:
                highlighterSubmenuContent
            case .color:
                colorSubmenuContent
            }
        }
        .padding(12)
        .frame(width: 245)
        .liquidGlassCard(theme: theme, windowOpacity: windowOpacity, cornerRadius: 12)
        .shadow(color: Color.black.opacity(theme.isLight ? 0.18 : 0.50), radius: 16, x: 0, y: 8)
    }

    private var arrowSubmenuContent: some View {
        strokeWidthPickerRow
    }

    private var textSubmenuContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Размер шрифта", "Font Size"))
                .font(currentFont.font(size: 11, weight: .bold))
                .foregroundStyle(theme.secondaryText)

            HStack(spacing: 5) {
                ForEach(ScreenshotEditorEngine.availableFontSizes, id: \.self) { size in
                    let isSelected = (engine.selectedFontSize == size)
                    Button {
                        engine.updateSelectedAnnotationFontSize(size)
                        engine.updateActiveTextStyle(fontSize: size)
                    } label: {
                        Text("\(Int(size))")
                            .font(currentFont.font(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? Color.white : theme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(isSelected ? theme.accentColor : theme.primaryText.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isSelected ? theme.accentColor : theme.borderColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .background(theme.borderColor)

            Text(tr("Шрифт текста", "Text Font"))
                .font(currentFont.font(size: 11, weight: .bold))
                .foregroundStyle(theme.secondaryText)

            // Компактная плашка выбора шрифта в едином стиле выпадающих списков PasteVault (по умолчанию Inter ▾)
            Button {
                isFontDropdownExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "textformat")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.accentColor)

                    Text(engine.selectedFont.title)
                        .font(engine.selectedFont.font(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.down")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(theme.secondaryText)
                        .rotationEffect(.degrees(isFontDropdownExpanded ? 180 : 0))
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isFontDropdownExpanded ? theme.accentColor.opacity(0.14) : theme.primaryText.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isFontDropdownExpanded ? theme.accentColor.opacity(0.65) : theme.borderColor,
                            lineWidth: 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isFontDropdownExpanded, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(AppFont.allCases) { fontItem in
                        FontDropdownItemRow(
                            fontItem: fontItem,
                            isSelected: engine.selectedFont == fontItem,
                            theme: theme
                        ) {
                            engine.updateSelectedAnnotationFont(fontItem)
                            engine.updateActiveTextStyle(font: fontItem)
                            isFontDropdownExpanded = false
                        }
                    }
                }
                .padding(6)
                .frame(width: 210)
                .background(theme.cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.borderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
                .environment(\.colorScheme, theme.isLight ? .light : .dark)
            }
        }
    }

    private var shapeSubmenuContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Форма фигуры", "Shape Type"))
                .font(currentFont.font(size: 11, weight: .bold))
                .foregroundStyle(theme.secondaryText)

            VStack(spacing: 4) {
                ForEach(ScreenshotShapeKind.allCases) { kind in
                    let isSelected = (engine.selectedShapeKind == kind)
                    Button {
                        engine.updateSelectedAnnotationShapeKind(kind)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.iconName)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 18)
                            Text(kind.title())
                                .font(currentFont.font(size: 11.5, weight: isSelected ? .semibold : .regular))
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(theme.accentColor)
                            }
                        }
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(isSelected ? theme.accentColor.opacity(0.22) : theme.primaryText.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .background(theme.borderColor)

            strokeWidthPickerRow
        }
    }

    private var highlighterSubmenuContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Режим маркера (прозрачность 35%)", "Highlighter Mode (35% Opacity)"))
                .font(currentFont.font(size: 11, weight: .bold))
                .foregroundStyle(theme.secondaryText)

            VStack(spacing: 4) {
                ForEach(ScreenshotHighlighterMode.allCases) { mode in
                    let isSelected = (engine.selectedHighlighterMode == mode)
                    Button {
                        engine.selectedHighlighterMode = mode
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 18)
                            Text(mode.title())
                                .font(currentFont.font(size: 11.5, weight: isSelected ? .semibold : .regular))
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(theme.accentColor)
                            }
                        }
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(isSelected ? theme.accentColor.opacity(0.22) : theme.primaryText.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .background(theme.borderColor)

            strokeWidthPickerRow
        }
    }

    private var colorSubmenuContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Палитра цветов", "Color Palette"))
                .font(currentFont.font(size: 11, weight: .bold))
                .foregroundStyle(theme.secondaryText)

            HStack(spacing: 8) {
                ForEach(ScreenshotAnnotationColor.allCases) { colorItem in
                    let isSelected = (engine.selectedColor == colorItem)
                    Button {
                        engine.updateSelectedAnnotationColor(colorItem)
                        engine.updateActiveTextStyle(color: colorItem)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(colorItem.swiftUIColor)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isSelected ? theme.primaryText : theme.borderColor,
                                            lineWidth: isSelected ? 2.2 : 1
                                        )
                                )
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(colorItem == .white ? Color.black : Color.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(colorItem.title())
                }
            }
        }
    }

    private var strokeWidthPickerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Толщина линии", "Stroke Width"))
                .font(currentFont.font(size: 11, weight: .bold))
                .foregroundStyle(theme.secondaryText)

            VStack(spacing: 5) {
                ForEach(ScreenshotEditorEngine.availableStrokeWidths, id: \.self) { width in
                    let isSelected = (engine.selectedStrokeWidth == width)
                    Button {
                        engine.updateSelectedAnnotationStrokeWidth(width)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(Int(width)) pt")
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                                .foregroundStyle(theme.primaryText)
                                .frame(width: 38, alignment: .leading)

                            Capsule()
                                .fill(isSelected ? theme.accentColor : theme.primaryText.opacity(0.78))
                                .frame(height: width)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(isSelected ? theme.accentColor.opacity(0.22) : theme.primaryText.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct FontDropdownItemRow: View {
    let fontItem: AppFont
    let isSelected: Bool
    let theme: AppTheme
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(fontItem.title)
                    .font(fontItem.font(size: 12, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if isSelected {
                    Image(systemName: "checkmark")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? theme.accentColor.opacity(0.20) : (isHovered ? theme.accentColor.opacity(0.12) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

// MARK: - Toolbar Button with `◢` Submenu Corner Indicator

private struct EditorToolButton<Content: View>: View {
    let isSelected: Bool
    let hasSubmenu: Bool
    let theme: AppTheme
    let tooltip: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                content()
                    .foregroundStyle(isSelected ? Color.white : theme.primaryText)
                    .frame(width: 36, height: 36)

                if hasSubmenu {
                    SubmenuCornerTriangle()
                        .fill(isSelected ? Color.white : theme.secondaryText.opacity(0.75))
                        .frame(width: 5.5, height: 5.5)
                        .padding(3.5)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? theme.accentColor
                            : (isHovered ? theme.primaryText.opacity(0.14) : theme.primaryText.opacity(0.06))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? theme.accentColor.opacity(0.85)
                            : theme.borderColor.opacity(isHovered ? 1.0 : 0.7),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}

// MARK: - AppKit Cursor Rect Enforcer for Flicker-Free Canvas Cursor

private struct CanvasCursorEnforcer: NSViewRepresentable {
    let cursor: NSCursor

    final class CursorRectNSView: NSView {
        var targetCursor: NSCursor = .crosshair {
            didSet {
                if oldValue !== targetCursor {
                    window?.invalidateCursorRects(for: self)
                    targetCursor.set()
                }
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: targetCursor)
        }
    }

    func makeNSView(context: Context) -> CursorRectNSView {
        let view = CursorRectNSView(frame: .zero)
        view.targetCursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorRectNSView, context: Context) {
        if nsView.targetCursor !== cursor {
            nsView.targetCursor = cursor
        }
    }
}

// MARK: - White Blinking Caret Enforcer for Dark Text Pill

private struct WhiteCaretEnforcer: NSViewRepresentable {
    var trigger: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        applyWhiteCaret(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyWhiteCaret(from: nsView)
    }

    private func applyWhiteCaret(from view: NSView) {
        for delay in [0.0, 0.02, 0.06] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let window = view.window ?? NSApp.keyWindow else { return }
                if let tv = window.firstResponder as? NSTextView {
                    tv.appearance = NSAppearance(named: .darkAqua)
                    tv.insertionPointColor = .white
                    tv.drawsBackground = false
                    tv.textContainerInset = .zero
                    tv.textContainer?.lineFragmentPadding = 0
                    tv.needsDisplay = true
                }
                if let fe = window.fieldEditor(false, for: nil) as? NSTextView {
                    fe.appearance = NSAppearance(named: .darkAqua)
                    fe.insertionPointColor = .white
                    fe.drawsBackground = false
                    fe.textContainerInset = .zero
                    fe.textContainer?.lineFragmentPadding = 0
                }
            }
        }
    }
}

// MARK: - Interactive Bottom Shortcut Bar with Press Highlight & Scale Animation

public struct ScreenshotEditorBottomShortcutBar: View {
    @ObservedObject public var engine: ScreenshotEditorEngine
    public let theme: AppTheme
    public let currentFont: AppFont
    public let windowOpacity: Double
    public var onUndo: () -> Void
    public var onSelectHand: () -> Void
    public var onDeleteSelected: () -> Void
    public var onStepZoom: () -> Void
    public var onSaveCopy: () -> Void
    public var onEscape: () -> Void

    public init(
        engine: ScreenshotEditorEngine,
        theme: AppTheme,
        currentFont: AppFont,
        windowOpacity: Double,
        onUndo: @escaping () -> Void = {},
        onSelectHand: @escaping () -> Void = {},
        onDeleteSelected: @escaping () -> Void = {},
        onStepZoom: @escaping () -> Void = {},
        onSaveCopy: @escaping () -> Void = {},
        onEscape: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.theme = theme
        self.currentFont = currentFont
        self.windowOpacity = windowOpacity
        self.onUndo = onUndo
        self.onSelectHand = onSelectHand
        self.onDeleteSelected = onDeleteSelected
        self.onStepZoom = onStepZoom
        self.onSaveCopy = onSaveCopy
        self.onEscape = onEscape
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Spacer(minLength: 10)

            shortcutPill(
                id: "undo",
                key: "⌘Z",
                label: tr("Отмена", "Undo"),
                action: {
                    engine.triggerShortcutHighlight("undo")
                    onUndo()
                }
            )
            shortcutPill(
                id: "hand",
                key: tr("Пробел", "Space"),
                label: tr("Рука", "Hand"),
                action: {
                    engine.triggerShortcutHighlight("hand")
                    onSelectHand()
                }
            )
            shortcutPill(
                id: "delete",
                key: "⌫",
                label: tr("Удалить", "Delete"),
                action: {
                    engine.triggerShortcutHighlight("delete")
                    onDeleteSelected()
                }
            )
            shortcutPill(
                id: "shift",
                key: "⇧ Shift",
                label: tr("Ровный круг / линия", "Perfect circle / line"),
                action: {
                    engine.triggerShortcutHighlight("shift")
                }
            )
            shortcutPill(
                id: "zoom",
                key: "⌘ +/-",
                label: tr("Масштаб", "Zoom"),
                action: {
                    engine.triggerShortcutHighlight("zoom")
                    onStepZoom()
                }
            )
            shortcutPill(
                id: "escape",
                key: "Esc",
                label: tr("Закрыть", "Close"),
                action: {
                    engine.triggerShortcutHighlight("escape")
                    onEscape()
                }
            )

            Spacer(minLength: 10)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            ZStack {
                theme.cardColor.opacity(theme.usesLiquidGlass ? 0.88 : 0.98)
                if theme.usesLiquidGlass {
                    LinearGradient(
                        colors: [
                            Color.clear,
                            theme.accentColor.opacity(0.06 * (0.25 + windowOpacity * 0.75)),
                            Color.white.opacity((theme.isLight ? 0.35 : 0.10) * (0.25 + windowOpacity * 0.75))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
            }
        )
    }

    private func shortcutPill(
        id: String,
        key: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let isHighlighted = engine.isShortcutHighlighted(id)
        let isDeleteKey = (id == "delete")
        let badgeTextColor: Color = isHighlighted ? Color.white : theme.primaryText
        let idleBadgeFill: Color = theme.isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.14)
        let badgeFillColor: Color = isHighlighted ? theme.accentColor : idleBadgeFill
        let idleBadgeBorder: Color = theme.primaryText.opacity(theme.isLight ? 0.18 : 0.16)
        let badgeBorderColor: Color = isHighlighted ? Color.white.opacity(0.85) : idleBadgeBorder
        let badgeBorderWidth: CGFloat = isHighlighted ? 1.2 : 0.8
        let badgeShadowColor: Color = isHighlighted ? theme.accentColor.opacity(0.55) : Color.clear
        let badgeShadowRadius: CGFloat = isHighlighted ? 4.0 : 0.0
        let badgeScale: CGFloat = isHighlighted ? 1.08 : 1.0

        return Button(action: action) {
            HStack(spacing: 5) {
                Group {
                    if isDeleteKey {
                        Image(systemName: "delete.left")
                            .font(.system(size: 13, weight: .bold))
                    } else {
                        Text(key)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 20, maxHeight: 20)
                .foregroundStyle(badgeTextColor)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(badgeFillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(badgeBorderColor, lineWidth: badgeBorderWidth)
                )
                .shadow(color: badgeShadowColor, radius: badgeShadowRadius, x: 0, y: 0)
                .scaleEffect(badgeScale)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHighlighted)

                Text(label)
                    .font(currentFont.font(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .lineLimit(1)
        }
        .buttonStyle(.plain)
    }
}
