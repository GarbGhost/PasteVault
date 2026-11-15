import XCTest
import AppKit
import SwiftUI
@testable import PasteVault

@MainActor
final class ScreenshotAnnotationTests: XCTestCase {

    func testStepCounterNumberingAndUndoRecalculation() {
        let engine = ScreenshotEditorEngine()
        XCTAssertEqual(engine.nextStepNumber, 1)

        // 1 -> 2 -> 3
        let step1 = engine.addStepPin(at: CGPoint(x: 40, y: 40))
        XCTAssertEqual(step1, 1)
        XCTAssertEqual(engine.nextStepNumber, 2)

        let step2 = engine.addStepPin(at: CGPoint(x: 100, y: 80))
        XCTAssertEqual(step2, 2)
        XCTAssertEqual(engine.nextStepNumber, 3)

        let step3 = engine.addStepPin(at: CGPoint(x: 180, y: 120))
        XCTAssertEqual(step3, 3)
        XCTAssertEqual(engine.nextStepNumber, 4)

        // Undo последнего шага (3) -> следующий номер снова должен быть 3
        engine.undo()
        XCTAssertEqual(engine.annotations.count, 2)
        XCTAssertEqual(engine.nextStepNumber, 3)

        // Повторное добавление шага должно дать 3
        let step3Again = engine.addStepPin(at: CGPoint(x: 200, y: 140))
        XCTAssertEqual(step3Again, 3)
        XCTAssertEqual(engine.nextStepNumber, 4)

        // Полная очистка сбрасывает счётчик на 1
        engine.clearAll()
        XCTAssertEqual(engine.annotations.count, 0)
        XCTAssertEqual(engine.nextStepNumber, 1)
    }

    func testAddingMovingAndUndoingAllLayerTypes() {
        let engine = ScreenshotEditorEngine()

        // 1. Arrow
        engine.addArrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 120, y: 80), color: .crimson, lineWidth: 4)
        XCTAssertEqual(engine.annotations.count, 1)

        // 2. Text + перемещение + обновление текста
        let textId = engine.addText("API Token", at: CGPoint(x: 60, y: 60), font: .jetBrainsMono, fontSize: 18, color: .amber)
        XCTAssertEqual(engine.annotations.count, 2)
        engine.moveAnnotation(id: textId, to: CGPoint(x: 90, y: 95))
        engine.updateText(id: textId, newText: "Secret Key")
        if case .text(let pos, let updatedText, let font, let size, _, _, _, _) = engine.annotations[1].payload {
            XCTAssertEqual(pos, CGPoint(x: 90, y: 95))
            XCTAssertEqual(updatedText, "Secret Key")
            XCTAssertEqual(font, .jetBrainsMono)
            XCTAssertEqual(size, 18)
        } else {
            XCTFail("Expected text annotation payload")
        }

        // 3. Shape
        engine.addShape(kind: .roundedRect, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 160, y: 110), color: .emerald, lineWidth: 6)
        XCTAssertEqual(engine.annotations.count, 3)

        // 4. Highlighter (Box & Freehand)
        engine.addBoxHighlighter(rect: CGRect(x: 30, y: 40, width: 140, height: 28), color: .sky)
        engine.addFreehandHighlighter(points: [CGPoint(x: 10, y: 15), CGPoint(x: 50, y: 15), CGPoint(x: 90, y: 18)], color: .purple, lineWidth: 4)
        XCTAssertEqual(engine.annotations.count, 5)

        // 5. Fine Pixelate (6px)
        engine.addPixelate(rect: CGRect(x: 40, y: 40, width: 100, height: 30), pixelScale: 6.0)
        XCTAssertEqual(engine.annotations.count, 6)

        // 6. Step Pin + перетаскивание маячка
        _ = engine.addStepPin(at: CGPoint(x: 150, y: 150), color: .crimson)
        XCTAssertEqual(engine.annotations.count, 7)
        let stepId = engine.annotations[6].id
        engine.moveAnnotation(id: stepId, to: CGPoint(x: 175, y: 165))
        if case .step(let num, let pos, _, _) = engine.annotations[6].payload {
            XCTAssertEqual(num, 1)
            XCTAssertEqual(pos, CGPoint(x: 175, y: 165))
        } else {
            XCTFail("Expected step annotation payload")
        }

        // Проверяем пошаговый Undo всех 7 элементов
        for expectedRemaining in (0...6).reversed() {
            engine.undo()
            XCTAssertEqual(engine.annotations.count, expectedRemaining)
        }
    }

    func testRenderAndSaveAnnotatedCopyPreservesOriginalScreenshotItem() {
        let monitor = ClipboardMonitor.shared
        let previousItems = monitor.items
        defer {
            monitor.items = previousItems
        }

        let baseImage = ClipboardMonitor.generateSyntheticScreenshotImage(label: "Original Screenshot")
        guard let tiffData = baseImage.tiffRepresentation else {
            XCTFail("Failed to generate base screenshot TIFF")
            return
        }

        let originalItem = ClipboardItemRow(
            id: "test-orig-screenshot-\(UUID().uuidString)",
            rowid: 100,
            contentType: .image,
            textPreview: "[Скриншот 320×180 пкс] #OCR",
            contentHash: "orig-hash-\(UUID().uuidString)",
            sourceBundleId: "com.apple.screencaptureui",
            sourceAppName: "Снимок экрана",
            isSensitive: false,
            secretKind: nil,
            isPinned: false,
            createdAt: 1000,
            expiresAt: nil,
            ocrText: "Original Screenshot OCR",
            rawImageData: tiffData,
            fileURLPath: nil,
            useCount: 0
        )
        monitor.items.insert(originalItem, at: 0)

        let countBefore = monitor.items.count
        let engine = ScreenshotEditorEngine()
        engine.addArrow(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 160, y: 90), color: .crimson, lineWidth: 4)
        _ = engine.addStepPin(at: CGPoint(x: 160, y: 90), color: .crimson)
        engine.addBoxHighlighter(rect: CGRect(x: 30, y: 50, width: 120, height: 24), color: .amber)
        engine.addPixelate(rect: CGRect(x: 40, y: 80, width: 90, height: 25), pixelScale: 6.0)

        guard let renderedImage = engine.renderAnnotatedImage(baseImage: baseImage, canvasSize: baseImage.size) else {
            XCTFail("Expected non-nil rendered annotated image")
            return
        }

        let newCopyItem = monitor.saveAnnotatedCopy(from: originalItem, annotatedImage: renderedImage)

        // 1. В истории стало ровно на 1 элемент больше
        XCTAssertEqual(monitor.items.count, countBefore + 1)

        // 2. Новая копия находится на 1-м месте (индекс 0)
        XCTAssertEqual(monitor.items.first?.id, newCopyItem.id)
        XCTAssertNotEqual(newCopyItem.id, originalItem.id)

        // 3. Оригинальный элемент скриншота остался в истории полностью неизменным
        guard let preservedOriginal = monitor.items.first(where: { $0.id == originalItem.id }) else {
            XCTFail("Original screenshot item must remain in history untouched")
            return
        }
        XCTAssertEqual(preservedOriginal.contentHash, originalItem.contentHash)
        XCTAssertEqual(preservedOriginal.textPreview, originalItem.textPreview)
    }

    func testDefaultFontIsInterAndToolSubmenus() {
        let engine = ScreenshotEditorEngine()
        XCTAssertEqual(engine.selectedFont, .inter, "Default font in ScreenshotEditorEngine must always be Inter")
        XCTAssertTrue(ScreenshotTool.arrow.hasSubmenu, "Arrow tool must have submenu for stroke width")
        XCTAssertTrue(ScreenshotTool.text.hasSubmenu, "Text tool must have submenu for size and collapsible font")
        XCTAssertTrue(ScreenshotTool.shape.hasSubmenu, "Shape tool must have submenu")
        XCTAssertTrue(ScreenshotTool.highlighter.hasSubmenu, "Highlighter tool must have submenu for mode and stroke width")
        XCTAssertFalse(ScreenshotTool.step.hasSubmenu)
        XCTAssertFalse(ScreenshotTool.pixelate.hasSubmenu)
    }

    func testZoomCropAt200PercentSavesCroppedFragmentAndUpdatesDimensions() {
        let monitor = ClipboardMonitor.shared
        let previousItems = monitor.items
        defer {
            monitor.items = previousItems
        }

        // Создаём тестовый скриншот 320×180: внешняя рамка чисто красная, а центральный фрагмент 160×90 — чисто зелёный
        let fullSize = NSSize(width: 320, height: 180)
        let testImage = NSImage(size: fullSize)
        testImage.lockFocus()
        NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: fullSize)).fill()
        NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 80, y: 45, width: 160, height: 90)).fill()
        testImage.unlockFocus()

        guard let tiffData = testImage.tiffRepresentation else {
            XCTFail("Failed to get TIFF data for zoom test image")
            return
        }

        let originalItem = ClipboardItemRow(
            id: "test-zoom-orig-\(UUID().uuidString)",
            rowid: 200,
            contentType: .image,
            textPreview: "[Скриншот 320×180 пкс] #OCR",
            contentHash: "zoom-orig-hash-\(UUID().uuidString)",
            sourceBundleId: "com.apple.screencaptureui",
            sourceAppName: "Снимок экрана",
            isSensitive: false,
            secretKind: nil,
            isPinned: false,
            createdAt: 2000,
            expiresAt: nil,
            ocrText: nil,
            rawImageData: tiffData,
            fileURLPath: nil,
            useCount: 0
        )
        monitor.items.insert(originalItem, at: 0)

        let engine = ScreenshotEditorEngine()
        // Рендерим с увеличением масштаба 200% (zoomScale = 2.0) даже без нарисованных стрелок
        guard let zoomedImage = engine.renderAnnotatedImage(
            baseImage: testImage,
            canvasSize: fullSize,
            zoomScale: 2.0,
            panOffset: .zero
        ) else {
            XCTFail("Expected non-nil zoomed rendered image")
            return
        }

        // 1. Размеры сохранённого фрагмента должны составлять ровно половину (160×90), а не полный кадр 320×180
        XCTAssertEqual(Int(zoomedImage.size.width), 160)
        XCTAssertEqual(Int(zoomedImage.size.height), 90)

        // 2. Проверяем по пикселю в углу сохранённого кадра, что внешняя красная рамка отрезана, и внутри именно центральный зелёный фрагмент
        guard let cgCropped = zoomedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            XCTFail("Expected CGImage from zoomed annotated image")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgCropped)
        guard let cornerColor = rep.colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB) else {
            XCTFail("Expected sRGB pixel color at (10, 10)")
            return
        }
        XCTAssertGreaterThan(cornerColor.greenComponent, 0.7, "Cropped image corner must be the green central region, not the red outer border")
        XCTAssertLessThan(cornerColor.redComponent, 0.3, "Red outer border must be cropped out at 200% zoom")

        // 3. В подписи новой карточки в буфере обмена указаны новые пиксельные размеры 160×90
        let savedCopy = monitor.saveAnnotatedCopy(from: originalItem, annotatedImage: zoomedImage)
        XCTAssertTrue(savedCopy.textPreview.contains("160×90"), "Expected new card preview to contain 160×90, got: \(savedCopy.textPreview)")
    }

    func testShiftConstraintProducesPerfectCircleAndSquareAndSnapsLineToHorizontalVertical45() {
        let start = CGPoint(x: 50, y: 50)

        // 1. Круг/овал (.ellipse) с зажатым Shift (isShiftPressed == true) -> ширина строго равна высоте (width == height)
        let rawEllipseEnd = CGPoint(x: 170, y: 110) // dx = 120, dy = 60
        let adjustedCircleEnd = ScreenshotEditorEngine.adjustedDragEndPoint(
            start: start,
            rawEnd: rawEllipseEnd,
            tool: .shape,
            shapeKind: .ellipse,
            isShiftPressed: true
        )
        let circleWidth = abs(adjustedCircleEnd.x - start.x)
        let circleHeight = abs(adjustedCircleEnd.y - start.y)
        XCTAssertEqual(circleWidth, circleHeight, accuracy: 0.001, "With Shift pressed, ellipse width must strictly equal height (perfect circle)")
        XCTAssertEqual(circleWidth, 120, accuracy: 0.001)

        // 2. Прямоугольник (.roundedRect) в отрицательный квадрант с зажатым Shift -> идеальный квадрат
        let rawSquareEnd = CGPoint(x: 20, y: -30) // dx = -30, dy = -80
        let adjustedSquareEnd = ScreenshotEditorEngine.adjustedDragEndPoint(
            start: start,
            rawEnd: rawSquareEnd,
            tool: .shape,
            shapeKind: .roundedRect,
            isShiftPressed: true
        )
        XCTAssertEqual(abs(adjustedSquareEnd.x - start.x), abs(adjustedSquareEnd.y - start.y), accuracy: 0.001)
        XCTAssertEqual(adjustedSquareEnd.x, 50 - 80, accuracy: 0.001)
        XCTAssertEqual(adjustedSquareEnd.y, 50 - 80, accuracy: 0.001)

        // 3. Прямая линия (.line) с небольшим отклонением по Y и зажатым Shift -> примагничивается строго горизонтально (end.y == start.y)
        let rawLineEnd = CGPoint(x: 210, y: 62) // dx = 160, dy = 12 (угол ~4.3°)
        let adjustedLineEnd = ScreenshotEditorEngine.adjustedDragEndPoint(
            start: start,
            rawEnd: rawLineEnd,
            tool: .shape,
            shapeKind: .line,
            isShiftPressed: true
        )
        XCTAssertEqual(adjustedLineEnd.y, start.y, accuracy: 0.001, "With Shift pressed and small Y offset, line must snap strictly horizontally (end.y == start.y)")
        XCTAssertEqual(adjustedLineEnd.x, rawLineEnd.x, accuracy: 0.001)

        // 4. Стрелка (.arrow) с небольшим отклонением по X и зажатым Shift -> примагничивается строго вертикально (end.x == start.x)
        let rawVerticalArrowEnd = CGPoint(x: 56, y: 190) // dx = 6, dy = 140
        let adjustedVerticalArrowEnd = ScreenshotEditorEngine.adjustedDragEndPoint(
            start: start,
            rawEnd: rawVerticalArrowEnd,
            tool: .arrow,
            isShiftPressed: true
        )
        XCTAssertEqual(adjustedVerticalArrowEnd.x, start.x, accuracy: 0.001, "With Shift pressed and small X offset, arrow must snap strictly vertically (end.x == start.x)")
        XCTAssertEqual(adjustedVerticalArrowEnd.y, rawVerticalArrowEnd.y, accuracy: 0.001)

        // 5. Линия под углом около 45° с зажатым Shift -> примагничивается ровно под 45° (|dx| == |dy|)
        let rawDiagonalEnd = CGPoint(x: 150, y: 140) // dx = 100, dy = 90
        let adjustedDiagonalEnd = ScreenshotEditorEngine.adjustedDragEndPoint(
            start: start,
            rawEnd: rawDiagonalEnd,
            tool: .shape,
            shapeKind: .line,
            isShiftPressed: true
        )
        XCTAssertEqual(abs(adjustedDiagonalEnd.x - start.x), abs(adjustedDiagonalEnd.y - start.y), accuracy: 0.001)
    }

    func testTranslateAnnotationAndResizeHandle() {
        let engine = ScreenshotEditorEngine()

        // 1. Создаём стрелку от (10, 20) до (80, 100) — после рисования она НЕ выделяется автоматически
        let arrowId = engine.addArrow(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 80, y: 100), color: .crimson, lineWidth: 4)
        XCTAssertNil(engine.selectedAnnotationId)

        // Перемещаем тело стрелки на delta (+15, -10)
        engine.translateAnnotation(id: arrowId, by: CGPoint(x: 15, y: -10))
        if case .arrow(let start, let end, _, _, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(start, CGPoint(x: 25, y: 10))
            XCTAssertEqual(end, CGPoint(x: 95, y: 90))
        } else {
            XCTFail("Expected arrow payload")
        }

        // Изменяем ручку .end до (130, 140)
        engine.updateAnnotationHandle(id: arrowId, handle: .end, to: CGPoint(x: 130, y: 140), isShiftPressed: false)
        if case .arrow(let start, let end, _, _, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(start, CGPoint(x: 25, y: 10))
            XCTAssertEqual(end, CGPoint(x: 130, y: 140))
        } else {
            XCTFail("Expected arrow payload")
        }

        // 2. Создаём прямоугольник и изменяем правый нижний угол .bottomRight
        let shapeId = engine.addShape(kind: .roundedRect, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 100, y: 80))
        engine.updateAnnotationHandle(id: shapeId, handle: .bottomRight, to: CGPoint(x: 150, y: 120), isShiftPressed: false)
        if case .shape(let kind, let start, let end, _, _) = engine.annotations[1].payload {
            XCTAssertEqual(kind, .roundedRect)
            XCTAssertEqual(start, CGPoint(x: 30, y: 30))
            XCTAssertEqual(end, CGPoint(x: 150, y: 120))
        } else {
            XCTFail("Expected shape payload")
        }
    }

    func testStepPinPointerAngleUpdateAndShiftSnapping() {
        let engine = ScreenshotEditorEngine()

        // Создаём маячок шага (по умолчанию угол = .pi / 4.0 = 45°)
        _ = engine.addStepPin(at: CGPoint(x: 100, y: 100), color: .amber)
        let stepId = engine.annotations[0].id
        if case .step(let num, let pos, let color, let angle) = engine.annotations[0].payload {
            XCTAssertEqual(num, 1)
            XCTAssertEqual(pos, CGPoint(x: 100, y: 100))
            XCTAssertEqual(color, .amber)
            XCTAssertEqual(angle, Double.pi / 4.0, accuracy: 0.001)
        } else {
            XCTFail("Expected step pin payload")
        }

        // Поворачиваем носик вниз на угол 90° (Double.pi / 2.0)
        engine.updateStepPointerAngle(id: stepId, to: Double.pi / 2.0)
        if case .step(_, _, _, let updatedAngle) = engine.annotations[0].payload {
            XCTAssertEqual(updatedAngle, Double.pi / 2.0, accuracy: 0.001)
        } else {
            XCTFail("Expected updated angle")
        }

        // Проверяем работу ручки .stepPointer с примагничиванием по Shift (шаг 45° = .pi / 4)
        // Center маячка = (100, 100)
        // Тянем ручку влево-вверх: dx = -40, dy = -35 -> угол около -138°, с зажатым Shift должен примагнититься к -135° (-3*pi/4)
        let handlePt = CGPoint(x: 100 - 40, y: 100 - 35)
        engine.updateAnnotationHandle(id: stepId, handle: .stepPointer, to: handlePt, isShiftPressed: true)
        if case .step(let num, _, _, let snappedAngle) = engine.annotations[0].payload {
            XCTAssertEqual(num, 1, "Step number must never change during rotation")
            let expectedSnap = -3.0 * Double.pi / 4.0
            XCTAssertEqual(snappedAngle, expectedSnap, accuracy: 0.05)
        } else {
            XCTFail("Expected snapped angle")
        }

        // Проверяем отмену поворота через Undo
        engine.undo()
        if case .step(_, _, _, let revertedAngle) = engine.annotations[0].payload {
            XCTAssertEqual(revertedAngle, Double.pi / 4.0, accuracy: 0.001)
        } else {
            XCTFail("Expected step pin payload after undo")
        }
    }

    func testDeleteSelectedAnnotationAndUndo() {
        let engine = ScreenshotEditorEngine()

        let id1 = engine.addArrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50))
        let id2 = engine.addShape(kind: .ellipse, from: CGPoint(x: 60, y: 60), to: CGPoint(x: 120, y: 120))
        _ = engine.addStepPin(at: CGPoint(x: 140, y: 140))
        XCTAssertEqual(engine.annotations.count, 3)

        // Выделяем эллипс (id2) и удаляем его клавишей Backspace / deleteSelectedAnnotation
        engine.selectedAnnotationId = id2
        engine.deleteSelectedAnnotation()

        XCTAssertEqual(engine.annotations.count, 2)
        XCTAssertNil(engine.selectedAnnotationId, "After deletion, selectedAnnotationId must be nil")
        XCTAssertFalse(engine.annotations.contains(where: { $0.id == id2 }))
        XCTAssertTrue(engine.annotations.contains(where: { $0.id == id1 }))

        // Нажимаем Undo (⌘Z) — эллипс должен восстановиться
        engine.undo()
        XCTAssertEqual(engine.annotations.count, 3)
        XCTAssertTrue(engine.annotations.contains(where: { $0.id == id2 }))
    }

    func testLiveColorAndStrokeWidthUpdateOnSelectedItem() {
        let engine = ScreenshotEditorEngine()

        // Создаём стрелку цвета Crimson с толщиной 4
        let arrowId = engine.addArrow(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 50), color: .crimson, lineWidth: 4)
        engine.selectedAnnotationId = arrowId

        // Меняем цвет на лету на Emerald
        engine.updateSelectedAnnotationColor(.emerald)
        if case .arrow(_, _, let color, let width, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(color, .emerald)
            XCTAssertEqual(width, 4)
        } else {
            XCTFail("Expected arrow payload")
        }

        // Меняем толщину линии на лету на 12 pt
        engine.updateSelectedAnnotationStrokeWidth(12)
        if case .arrow(_, _, let color, let width, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(color, .emerald)
            XCTAssertEqual(width, 12)
        } else {
            XCTFail("Expected arrow payload")
        }

        // Проверяем отмену изменений через Undo
        engine.undo() // отменяет толщину 12 -> 4
        if case .arrow(_, _, _, let width, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(width, 4)
        } else {
            XCTFail("Expected arrow payload after width undo")
        }
        engine.undo() // отменяет цвет Emerald -> Crimson
        if case .arrow(_, _, let color, _, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(color, .crimson)
        } else {
            XCTFail("Expected arrow payload after color undo")
        }
    }

    func testHandToolAndHitTesting() {
        let engine = ScreenshotEditorEngine()

        // 1. Стрелка
        let arrowId = engine.addArrow(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 100, y: 20), color: .crimson, lineWidth: 6)
        let hitArrow = ScreenshotEditorEngine.hitTestBody(point: CGPoint(x: 60, y: 22), in: engine.annotations)
        XCTAssertEqual(hitArrow, arrowId)

        // Проверяем ручки стрелки (.start и .end)
        let handleStart = ScreenshotEditorEngine.hitTestHandle(point: CGPoint(x: 22, y: 21), in: engine.annotations[0])
        XCTAssertEqual(handleStart, .start)
        let handleEnd = ScreenshotEditorEngine.hitTestHandle(point: CGPoint(x: 99, y: 19), in: engine.annotations[0])
        XCTAssertEqual(handleEnd, .end)

        // 2. Шаг-маячок (center = 150, 150)
        _ = engine.addStepPin(at: CGPoint(x: 150, y: 150), color: .sky, pointerAngle: .pi / 4.0)
        let stepId = engine.annotations[1].id
        let hitStep = ScreenshotEditorEngine.hitTestBody(point: CGPoint(x: 150, y: 150), in: engine.annotations)
        XCTAssertEqual(hitStep, stepId)

        // Ручка поворота маячка находится на расстоянии 28pt под углом 45°
        let center = CGPoint(x: 150, y: 150)
        let rotationHandlePt = CGPoint(x: center.x + cos(.pi / 4.0) * 28.0, y: center.y + sin(.pi / 4.0) * 28.0)
        let handleStep = ScreenshotEditorEngine.hitTestHandle(point: rotationHandlePt, in: engine.annotations[1])
        XCTAssertEqual(handleStep, .stepPointer)

        // 3. Клик в пустое место возвращает nil
        let hitEmpty = ScreenshotEditorEngine.hitTestBody(point: CGPoint(x: 400, y: 400), in: engine.annotations)
        XCTAssertNil(hitEmpty)
    }

    func testVisibleCropRectCalculationWithZoomAndPanOffset() {
        let canvasSize = CGSize(width: 800, height: 600)
        let zoomScale: CGFloat = 2.0

        // 1. При panOffset == .zero вырезается строго центральный сектор 400×300 (origin = 200, 150)
        let centerRect = ScreenshotEditorEngine.visibleCropRect(in: canvasSize, zoomScale: zoomScale, panOffset: .zero)
        XCTAssertEqual(centerRect.width, 400, accuracy: 0.001)
        XCTAssertEqual(centerRect.height, 300, accuracy: 0.001)
        XCTAssertEqual(centerRect.minX, 200, accuracy: 0.001)
        XCTAssertEqual(centerRect.minY, 150, accuracy: 0.001)

        // 2. При сдвиге вправо (panOffset.width = 200) в кадр смещается левая часть скриншота (minX уменьшается)
        let pannedLeftContentRect = ScreenshotEditorEngine.visibleCropRect(
            in: canvasSize,
            zoomScale: zoomScale,
            panOffset: CGSize(width: 200, height: 0)
        )
        XCTAssertEqual(pannedLeftContentRect.minX, 100, accuracy: 0.001)
        XCTAssertEqual(pannedLeftContentRect.width, 400, accuracy: 0.001)

        // 3. При максимальном сдвиге влево (panOffset.width = -400) вырезается правый край скриншота (maxX == 800)
        let pannedRightContentRect = ScreenshotEditorEngine.visibleCropRect(
            in: canvasSize,
            zoomScale: zoomScale,
            panOffset: CGSize(width: -400, height: 0)
        )
        XCTAssertEqual(pannedRightContentRect.minX, 400, accuracy: 0.001)
        XCTAssertEqual(pannedRightContentRect.maxX, 800, accuracy: 0.001)

        // 4. Ограничение (clamp) от вылета за границы изображения в пустоту при огромном смещении
        let extremeRect = ScreenshotEditorEngine.visibleCropRect(
            in: canvasSize,
            zoomScale: zoomScale,
            panOffset: CGSize(width: 9999, height: 9999)
        )
        XCTAssertEqual(extremeRect.minX, 0, accuracy: 0.001, "Origin must clamp to 0 and not exceed image bounds")
        XCTAssertEqual(extremeRect.minY, 0, accuracy: 0.001)
    }

    func testHitTestInsideShapesInHandMode() {
        let engine = ScreenshotEditorEngine()

        // 1. Круг / Овал от (50, 50) до (150, 150): центр в (100, 100)
        let ellipseId = engine.addShape(kind: .ellipse, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 150))
        let hitEllipseCenter = ScreenshotEditorEngine.hitTestBody(point: CGPoint(x: 100, y: 100), in: engine.annotations)
        XCTAssertEqual(hitEllipseCenter, ellipseId, "Click inside the center of an ellipse must hit-test the shape")

        let hitEllipseInner = ScreenshotEditorEngine.hitTestBody(point: CGPoint(x: 80, y: 90), in: engine.annotations)
        XCTAssertEqual(hitEllipseInner, ellipseId, "Click inside the area of an ellipse must hit-test the shape")

        // 2. Скруглённый прямоугольник от (200, 50) до (300, 150): центр в (250, 100)
        let roundedRectId = engine.addShape(kind: .roundedRect, from: CGPoint(x: 200, y: 50), to: CGPoint(x: 300, y: 150))
        let hitRoundedCenter = ScreenshotEditorEngine.hitTestBody(point: CGPoint(x: 250, y: 100), in: engine.annotations)
        XCTAssertEqual(hitRoundedCenter, roundedRectId, "Click inside rounded rectangle body must hit-test the shape")

        // 3. Обычный прямоугольник от (350, 50) до (450, 150): центр в (400, 100)
        let rectId = engine.addShape(kind: .rect, from: CGPoint(x: 350, y: 50), to: CGPoint(x: 450, y: 150))
        let hitRectCenter = ScreenshotEditorEngine.hitTestBody(point: CGPoint(x: 400, y: 100), in: engine.annotations)
        XCTAssertEqual(hitRectCenter, rectId, "Click inside normal rectangle body must hit-test the shape")
    }

    func testNoAutoSelectionAfterDrawingPreventsMutatingPreviousElements() {
        let engine = ScreenshotEditorEngine()

        // 1. Рисуем первую стрелку толщиной 4 pt и цветом Crimson
        engine.selectedStrokeWidth = 4
        engine.selectedColor = .crimson
        let firstArrowId = engine.addArrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 50))
        XCTAssertNil(engine.selectedAnnotationId, "Newly drawn arrow must NOT remain auto-selected")

        // 2. Меняем толщину на 12 pt и цвет на Emerald для СЛЕДУЮЩЕЙ стрелки
        engine.updateSelectedAnnotationStrokeWidth(12)
        engine.updateSelectedAnnotationColor(.emerald)

        // Первая стрелка обязана сохранить свою исходную толщину 4 pt и цвет Crimson!
        if case .arrow(_, _, let firstColor, let firstWidth, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(firstColor, .crimson, "Previously drawn arrow color must not mutate when changing tool color")
            XCTAssertEqual(firstWidth, 4, "Previously drawn arrow stroke width must not mutate when changing tool stroke width")
        } else {
            XCTFail("Expected arrow payload")
        }

        // 3. Рисуем вторую стрелку — она создаётся уже с новыми настройками (12 pt, Emerald)
        _ = engine.addArrow(from: CGPoint(x: 20, y: 80), to: CGPoint(x: 140, y: 120))
        if case .arrow(_, _, let secondColor, let secondWidth, _, _) = engine.annotations[1].payload {
            XCTAssertEqual(secondColor, .emerald)
            XCTAssertEqual(secondWidth, 12)
        } else {
            XCTFail("Expected second arrow payload")
        }

        // 4. Только если явно выделить первую стрелку инструментом «✋ Рука» — смена цвета изменит её
        engine.selectedAnnotationId = firstArrowId
        engine.updateSelectedAnnotationColor(.sky)
        if case .arrow(_, _, let updatedFirstColor, _, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(updatedFirstColor, .sky)
        }

        // 5. Переключение на любой инструмент рисования сбрасывает выделение
        engine.selectTool(.shape)
        XCTAssertNil(engine.selectedAnnotationId)
    }

    func testEditingExistingTextPreservesAndSyncsFontAndSize() {
        let engine = ScreenshotEditorEngine()

        // 1. Создаём первую надпись шрифтом JetBrains Mono 18pt и завершаем ввод
        engine.selectedFont = .jetBrainsMono
        engine.selectedFontSize = 18
        engine.selectedColor = .amber
        let text1Id = engine.addText("First Note", at: CGPoint(x: 60, y: 60))
        engine.beginEditingTextAnnotation(id: text1Id)
        engine.commitActiveTextEditing()
        XCTAssertNil(engine.editingTextAnnotationId)
        XCTAssertNil(engine.selectedAnnotationId)

        // 2. Меняем шрифт в меню Aa на Tektur 24pt и цвет Sky для второй надписи
        engine.updateSelectedAnnotationFont(.tektur)
        engine.updateSelectedAnnotationFontSize(24)
        engine.updateSelectedAnnotationColor(.sky)

        // Первая надпись НЕ должна измениться!
        if case .text(_, let t1, let f1, let s1, let c1, _, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(t1, "First Note")
            XCTAssertEqual(f1, .jetBrainsMono, "First text font must remain JetBrains Mono after changing tool font for next text")
            XCTAssertEqual(s1, 18, "First text font size must remain 18pt")
            XCTAssertEqual(c1, .amber)
        } else {
            XCTFail("Expected first text payload")
        }

        // Создаём вторую надпись с новыми параметрами (Tektur 24pt, Sky)
        let text2Id = engine.addText("Second Note", at: CGPoint(x: 180, y: 140))
        engine.beginEditingTextAnnotation(id: text2Id)
        engine.commitActiveTextEditing()

        // 3. Кликаем по первой надписи для редактирования — её собственные шрифт (JetBrains Mono), размер (18) и цвет (Amber) синхронизируются с панелью
        engine.beginEditingTextAnnotation(id: text1Id)
        XCTAssertEqual(engine.editingTextAnnotationId, text1Id)
        XCTAssertEqual(engine.selectedFont, .jetBrainsMono)
        XCTAssertEqual(engine.selectedFontSize, 18)
        XCTAssertEqual(engine.selectedColor, .amber)

        // Изменяем текст первой надписи и завершаем редактирование
        engine.updateText(id: text1Id, newText: "Edited First Note")
        engine.commitActiveTextEditing()

        if case .text(_, let updatedText1, let font1After, let size1After, let color1After, _, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(updatedText1, "Edited First Note")
            XCTAssertEqual(font1After, .jetBrainsMono)
            XCTAssertEqual(size1After, 18)
            XCTAssertEqual(color1After, .amber)
        } else {
            XCTFail("Expected updated first text payload")
        }

        // Вторая надпись по-прежнему осталась Tektur 24pt Sky
        if case .text(_, let text2After, let font2After, let size2After, let color2After, _, _, _) = engine.annotations[1].payload {
            XCTAssertEqual(text2After, "Second Note")
            XCTAssertEqual(font2After, .tektur)
            XCTAssertEqual(size2After, 24)
            XCTAssertEqual(color2After, .sky)
        } else {
            XCTFail("Expected second text payload")
        }
    }

    func testCalloutAnchorPointTopBottomLeftRightEdges() {
        // Прямоугольник текста от (100, 100) с шириной 120 и высотой 40 -> center = (160, 120)
        // minX = 100, maxX = 220, minY = 100, maxY = 140
        let textRect = CGRect(x: 100, y: 100, width: 120, height: 40)

        // 1. Цель строго сверху (160, 20) -> выходит из верхней грани (y == minY == 100)
        let topAnchor = ScreenshotEditorEngine.calloutAnchorPoint(for: textRect, target: CGPoint(x: 160, y: 20))
        XCTAssertEqual(topAnchor.x, 160, accuracy: 0.001)
        XCTAssertEqual(topAnchor.y, 100, accuracy: 0.001)

        // 2. Цель строго снизу (160, 250) -> выходит из нижней грани (y == maxY == 140)
        let bottomAnchor = ScreenshotEditorEngine.calloutAnchorPoint(for: textRect, target: CGPoint(x: 160, y: 250))
        XCTAssertEqual(bottomAnchor.x, 160, accuracy: 0.001)
        XCTAssertEqual(bottomAnchor.y, 140, accuracy: 0.001)

        // 3. Цель строго слева (20, 120) -> выходит из левой грани (x == minX == 100)
        let leftAnchor = ScreenshotEditorEngine.calloutAnchorPoint(for: textRect, target: CGPoint(x: 20, y: 120))
        XCTAssertEqual(leftAnchor.x, 100, accuracy: 0.001)
        XCTAssertEqual(leftAnchor.y, 120, accuracy: 0.001)

        // 4. Цель строго справа (320, 120) -> выходит из правой грани (x == maxX == 220)
        let rightAnchor = ScreenshotEditorEngine.calloutAnchorPoint(for: textRect, target: CGPoint(x: 320, y: 120))
        XCTAssertEqual(rightAnchor.x, 220, accuracy: 0.001)
        XCTAssertEqual(rightAnchor.y, 120, accuracy: 0.001)
    }

    func testMovingTextAnnotationPreservesCalloutTargetAndUpdatesAnchor() {
        let engine = ScreenshotEditorEngine()

        // Создаём текст в точке (100, 200) и вытягиваем стрелку к точке (300, 200) справа
        let pinnedTarget = CGPoint(x: 300, y: 200)
        let textId = engine.addText("Target Here", at: CGPoint(x: 100, y: 200), fontSize: 16, color: .sky)
        engine.updateAnnotationHandle(id: textId, handle: .textCalloutPull, to: pinnedTarget, isShiftPressed: false)

        if case .text(let posBefore, let text, _, let fontSize, _, let targetBefore, _, let maxWBefore) = engine.annotations[0].payload {
            XCTAssertEqual(posBefore, CGPoint(x: 100, y: 200))
            XCTAssertEqual(targetBefore, pinnedTarget)

            // До перемещения текста цель справа -> стрелка выходит из правой грани (anchor.x == rectBefore.maxX)
            let rectBefore = ScreenshotEditorEngine.textBoundingRect(position: posBefore, text: text, fontSize: fontSize, maxWidth: maxWBefore)
            let anchorBefore = ScreenshotEditorEngine.calloutAnchorPoint(for: rectBefore, target: pinnedTarget)
            XCTAssertEqual(anchorBefore.x, rectBefore.maxX, accuracy: 0.001)
        } else {
            XCTFail("Expected text payload with calloutTarget")
        }

        // Перемещаем текст вправо за целевую точку: на (450, 200) через translateAnnotation
        engine.translateAnnotation(id: textId, by: CGPoint(x: 350, y: 0))

        if case .text(let posAfter, let text, _, let fontSize, _, let targetAfter, _, let maxWAfter) = engine.annotations[0].payload {
            XCTAssertEqual(posAfter, CGPoint(x: 450, y: 200), "Text position must move to (450, 200)")
            XCTAssertEqual(targetAfter, pinnedTarget, "calloutTarget must remain pinned at (300, 200) when text moves")

            // Теперь текст находится правее цели (300, 200) -> хвост стрелки автоматически переключился на левую грань!
            let rectAfter = ScreenshotEditorEngine.textBoundingRect(position: posAfter, text: text, fontSize: fontSize, maxWidth: maxWAfter)
            let anchorAfter = ScreenshotEditorEngine.calloutAnchorPoint(for: rectAfter, target: pinnedTarget)
            XCTAssertEqual(anchorAfter.x, rectAfter.minX, accuracy: 0.001)
        } else {
            XCTFail("Expected text payload after translation")
        }
    }

    func testDraggingCalloutTargetInsideTextRectRetractsArrowToNil() {
        let engine = ScreenshotEditorEngine()
        let textPos = CGPoint(x: 200, y: 200)
        let textId = engine.addText("Retract Me", at: textPos, fontSize: 16, color: .crimson)

        // 1. Вытягиваем стрелку наружу к (360, 260)
        engine.updateAnnotationHandle(id: textId, handle: .textCalloutPull, to: CGPoint(x: 360, y: 260), isShiftPressed: false)
        engine.finalizeTextCalloutDrag(id: textId)
        if case .text(_, _, _, _, _, let activeTarget, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(activeTarget, CGPoint(x: 360, y: 260))
        } else {
            XCTFail("Expected active calloutTarget")
        }

        // 2. Перетаскиваем остриё стрелки обратно внутрь рамки текста (205, 202) и завершаем жест
        engine.updateAnnotationHandle(id: textId, handle: .textCalloutTip, to: CGPoint(x: 205, y: 202), isShiftPressed: false)
        engine.finalizeTextCalloutDrag(id: textId)
        if case .text(_, _, _, _, _, let retractedTarget, _, _) = engine.annotations[0].payload {
            XCTAssertNil(retractedTarget, "Dragging callout tip inside text bounding rect must retract calloutTarget to nil")
        } else {
            XCTFail("Expected text payload")
        }
    }

    func testMenuBarDefaultRegistrationOnCleanUserDefaultsSuite() {
        let suiteName = "com.pastevault.test.freshmac.\(UUID().uuidString)"
        guard let cleanDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create clean UserDefaults suite")
            return
        }
        defer {
            cleanDefaults.removePersistentDomain(forName: suiteName)
        }

        // До регистрации ключи отсутствуют
        XCTAssertNil(cleanDefaults.object(forKey: "showMenuBarIcon"))

        // Регистрируем дефолты для чистого Mac
        AppDelegate.registerMenuBarDefaults(in: cleanDefaults)

        XCTAssertTrue(cleanDefaults.bool(forKey: "showMenuBarIcon"), "Fresh Mac must default showMenuBarIcon to true")
        XCTAssertTrue(cleanDefaults.bool(forKey: "showInMenuBar"), "Fresh Mac must default showInMenuBar to true")
        XCTAssertTrue(cleanDefaults.bool(forKey: "NSStatusItem Visible Item-0"), "Fresh Mac must default NSStatusItem Visible Item-0 to true")
        XCTAssertTrue(cleanDefaults.bool(forKey: "NSStatusItem Visible PasteVaultStatusItem"), "Fresh Mac must default NSStatusItem Visible PasteVaultStatusItem to true")
    }

    func testUnifiedTextCalloutPathSingleClosedContourAndEdges() {
        let pillRect = CGRect(x: 100, y: 100, width: 120, height: 36)

        // 1. Без выдвинутой стрелки (calloutTarget == nil) контур ровно соответствует прямоугольнику текстового окна
        let basePath = ScreenshotEditorEngine.unifiedTextCalloutPath(pillRect: pillRect, cornerRadius: 7.0, calloutTarget: nil)
        let baseBounds = basePath.boundingRect
        XCTAssertEqual(baseBounds.minX, pillRect.minX, accuracy: 0.5)
        XCTAssertEqual(baseBounds.maxX, pillRect.maxX, accuracy: 0.5)
        XCTAssertEqual(baseBounds.minY, pillRect.minY, accuracy: 0.5)
        XCTAssertEqual(baseBounds.maxY, pillRect.maxY, accuracy: 0.5)

        // Вспомогательная проверка: контур после CGPath.union должен содержать ровно 1 move(to:) и 1 closeSubpath() (единый неразрывный контур без швов и преломлений углов)
        func assertSingleClosedSubpath(_ path: Path, requireCurves: Bool = false) {
            var moveCount = 0
            var closeCount = 0
            var curveCount = 0
            path.forEach { element in
                switch element {
                case .move: moveCount += 1
                case .closeSubpath: closeCount += 1
                case .quadCurve, .curve: curveCount += 1
                default: break
                }
            }
            XCTAssertEqual(moveCount, 1, "Unified text callout bubble + arrow via CGPath.union must be a single continuous subpath (1 move)")
            XCTAssertEqual(closeCount, 1, "Unified text callout bubble + arrow via CGPath.union must have exactly 1 closeSubpath")
            if requireCurves {
                XCTAssertGreaterThanOrEqual(curveCount, 4, "Unified text callout path must preserve smooth Bezier curves for corners and concave wedge")
            }
        }

        assertSingleClosedSubpath(basePath)

        // 2. Прямые стороны (0°, 90°, 180°, 270°)
        let rightTarget = CGPoint(x: 310, y: 118) // 0°
        let rightPath = ScreenshotEditorEngine.unifiedTextCalloutPath(pillRect: pillRect, cornerRadius: 7.0, calloutTarget: rightTarget)
        assertSingleClosedSubpath(rightPath, requireCurves: true)
        XCTAssertEqual(rightPath.boundingRect.maxX, rightTarget.x, accuracy: 0.5)
        XCTAssertEqual(rightPath.boundingRect.minX, pillRect.minX, accuracy: 0.5)

        let leftTarget = CGPoint(x: 25, y: 118) // 180°
        let leftPath = ScreenshotEditorEngine.unifiedTextCalloutPath(pillRect: pillRect, cornerRadius: 7.0, calloutTarget: leftTarget)
        assertSingleClosedSubpath(leftPath, requireCurves: true)
        XCTAssertEqual(leftPath.boundingRect.minX, leftTarget.x, accuracy: 0.5)
        XCTAssertEqual(leftPath.boundingRect.maxX, pillRect.maxX, accuracy: 0.5)

        let topTarget = CGPoint(x: 160, y: 20) // 270° (-90°)
        let topPath = ScreenshotEditorEngine.unifiedTextCalloutPath(pillRect: pillRect, cornerRadius: 7.0, calloutTarget: topTarget)
        assertSingleClosedSubpath(topPath, requireCurves: true)
        XCTAssertEqual(topPath.boundingRect.minY, topTarget.y, accuracy: 0.5)
        XCTAssertEqual(topPath.boundingRect.maxY, pillRect.maxY, accuracy: 0.5)

        let bottomTarget = CGPoint(x: 160, y: 230) // 90°
        let bottomPath = ScreenshotEditorEngine.unifiedTextCalloutPath(pillRect: pillRect, cornerRadius: 7.0, calloutTarget: bottomTarget)
        assertSingleClosedSubpath(bottomPath, requireCurves: true)
        XCTAssertEqual(bottomPath.boundingRect.maxY, bottomTarget.y, accuracy: 0.5)
        XCTAssertEqual(bottomPath.boundingRect.minY, pillRect.minY, accuracy: 0.5)

        // 3. Все 4 диагональных угла (45°, 135°, 225°, 315°) относительно центра плашки (160, 118)
        let center = CGPoint(x: pillRect.midX, y: pillRect.midY)
        let diagDist: CGFloat = 110.0

        // 45° (правый нижний угол)
        let corner45 = CGPoint(x: center.x + diagDist, y: center.y + diagDist)
        let path45 = ScreenshotEditorEngine.unifiedTextCalloutPath(pillRect: pillRect, cornerRadius: 7.0, calloutTarget: corner45)
        assertSingleClosedSubpath(path45, requireCurves: true)
        XCTAssertEqual(path45.boundingRect.maxX, corner45.x, accuracy: 0.5)
        XCTAssertEqual(path45.boundingRect.maxY, corner45.y, accuracy: 0.5)

        // 135° (левый нижний угол)
        let corner135 = CGPoint(x: center.x - diagDist, y: center.y + diagDist)
        let path135 = ScreenshotEditorEngine.unifiedTextCalloutPath(pillRect: pillRect, cornerRadius: 7.0, calloutTarget: corner135)
        assertSingleClosedSubpath(path135, requireCurves: true)
        XCTAssertEqual(path135.boundingRect.minX, corner135.x, accuracy: 0.5)
        XCTAssertEqual(path135.boundingRect.maxY, corner135.y, accuracy: 0.5)

        // 225° (левый верхний угол)
        let corner225 = CGPoint(x: center.x - diagDist, y: center.y - diagDist)
        let path225 = ScreenshotEditorEngine.unifiedTextCalloutPath(pillRect: pillRect, cornerRadius: 7.0, calloutTarget: corner225)
        assertSingleClosedSubpath(path225, requireCurves: true)
        XCTAssertEqual(path225.boundingRect.minX, corner225.x, accuracy: 0.5)
        XCTAssertEqual(path225.boundingRect.minY, corner225.y, accuracy: 0.5)

        // 315° (правый верхний угол)
        let corner315 = CGPoint(x: center.x + diagDist, y: center.y - diagDist)
        let path315 = ScreenshotEditorEngine.unifiedTextCalloutPath(pillRect: pillRect, cornerRadius: 7.0, calloutTarget: corner315)
        assertSingleClosedSubpath(path315, requireCurves: true)
        XCTAssertEqual(path315.boundingRect.maxX, corner315.x, accuracy: 0.5)
        XCTAssertEqual(path315.boundingRect.minY, corner315.y, accuracy: 0.5)
    }

    func testShortcutHighlightActivationAndShiftHoldState() {
        let engine = ScreenshotEditorEngine()
        XCTAssertNil(engine.activeShortcutID)
        XCTAssertFalse(engine.isShiftShortcutHeld)

        // 1. Нажатие горячей клавиши активирует подсветку соответствующего ID
        engine.triggerShortcutHighlight("hand", duration: 0)
        XCTAssertTrue(engine.isShortcutHighlighted("hand"))
        XCTAssertFalse(engine.isShortcutHighlighted("undo"))

        engine.triggerShortcutHighlight("delete", duration: 0)
        XCTAssertTrue(engine.isShortcutHighlighted("delete"))
        XCTAssertFalse(engine.isShortcutHighlighted("hand"))

        // 2. Удержание клавиши Shift включает постоянную подсветку "shift", а отпускание — выключает
        engine.setShiftShortcutHeld(true)
        XCTAssertTrue(engine.isShortcutHighlighted("shift"))
        engine.setShiftShortcutHeld(false)
        XCTAssertFalse(engine.isShortcutHighlighted("shift"))
    }

    func testMultilineTextBoundingRectAndWidthResizeHandles() {
        let engine = ScreenshotEditorEngine()
        let longText = "Multiline text annotation in PasteVault screenshot editor automatically wraps words across lines when narrowed"
        let startPos = CGPoint(x: 220, y: 120)

        let textId = engine.addText(
            longText,
            at: startPos,
            font: .inter,
            fontSize: 18,
            color: .crimson,
            maxWidth: 280
        )

        let wideRect = ScreenshotEditorEngine.textBoundingRect(
            position: startPos,
            text: longText,
            font: .inter,
            fontSize: 18,
            maxWidth: 280
        )
        XCTAssertLessThanOrEqual(wideRect.width, 280.5, "Text block width must respect maxWidth = 280")
        XCTAssertGreaterThan(wideRect.height, 44, "Long text with maxWidth 280 must wrap into multiple lines")

        // Тянем правую боковую ручку (.textWidthRight) влево, сужая блок до 150 пт от его левого края (wideRect.minX + 150)
        engine.updateAnnotationHandle(
            id: textId,
            handle: .textWidthRight,
            to: CGPoint(x: wideRect.minX + 150.0, y: wideRect.midY),
            isShiftPressed: false
        )

        if case .text(let posAfterRight, let updatedText, let font, let fontSize, _, _, _, let narrowedMaxW) = engine.annotations[0].payload {
            XCTAssertEqual(narrowedMaxW ?? 0, 150, accuracy: 0.5)

            let narrowRect = ScreenshotEditorEngine.textBoundingRect(
                position: posAfterRight,
                text: updatedText,
                font: font,
                fontSize: fontSize,
                maxWidth: narrowedMaxW
            )
            XCTAssertEqual(narrowRect.minX, wideRect.minX, accuracy: 1.0, "Dragging right width handle must keep left edge anchored")
            XCTAssertLessThanOrEqual(narrowRect.width, 150.5, "Narrowed text block width must not exceed new maxWidth = 150")
            XCTAssertGreaterThan(narrowRect.height, wideRect.height, "Narrowing maxWidth from 280 to 150 must increase multiline text height")
        } else {
            XCTFail("Expected text payload after .textWidthRight resize")
        }

        // Проверяем, что синий кружок вытягивания стрелки (↗) находится СНАРУЖИ справа от плашки (rect.maxX + 18)
        let pullPos = ScreenshotEditorEngine.textCalloutPullHandlePosition(
            position: startPos,
            text: longText,
            font: .inter,
            fontSize: 18,
            maxWidth: 280
        )
        XCTAssertEqual(pullPos.x, wideRect.maxX + 18.0, accuracy: 0.001, "Callout pull circle must sit 18pt outside rect.maxX so text inside pill is perfectly centered")
        XCTAssertEqual(pullPos.y, wideRect.midY, accuracy: 0.001)
    }

    func testWideTextBlockCalloutArrowExitsNearClosestEdgeInsteadOfCenter() {
        // Широкий текстовый блок: от x=100 до x=420 (ширина 320, центр midX=260), от y=100 до y=140
        let wideTextRect = CGRect(x: 100, y: 100, width: 320, height: 40)
        // Целевая точка вытянута снизу у правого края (x=390, y=210)
        let rightBottomTarget = CGPoint(x: 390, y: 210)

        // 1. Точка привязки (calloutAnchorPoint) обязана находиться на нижней грани прямо над целью (x ≈ 390, y = 140),
        // а НЕ в геометрическом центре широкого блока (midX = 260)
        let anchor = ScreenshotEditorEngine.calloutAnchorPoint(for: wideTextRect, target: rightBottomTarget, cornerRadius: 7.0)
        XCTAssertEqual(anchor.x, 390.0, accuracy: 0.5, "On a wide text block, callout anchor must attach at closest x (390), not center (260)")
        XCTAssertEqual(anchor.y, 140.0, accuracy: 0.5)

        // 2. Единый контур плашки + стрелки должен иметь ровно 1 замкнутый subpath и компактное основание стрелки справа (x > 350 для всех точек ниже плашки y > 142)
        let path = ScreenshotEditorEngine.unifiedTextCalloutPath(
            pillRect: wideTextRect,
            cornerRadius: 7.0,
            calloutTarget: rightBottomTarget
        )

        var moveCount = 0
        var closeCount = 0
        var belowPillMinX: CGFloat = .greatestFiniteMagnitude

        func inspectPoint(_ pt: CGPoint) {
            if pt.y > wideTextRect.maxY + 2.0 {
                belowPillMinX = min(belowPillMinX, pt.x)
            }
        }

        path.forEach { element in
            switch element {
            case .move(to: let pt):
                moveCount += 1
                inspectPoint(pt)
            case .line(to: let pt):
                inspectPoint(pt)
            case .quadCurve(to: let pt, control: let ctrl):
                inspectPoint(pt)
                inspectPoint(ctrl)
            case .curve(to: let pt, control1: let c1, control2: let c2):
                inspectPoint(pt)
                inspectPoint(c1)
                inspectPoint(c2)
            case .closeSubpath:
                closeCount += 1
            }
        }

        XCTAssertEqual(moveCount, 1)
        XCTAssertEqual(closeCount, 1)
        XCTAssertGreaterThan(belowPillMinX, 350.0, "Arrow protruding below wide text rect near x=390 must remain compact on the right (x > 350) and never stretch back to center (x=260)")
    }

    func testShortAndLongRussianTextNeverWrapsSingleWordOrOverflowsBoxHeight() {
        let startPos = CGPoint(x: 240, y: 160)
        let canvasSize = CGSize(width: 800, height: 600)

        // 1. Короткое слово «Текст» на 16 пт и 24 пт обязано иметь компактную ширину >= minTextBoxWidth и оставаться строго в 1 строку
        for fontSize in [CGFloat(16), CGFloat(24)] {
            let shortRect = ScreenshotEditorEngine.textBoundingRect(
                position: startPos,
                text: "Текст",
                font: .inter,
                fontSize: fontSize,
                maxWidth: nil,
                canvasSize: canvasSize
            )
            XCTAssertGreaterThanOrEqual(shortRect.width, ScreenshotEditorEngine.minTextBoxWidth, "Short label 'Текст' at \(Int(fontSize))pt must have at least minTextBoxWidth")
            let nsFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let oneLineMaxHeight = ceil(nsFont.ascender - nsFont.descender + nsFont.leading) + ScreenshotEditorEngine.textVerticalPadding * 2 + 12.0
            XCTAssertLessThanOrEqual(shortRect.height, oneLineMaxHeight, "'Текст' at \(Int(fontSize))pt must never wrap into two lines ('Текс' + 'т')")
        }

        // 2. Длинный русский текст при автоматической ширине (maxWidth == nil) и при сужении (maxWidth = 140)
        // обязан полностью помещаться по высоте с учётом всех перенесённых строк и verticalPadding * 2
        let longRussianText = "Нашёл единственный настоящий Swift-тестовый сбой: старый UI-regression тест безусловно ожидал заголовок Downloads"
        let autoRect = ScreenshotEditorEngine.textBoundingRect(
            position: startPos,
            text: longRussianText,
            font: .inter,
            fontSize: 18,
            maxWidth: nil,
            canvasSize: canvasSize
        )
        XCTAssertLessThanOrEqual(autoRect.width, 340.5, "Auto-wrapped long text box width must respect defaultMaxBoxWidth <= 340pt")
        XCTAssertGreaterThanOrEqual(autoRect.height, 90.0, "Long Russian text must expand boxHeight vertically for all wrapped lines")

        let narrowedRect = ScreenshotEditorEngine.textBoundingRect(
            position: startPos,
            text: longRussianText,
            font: .inter,
            fontSize: 18,
            maxWidth: 140,
            canvasSize: canvasSize
        )
        XCTAssertEqual(narrowedRect.width, 140.0, accuracy: 0.5)
        XCTAssertGreaterThan(narrowedRect.height, autoRect.height + 40.0, "Narrowing long text to 140pt must proportionally grow boxHeight so top/bottom lines never clip")
    }

    func testNextStepNumberDynamicallyPreservedAcrossToolChanges() {
        let engine = ScreenshotEditorEngine()
        for i in 1...5 {
            let num = engine.addStepPin(at: CGPoint(x: 100 + i * 20, y: 100))
            XCTAssertEqual(num, i)
        }
        XCTAssertEqual(engine.nextStepNumber, 6)

        // Добавляем другие элементы (стрелку, фигуру)
        engine.addArrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50))
        engine.addShape(kind: .roundedRect, from: CGPoint(x: 60, y: 60), to: CGPoint(x: 120, y: 120))
        XCTAssertEqual(engine.nextStepNumber, 6, "Adding other annotations must not alter step counter")

        // Переключаем инструменты
        engine.selectTool(.highlighter)
        engine.selectTool(.shape)
        engine.selectTool(.arrow)
        engine.selectTool(.step)
        XCTAssertEqual(engine.nextStepNumber, 6, "Switching tools back and forth must dynamically preserve nextStepNumber = 6")

        // Ставим 6-й шаг
        let sixth = engine.addStepPin(at: CGPoint(x: 220, y: 100))
        XCTAssertEqual(sixth, 6)
        XCTAssertEqual(engine.nextStepNumber, 7)

        // Отмена последнего действия должна уменьшить номер обратно до 6
        engine.undo()
        XCTAssertEqual(engine.nextStepNumber, 6, "Undo must dynamically recalculate nextStepNumber back to 6")
    }

    func testTextBoundingRectClampedInsideCanvasBounds() {
        let engine = ScreenshotEditorEngine()
        let canvasSize = CGSize(width: 800, height: 600)
        let edgePos = CGPoint(x: 40, y: 150)

        let textId = engine.addText(
            "Текст",
            at: edgePos,
            font: .inter,
            fontSize: 16,
            canvasSize: canvasSize
        )

        let longParagraph = "Длинный текст абзаца для проверки автоматического сдвига текстовой плашки от левого края холста в редакторе скриншотов PasteVault"
        engine.updateText(id: textId, newText: longParagraph, canvasSize: canvasSize)

        guard let item = engine.annotations.first(where: { $0.id == textId }),
              case .text(let clampedPos, let text, let font, let fontSize, _, _, _, let maxWidth) = item.payload else {
            XCTFail("Expected clamped text payload")
            return
        }

        let rect = ScreenshotEditorEngine.textBoundingRect(
            position: clampedPos,
            text: text,
            font: font,
            fontSize: fontSize,
            maxWidth: maxWidth,
            canvasSize: canvasSize
        )

        XCTAssertGreaterThanOrEqual(rect.minX, 8.0, "Clamped text block left edge must not fall below 8pt margin")
        XCTAssertLessThanOrEqual(rect.maxX, canvasSize.width - 8.0, "Clamped text block right edge must not exceed canvasSize.width - 8pt")
        XCTAssertGreaterThanOrEqual(rect.minY, 8.0, "Clamped text block top edge must not fall below 8pt margin")
        XCTAssertLessThanOrEqual(rect.maxY, canvasSize.height - 8.0, "Clamped text block bottom edge must not exceed canvasSize.height - 8pt")
    }

    func testStepPinTipAnchorAndZeroJumpOnClick() {
        let engine = ScreenshotEditorEngine()
        let tipOffset = ScreenshotEditorEngine.stepPinTipOffsetFromCenter

        // 1. Проверяем точное смещение носика метки-шага (beak tip) относительно центра плашки
        XCTAssertEqual(tipOffset.x, 18.4, accuracy: 0.001, "Beak tip X offset must be 18.4pt from pin center at 45°")
        XCTAssertEqual(tipOffset.y, 18.4, accuracy: 0.001, "Beak tip Y offset must be 18.4pt from pin center at 45°")

        // 2. Симулируем наведение мыши на холст
        let cursorPosition = CGPoint(x: 350.0, y: 220.0)
        let previewCenter = ScreenshotEditorEngine.stepPinCenter(forTipPoint: cursorPosition)

        // Центр метки должен быть смещён строго влево-вверх, чтобы остриё носика смотрело в точку курсора
        XCTAssertEqual(previewCenter.x, cursorPosition.x - tipOffset.x, accuracy: 0.001)
        XCTAssertEqual(previewCenter.y, cursorPosition.y - tipOffset.y, accuracy: 0.001)
        XCTAssertEqual(previewCenter.x + tipOffset.x, cursorPosition.x, accuracy: 0.001, "Tip of pin must match cursor X exactly")
        XCTAssertEqual(previewCenter.y + tipOffset.y, cursorPosition.y, accuracy: 0.001, "Tip of pin must match cursor Y exactly")

        // 3. Симулируем клик пользователя в ту же точку курсора (Zero Jump)
        let clickPosition = cursorPosition
        let placedCenter = ScreenshotEditorEngine.stepPinCenter(forTipPoint: clickPosition)
        XCTAssertEqual(previewCenter.x, placedCenter.x, accuracy: 0.0001, "Preview center and placed center must be identical (0px jump)")
        XCTAssertEqual(previewCenter.y, placedCenter.y, accuracy: 0.0001, "Preview center and placed center must be identical (0px jump)")

        // 4. Добавляем метку в движок по рассчитанному центру
        let stepNumber = engine.addStepPin(at: placedCenter)
        XCTAssertEqual(stepNumber, 1)

        // 5. Проверяем хит-тест: плашка должна кликаться и по своему центру, и по кончику носика (cursorPosition)
        let hitAtCenter = engine.hitTest(point: placedCenter)
        XCTAssertNotNil(hitAtCenter, "Hit test must succeed at badge center")
        XCTAssertEqual(hitAtCenter, engine.annotations.first?.id)

        let hitAtTip = engine.hitTest(point: cursorPosition)
        XCTAssertNotNil(hitAtTip, "Hit test must succeed at the beak tip (cursor position)")
        XCTAssertEqual(hitAtTip, engine.annotations.first?.id)

        let hitFarAway = engine.hitTest(point: CGPoint(x: 600, y: 600))
        XCTAssertNil(hitFarAway, "Hit test must fail far away from pin")
    }

    // MARK: - Iteration 30.17 Tests (Curved Arrows, Dual Text Callout, Smart Eraser)

    func testCurvedArrowBezierGeometryAndApexHandle() {
        XCTAssertEqual(ArrowCurveStyle.allCases, [.straight, .curved])
        let start = CGPoint(x: 100, y: 300)
        let end = CGPoint(x: 100, y: 100) // upward vector (0, -200), L = 200 -> bend = 48

        let straightCtrl = ScreenshotEditorEngine.arrowControlPoint(start: start, end: end, style: .straight)
        let curvedCtrl = ScreenshotEditorEngine.arrowControlPoint(start: start, end: end, style: .curved)
        let curvedNegCtrl = ScreenshotEditorEngine.arrowControlPoint(start: start, end: end, style: .curved, customOffset: -48)

        let mid = CGPoint(x: 100, y: 200)
        XCTAssertEqual(straightCtrl.x, mid.x, accuracy: 0.001)
        XCTAssertEqual(straightCtrl.y, mid.y, accuracy: 0.001)

        // Default curved and negative customOffset bend to opposite sides relative to midpoint
        XCTAssertGreaterThan(curvedCtrl.x, mid.x)
        XCTAssertLessThan(curvedNegCtrl.x, mid.x)

        let rightApex = ScreenshotEditorEngine.arrowApexPoint(start: start, end: end, style: .curved)
        XCTAssertEqual(rightApex.x, 148.0, accuracy: 0.001, "Apex at t=0.5 should be offset by 200 * 0.24 = 48pt")

        let engine = ScreenshotEditorEngine()
        engine.selectedArrowStyle = .curved
        let arrowId = engine.addArrow(from: start, to: end, color: .crimson, lineWidth: 4)

        // Hit-test along the curved arc (not on straight chord)
        XCTAssertEqual(engine.hitTest(point: rightApex), arrowId, "hitTestBody must hit curved arrow along its Bezier arc")

        // Dragging apex handle to the left bends curve to the opposite side while keeping .curved style
        engine.updateAnnotationHandle(id: arrowId, handle: .arrowCurveApex, to: CGPoint(x: 60, y: 200), isShiftPressed: false)
        if case .arrow(_, _, _, _, let updatedStyle, let customOffset) = engine.annotations[0].payload {
            XCTAssertEqual(updatedStyle, .curved)
            XCTAssertEqual(customOffset ?? 0, -40.0, accuracy: 0.001)
        } else {
            XCTFail("Expected updated curved arrow payload")
        }
    }

    func testDualTextCalloutCrossingAndMinimumSeparation() {
        let engine = ScreenshotEditorEngine()
        let textPos = CGPoint(x: 400, y: 300)
        let textId = engine.addText("Dual Callout", at: textPos, fontSize: 16, color: .sky)

        // Pull right callout to the left, and left callout to the right (crossing arrows)
        let rightTarget = CGPoint(x: 240, y: 420)
        let leftTarget = CGPoint(x: 560, y: 420)
        engine.updateTextCalloutTarget(id: textId, to: rightTarget, isSecondary: false)
        engine.updateTextCalloutTarget(id: textId, to: leftTarget, isSecondary: true)

        guard case .text(let pos, let text, let font, let fontSize, _, let primary, let secondary, let maxW) = engine.annotations[0].payload else {
            XCTFail("Expected text payload")
            return
        }
        XCTAssertEqual(primary, rightTarget)
        XCTAssertEqual(secondary, leftTarget)

        let rect = ScreenshotEditorEngine.textBoundingRect(position: pos, text: text, font: font, fontSize: fontSize, maxWidth: maxW)
        let combinedPath = ScreenshotEditorEngine.unifiedTextCalloutPath(
            pillRect: rect,
            calloutTarget: primary,
            secondaryCalloutTarget: secondary
        )
        XCTAssertFalse(combinedPath.isEmpty)
        XCTAssertTrue(combinedPath.boundingRect.contains(CGPoint(x: rightTarget.x + 1, y: rightTarget.y - 1)) || combinedPath.boundingRect.width > rect.width)

        // Dragging secondary tip closer than 18pt to primary tip enforces >= 18pt separation
        engine.updateAnnotationHandle(
            id: textId,
            handle: .textSecondaryCalloutTip,
            to: CGPoint(x: rightTarget.x + 4, y: rightTarget.y + 3),
            isShiftPressed: false
        )
        if case .text(_, _, _, _, _, let pAfter, let sAfter, _) = engine.annotations[0].payload,
           let p = pAfter, let s = sAfter {
            let dist = hypot(s.x - p.x, s.y - p.y)
            XCTAssertGreaterThanOrEqual(dist, 17.99, "Dual callout tips must stay at least 18pt apart")
        } else {
            XCTFail("Expected both callout targets to remain active")
        }

        // Translating text keeps both callout tips pinned to their target coordinates
        let beforeP = engine.annotations[0].payload
        engine.translateAnnotation(id: textId, by: CGPoint(x: 20, y: -15))
        if case .text(let pos1, _, _, _, _, let p1, let s1, _) = beforeP,
           case .text(let pos2, _, _, _, _, let p2, let s2, _) = engine.annotations[0].payload {
            XCTAssertNotEqual(pos1, pos2)
            XCTAssertEqual(p1, p2, "Primary callout tip must remain pinned when text moves")
            XCTAssertEqual(s1, s2, "Secondary callout tip must remain pinned when text moves")
        } else {
            XCTFail("Expected both callout targets to remain preserved on translation")
        }
    }

    func testSmartEraserSamplingUndoAndOptionDelete() {
        XCTAssertTrue(ScreenshotTool.eraser.hasSubmenu, "Eraser tool must have size submenu")

        // Create a 100x100 solid sky-blue image with a 1px black line across y = 50
        let size = NSSize(width: 100, height: 100)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setFill()
        NSRect(x: 0, y: 49, width: 100, height: 1).fill()
        image.unlockFocus()

        let cleanBackground = ScreenshotEditorEngine.sampleBackgroundColor(
            in: image,
            at: CGPoint(x: 15, y: 15),
            canvasSize: CGSize(width: 100, height: 100)
        )

        // Exact center-pixel sampling at (50, 50) must return the exact pixel under crosshair (black line), without blending neighbors
        let onLine = ScreenshotEditorEngine.sampleBackgroundColor(
            in: image,
            at: CGPoint(x: 50, y: 50),
            canvasSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(onLine.red, 0.0, accuracy: 0.02)
        XCTAssertEqual(onLine.green, 0.0, accuracy: 0.02)
        XCTAssertEqual(onLine.blue, 0.0, accuracy: 0.02)

        // Exact pixel sampling on the blue background at (50, 40) must return exact clean background
        let sampled = ScreenshotEditorEngine.sampleBackgroundColor(
            in: image,
            at: CGPoint(x: 50, y: 40),
            canvasSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(sampled.red, cleanBackground.red, accuracy: 0.02)
        XCTAssertEqual(sampled.green, cleanBackground.green, accuracy: 0.02)
        XCTAssertEqual(sampled.blue, cleanBackground.blue, accuracy: 0.02)

        let engine = ScreenshotEditorEngine()
        let arrowId = engine.addArrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 80, y: 10))
        _ = engine.addEraserStroke(
            points: [CGPoint(x: 20, y: 40), CGPoint(x: 60, y: 40)],
            strokeWidth: 22,
            red: sampled.red,
            green: sampled.green,
            blue: sampled.blue,
            alpha: sampled.alpha
        )
        XCTAssertEqual(engine.annotations.count, 2)

        engine.undo()
        XCTAssertEqual(engine.annotations.count, 1, "Undo must remove eraser stroke")
        XCTAssertEqual(engine.annotations.first?.id, arrowId)
    }

    func testMultilineShortTextDoesNotInflateBoxWidth() {
        let singleRect = ScreenshotEditorEngine.textBoundingRect(
            position: CGPoint(x: 300, y: 200),
            text: "Текст тест",
            font: .inter,
            fontSize: 16,
            maxWidth: nil,
            canvasSize: CGSize(width: 800, height: 600)
        )
        let multiRect = ScreenshotEditorEngine.textBoundingRect(
            position: CGPoint(x: 300, y: 200),
            text: "Текст тест\nтест",
            font: .inter,
            fontSize: 16,
            maxWidth: nil,
            canvasSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(multiRect.width, singleRect.width, accuracy: 2.0, "Короткий многострочный текст не должен раздувать ширину плашки до 340 pt")
        XCTAssertGreaterThan(multiRect.height, singleRect.height, "Перенос строки должен увеличивать высоту плашки")
    }

    func testHighlighterAnnotationsPreserveIndividualOpacity() {
        let engine = ScreenshotEditorEngine()
        XCTAssertEqual(engine.highlighterOpacity, 0.35, accuracy: 0.001, "Default highlighter opacity must stay 35%")

        engine.highlighterOpacity = 0.0
        let zeroBoxId = engine.addBoxHighlighter(rect: CGRect(x: 5, y: 5, width: 40, height: 20))

        engine.highlighterOpacity = 0.25
        let boxId = engine.addBoxHighlighter(rect: CGRect(x: 10, y: 10, width: 100, height: 40))

        engine.highlighterOpacity = 1.0
        let freehandId = engine.addFreehandHighlighter(points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 20)])

        let zeroItem = engine.annotations.first(where: { $0.id == zeroBoxId })
        let boxItem = engine.annotations.first(where: { $0.id == boxId })
        let freehandItem = engine.annotations.first(where: { $0.id == freehandId })

        if case .highlighterBox(_, _, let op0)? = zeroItem?.payload {
            XCTAssertEqual(op0, 0.0, accuracy: 0.001)
        } else {
            XCTFail("Expected highlighterBox 0% payload")
        }

        if case .highlighterBox(_, _, let op1)? = boxItem?.payload {
            XCTAssertEqual(op1, 0.25, accuracy: 0.001)
        } else {
            XCTFail("Expected highlighterBox 25% payload")
        }

        if case .highlighterFreehand(_, _, _, let op2)? = freehandItem?.payload {
            XCTAssertEqual(op2, 1.0, accuracy: 0.001)
        } else {
            XCTFail("Expected highlighterFreehand 100% payload")
        }
    }

    func testRetouchPipetteSRGBAccuracyOnDisplayP3TwoColorImage() throws {
        let width = 100
        let height = 100
        let p3Space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        let ctx = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: p3Space,
                bitmapInfo: bitmapInfo.rawValue
            )
        )

        // В CoreGraphics (origin bottom-left): верх картинки = y 50...100 (#1E222A), низ = y 0...50 (#FFFFFF)
        let darkTopComponents: [CGFloat] = [30.0 / 255.0, 34.0 / 255.0, 42.0 / 255.0, 1.0]
        let whiteBottomComponents: [CGFloat] = [1.0, 1.0, 1.0, 1.0]
        let darkTopP3 = try XCTUnwrap(CGColor(colorSpace: p3Space, components: darkTopComponents))
        let whiteBottomP3 = try XCTUnwrap(CGColor(colorSpace: p3Space, components: whiteBottomComponents))

        ctx.setFillColor(darkTopP3)
        ctx.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
        ctx.setFillColor(whiteBottomP3)
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 50))

        let cgImg = try XCTUnwrap(ctx.makeImage())
        let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: 100, height: 100))
        let canvasSize = CGSize(width: 100, height: 100)

        let expectedDarkSRGB = try XCTUnwrap(
            NSColor(colorSpace: .displayP3, components: darkTopComponents, count: 4).usingColorSpace(.sRGB)
        )

        // Верхняя точка (y = 15 в системе SwiftUI top-left) -> должна вернуть конвертированный sRGB #1E222A
        let sampledTop = ScreenshotEditorEngine.sampleBackgroundColor(
            in: nsImg,
            at: CGPoint(x: 50, y: 15),
            canvasSize: canvasSize
        )
        XCTAssertEqual(sampledTop.red, expectedDarkSRGB.redComponent, accuracy: 0.015)
        XCTAssertEqual(sampledTop.green, expectedDarkSRGB.greenComponent, accuracy: 0.015)
        XCTAssertEqual(sampledTop.blue, expectedDarkSRGB.blueComponent, accuracy: 0.015)

        // Нижняя точка (y = 85 в системе SwiftUI top-left) -> должна вернуть чистый белый (1, 1, 1)
        let sampledBottom = ScreenshotEditorEngine.sampleBackgroundColor(
            in: nsImg,
            at: CGPoint(x: 50, y: 85),
            canvasSize: canvasSize
        )
        XCTAssertEqual(sampledBottom.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(sampledBottom.green, 1.0, accuracy: 0.01)
        XCTAssertEqual(sampledBottom.blue, 1.0, accuracy: 0.01)

        // Рисуем мазок ретуши на тёмной верхней половине и проверяем sRGB-совпадение после renderAnnotatedImage
        let engine = ScreenshotEditorEngine()
        engine.addEraserStroke(
            points: [CGPoint(x: 50, y: 25)],
            strokeWidth: 14,
            red: sampledTop.red,
            green: sampledTop.green,
            blue: sampledTop.blue,
            alpha: sampledTop.alpha
        )
        let rendered = try XCTUnwrap(engine.renderAnnotatedImage(baseImage: nsImg, canvasSize: canvasSize))
        let renderedSample = ScreenshotEditorEngine.sampleBackgroundColor(
            in: rendered,
            at: CGPoint(x: 50, y: 25),
            canvasSize: canvasSize
        )
        XCTAssertEqual(renderedSample.red, sampledTop.red, accuracy: 0.015)
        XCTAssertEqual(renderedSample.green, sampledTop.green, accuracy: 0.015)
        XCTAssertEqual(renderedSample.blue, sampledTop.blue, accuracy: 0.015)
    }

    func testCompactTextBoxWidthTightToShortAndMultilineText() {
        let shortRect = ScreenshotEditorEngine.textBoundingRect(
            position: CGPoint(x: 200, y: 200),
            text: "а\nб",
            font: .inter,
            fontSize: 16,
            maxWidth: nil,
            canvasSize: CGSize(width: 800, height: 600)
        )
        XCTAssertGreaterThanOrEqual(shortRect.width, ScreenshotEditorEngine.minTextBoxWidth)
        XCTAssertLessThan(shortRect.width, 110.0, "Short multiline text 'а\\nб' must stay compact under 110pt")

        let hiRect = ScreenshotEditorEngine.textBoundingRect(
            position: CGPoint(x: 200, y: 200),
            text: "Hi",
            font: .inter,
            fontSize: 16,
            maxWidth: nil,
            canvasSize: CGSize(width: 800, height: 600)
        )
        XCTAssertLessThan(hiRect.width, 110.0, "Short word 'Hi' must hug text tightly under 110pt")
    }

    // MARK: - Stage 2 Tests (Iteration 30.31)

    func testUndoRedoStackAndExistingTextEditSession() {
        let engine = ScreenshotEditorEngine()
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.canRedo)

        let textId = engine.addText("Initial", at: CGPoint(x: 200, y: 200))
        XCTAssertEqual(engine.annotations.count, 1)
        XCTAssertTrue(engine.canUndo)
        XCTAssertFalse(engine.canRedo)

        // Undo adds item -> empty canvas, canRedo = true
        engine.undo()
        XCTAssertTrue(engine.annotations.isEmpty)
        XCTAssertFalse(engine.canUndo)
        XCTAssertTrue(engine.canRedo)

        // Redo restores it cleanly
        engine.redo()
        XCTAssertEqual(engine.annotations.count, 1)
        XCTAssertEqual(engine.annotations.first?.id, textId)
        XCTAssertFalse(engine.canRedo)

        // Undo + new edit clears redoStack
        engine.undo()
        XCTAssertTrue(engine.canRedo)
        _ = engine.addArrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 10))
        XCTAssertFalse(engine.canRedo, "Performing a new action must clear redoStack")

        // Existing-text edit session must record a single undo step and preserve old text on Undo
        let editableId = engine.addText("Old label", at: CGPoint(x: 220, y: 180))
        engine.beginEditingTextAnnotation(id: editableId)
        engine.updateText(id: editableId, newText: "Updated label")
        engine.commitActiveTextEditing()
        if case .text(_, let updatedText, _, _, _, _, _, _) = engine.annotations.last?.payload {
            XCTAssertEqual(updatedText, "Updated label")
        } else {
            XCTFail("Expected text annotation")
        }

        engine.undo()
        if case .text(_, let revertedText, _, _, _, _, _, _) = engine.annotations.last?.payload {
            XCTAssertEqual(revertedText, "Old label", "Undo after editing existing text must restore previous text")
        } else {
            XCTFail("Expected reverted text annotation")
        }

        engine.redo()
        if case .text(_, let redoneText, _, _, _, _, _, _) = engine.annotations.last?.payload {
            XCTAssertEqual(redoneText, "Updated label", "Redo after undoing text edit must restore updated text")
        } else {
            XCTFail("Expected redone text annotation")
        }
    }

    func testLivePropertyEditsAndToolSelectionPreservation() {
        let engine = ScreenshotEditorEngine()
        let hlId = engine.addBoxHighlighter(rect: CGRect(x: 40, y: 40, width: 120, height: 32))
        engine.selectedAnnotationId = hlId

        // Drag highlighter opacity live updates without inflating undoStack when recordUndo == false
        let undoCountBefore = engine.canUndo
        XCTAssertTrue(undoCountBefore)
        engine.updateSelectedAnnotationHighlighterOpacity(0.65, recordUndo: true)
        engine.updateSelectedAnnotationHighlighterOpacity(0.75, recordUndo: false)
        if case .highlighterBox(_, _, let op) = engine.annotations.first?.payload {
            XCTAssertEqual(op, 0.75, accuracy: 0.001)
        } else {
            XCTFail("Expected highlighterBox payload")
        }
        engine.undo()
        if case .highlighterBox(_, _, let revertedOp) = engine.annotations.first?.payload {
            XCTAssertEqual(revertedOp, 0.35, accuracy: 0.001, "Single undo must revert whole slider drag")
        } else {
            XCTFail("Expected highlighterBox payload after undo")
        }

        // Tool switching preserves selection for matching tool or .hand, clears for mismatch
        engine.selectedAnnotationId = hlId
        engine.selectTool(.highlighter)
        XCTAssertEqual(engine.selectedAnnotationId, hlId, "Selecting matching tool must preserve selection")
        engine.selectTool(.hand)
        XCTAssertEqual(engine.selectedAnnotationId, hlId, "Selecting hand tool must preserve selection")
        engine.selectTool(.arrow)
        XCTAssertNil(engine.selectedAnnotationId, "Selecting incompatible tool must clear selection")
    }

    func testRenderPreservesAlphaAndNativeOneXResolution() throws {
        let size = NSSize(width: 240, height: 120)
        // Build an explicit 1x sRGB RGBA bitmap with transparent background (alpha = 0) and a red center rect
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 240,
            pixelsHigh: 120,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 240 * 4,
            bitsPerPixel: 32
        ) else {
            XCTFail("Failed to allocate 1x RGBA bitmap")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 1.0).setFill()
        NSRect(x: 80, y: 40, width: 80, height: 40).fill()
        NSGraphicsContext.restoreGraphicsState()

        let baseImage = NSImage(size: size)
        baseImage.addRepresentation(bitmapRep)

        let engine = ScreenshotEditorEngine()
        let rendered = try XCTUnwrap(
            engine.renderAnnotatedImage(baseImage: baseImage, canvasSize: size, zoomScale: 1.0)
        )
        let outCG = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(outCG.width, 240, "1x image must stay 240px wide without forced 2x upscale")
        XCTAssertEqual(outCG.height, 120, "1x image must stay 120px tall without forced 2x upscale")

        let outRep = NSBitmapImageRep(cgImage: outCG)
        let cornerColor = try XCTUnwrap(outRep.colorAt(x: 4, y: 4))
        XCTAssertEqual(cornerColor.alphaComponent, 0.0, accuracy: 0.02, "Transparent PNG corner must preserve alpha == 0")
    }

    func testNarrowCanvasTextCalloutShortTailAndClampedStepPin() {
        let narrowCanvas = CGSize(width: 320, height: 600)
        let longText = "This is a deliberately long single-line annotation text for a narrow viewport test"
        let rect = ScreenshotEditorEngine.textBoundingRect(
            position: CGPoint(x: 160, y: 120),
            text: longText,
            font: .inter,
            fontSize: 16,
            maxWidth: nil,
            canvasSize: narrowCanvas
        )
        XCTAssertLessThanOrEqual(rect.width, narrowCanvas.width - 16.0 + 0.5, "Text box must never exceed narrow canvas width")

        // Pull handles near canvas edge must stay clamped inside canvasSize
        let rightPull = ScreenshotEditorEngine.textCalloutPullHandlePosition(
            position: CGPoint(x: 310, y: 100),
            text: "Edge",
            fontSize: 16,
            canvasSize: narrowCanvas
        )
        XCTAssertLessThanOrEqual(rightPull.x, narrowCanvas.width - 12.0 + 0.01)
        let leftPull = ScreenshotEditorEngine.textSecondaryCalloutPullHandlePosition(
            position: CGPoint(x: 10, y: 100),
            text: "Edge",
            fontSize: 16,
            canvasSize: narrowCanvas
        )
        XCTAssertGreaterThanOrEqual(leftPull.x, 12.0 - 0.01)

        // Short tail (4.0 - 6.2 pt beyond pillRect edge) must build clean path with no NaN
        let pillRect = CGRect(x: 100, y: 100, width: 90, height: 34)
        for offset in [4.2, 5.2, 6.2] as [CGFloat] {
            let shortTarget = CGPoint(x: pillRect.maxX + offset, y: pillRect.midY)
            let path = ScreenshotEditorEngine.unifiedTextCalloutPath(
                pillRect: pillRect,
                cornerRadius: 7.0,
                calloutTarget: shortTarget
            )
            let bounds = path.boundingRect
            XCTAssertFalse(bounds.isNull || bounds.isEmpty)
            XCTAssertFalse(bounds.width.isNaN || bounds.height.isNaN)
            XCTAssertGreaterThanOrEqual(bounds.maxX, shortTarget.x - 0.5)
        }

        // Step pin clamped inside canvas corners so badge does not clip off-canvas
        let topLeftPinCenter = ScreenshotEditorEngine.clampedStepPinCenter(
            forTipPoint: CGPoint(x: 2, y: 2),
            canvasSize: narrowCanvas
        )
        XCTAssertGreaterThanOrEqual(topLeftPinCenter.x, 16.0)
        XCTAssertGreaterThanOrEqual(topLeftPinCenter.y, 16.0)
    }

    func testSteppedEscapeAndModalKeyEventGuard() {
        let engine = ScreenshotEditorEngine()
        let textId = engine.addText("Label", at: CGPoint(x: 120, y: 120))
        engine.beginEditingTextAnnotation(id: textId)
        engine.activeSubmenu = .color
        engine.selectedAnnotationId = textId

        // 1. Editing text -> commit text
        XCTAssertEqual(engine.handleEscape(), .committedText)
        XCTAssertNil(engine.editingTextAnnotationId)

        // 2. Open submenu -> close submenu (first re-select annotation for step 3 check)
        engine.selectedAnnotationId = textId
        XCTAssertEqual(engine.handleEscape(), .closedSubmenu)
        XCTAssertNil(engine.activeSubmenu)

        // 3. Selected annotation -> clear selection
        XCTAssertEqual(engine.handleEscape(), .clearedSelection)
        XCTAssertNil(engine.selectedAnnotationId)

        // 4. Clean state -> close editor
        XCTAssertEqual(engine.handleEscape(), .closeEditor)

        // Key-event guard blocks when modal window (NSSavePanel/NSAlert) or unrelated NSTextView is active
        let hostWin = NSWindow()
        let otherWin = NSWindow()
        XCTAssertFalse(
            ScreenshotEditorEngine.shouldProcessKeyEvent(
                eventWindow: hostWin,
                hostWindow: hostWin,
                hasModalWindow: true,
                isRecordingShortcut: false,
                isHostFirstResponderTextView: false,
                isEditingAnnotationText: false
            )
        )
        XCTAssertFalse(
            ScreenshotEditorEngine.shouldProcessKeyEvent(
                eventWindow: otherWin,
                hostWindow: hostWin,
                hasModalWindow: false,
                isRecordingShortcut: false,
                isHostFirstResponderTextView: false,
                isEditingAnnotationText: false
            )
        )
        XCTAssertFalse(
            ScreenshotEditorEngine.shouldProcessKeyEvent(
                eventWindow: hostWin,
                hostWindow: hostWin,
                hasModalWindow: false,
                isRecordingShortcut: false,
                isHostFirstResponderTextView: true,
                isEditingAnnotationText: false
            )
        )
        XCTAssertTrue(
            ScreenshotEditorEngine.shouldProcessKeyEvent(
                eventWindow: hostWin,
                hostWindow: hostWin,
                hasModalWindow: false,
                isRecordingShortcut: false,
                isHostFirstResponderTextView: false,
                isEditingAnnotationText: false
            )
        )
    }

    func testUndoRedoKeyRecognitionAcrossLayoutsAndShiftPriority() {
        // 1. Все варианты Z / Я + физический ANSI keyCode 6 распознаются в любой раскладке
        XCTAssertTrue(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: "z", keyCode: 0))
        XCTAssertTrue(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: "Z", keyCode: 0))
        XCTAssertTrue(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: "я", keyCode: 0))
        XCTAssertTrue(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: "Я", keyCode: 0))
        XCTAssertTrue(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: nil, keyCode: 6))
        XCTAssertTrue(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: "я", keyCode: 6))

        // Посторонние клавиши не срабатывают
        XCTAssertFalse(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: "a", keyCode: 0))
        XCTAssertFalse(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: "ф", keyCode: 0))
        XCTAssertFalse(ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: "x", keyCode: 7))

        // 2. Приоритет Cmd+Shift+Z (Redo) над Cmd+Z (Undo), включая CapsLock
        let engine = ScreenshotEditorEngine()
        let firstId = engine.addArrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50))
        let secondId = engine.addArrow(from: CGPoint(x: 60, y: 10), to: CGPoint(x: 100, y: 50))
        XCTAssertEqual(engine.annotations.count, 2)

        // Вспомогательная проверка маршрутизации как в keyDownMonitor
        func simulateShortcut(flags: NSEvent.ModifierFlags, chars: String?, keyCode: UInt16) -> String? {
            let relevant = flags.intersection([.command, .shift, .option, .control])
            guard relevant.contains(.command),
                  relevant.intersection([.option, .control]).isEmpty,
                  ScreenshotEditorEngine.matchesUndoRedoKey(charactersIgnoringModifiers: chars, keyCode: keyCode) else {
                return nil
            }
            if relevant.contains(.shift) {
                engine.redo()
                return "redo"
            } else {
                engine.undo()
                return "undo"
            }
        }

        // Cmd+Z в русской раскладке ("я") -> undo (остаётся 1 стрелка)
        XCTAssertEqual(simulateShortcut(flags: [.command, .capsLock], chars: "я", keyCode: 6), "undo")
        XCTAssertEqual(engine.annotations.map(\.id), [firstId])

        // Cmd+Shift+Z в русской раскладке ("Я") -> приоритет Redo (возвращается вторая стрелка)
        XCTAssertEqual(simulateShortcut(flags: [.command, .shift], chars: "Я", keyCode: 6), "redo")
        XCTAssertEqual(engine.annotations.map(\.id), [firstId, secondId])
    }

    func testPureShiftModifierIgnoresCommandOptionControl() {
        XCTAssertTrue(ScreenshotEditorEngine.isPureShiftModifier([.shift]))
        XCTAssertTrue(ScreenshotEditorEngine.isPureShiftModifier([.shift, .capsLock]))
        XCTAssertFalse(ScreenshotEditorEngine.isPureShiftModifier([.command, .shift]))
        XCTAssertFalse(ScreenshotEditorEngine.isPureShiftModifier([.option, .shift]))
        XCTAssertFalse(ScreenshotEditorEngine.isPureShiftModifier([.control, .shift]))
        XCTAssertFalse(ScreenshotEditorEngine.isPureShiftModifier([.command]))
        XCTAssertFalse(ScreenshotEditorEngine.isPureShiftModifier([]))
    }
}
