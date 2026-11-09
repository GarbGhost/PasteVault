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
        if case .text(let pos, let updatedText, let font, let size, _, _, _) = engine.annotations[1].payload {
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
        if let cgCropped = zoomedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cgCropped)
            if let cornerColor = rep.colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB) {
                XCTAssertGreaterThan(cornerColor.greenComponent, 0.7, "Cropped image corner must be the green central region, not the red outer border")
                XCTAssertLessThan(cornerColor.redComponent, 0.3, "Red outer border must be cropped out at 200% zoom")
            }
        }

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
        if case .arrow(let start, let end, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(start, CGPoint(x: 25, y: 10))
            XCTAssertEqual(end, CGPoint(x: 95, y: 90))
        } else {
            XCTFail("Expected arrow payload")
        }

        // Изменяем ручку .end до (130, 140)
        engine.updateAnnotationHandle(id: arrowId, handle: .end, to: CGPoint(x: 130, y: 140), isShiftPressed: false)
        if case .arrow(let start, let end, _, _) = engine.annotations[0].payload {
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
        if case .arrow(_, _, let color, let width) = engine.annotations[0].payload {
            XCTAssertEqual(color, .emerald)
            XCTAssertEqual(width, 4)
        } else {
            XCTFail("Expected arrow payload")
        }

        // Меняем толщину линии на лету на 12 pt
        engine.updateSelectedAnnotationStrokeWidth(12)
        if case .arrow(_, _, let color, let width) = engine.annotations[0].payload {
            XCTAssertEqual(color, .emerald)
            XCTAssertEqual(width, 12)
        } else {
            XCTFail("Expected arrow payload")
        }

        // Проверяем отмену изменений через Undo
        engine.undo() // отменяет толщину 12 -> 4
        if case .arrow(_, _, _, let width) = engine.annotations[0].payload {
            XCTAssertEqual(width, 4)
        }
        engine.undo() // отменяет цвет Emerald -> Crimson
        if case .arrow(_, _, let color, _) = engine.annotations[0].payload {
            XCTAssertEqual(color, .crimson)
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
        if case .arrow(_, _, let firstColor, let firstWidth) = engine.annotations[0].payload {
            XCTAssertEqual(firstColor, .crimson, "Previously drawn arrow color must not mutate when changing tool color")
            XCTAssertEqual(firstWidth, 4, "Previously drawn arrow stroke width must not mutate when changing tool stroke width")
        } else {
            XCTFail("Expected arrow payload")
        }

        // 3. Рисуем вторую стрелку — она создаётся уже с новыми настройками (12 pt, Emerald)
        _ = engine.addArrow(from: CGPoint(x: 20, y: 80), to: CGPoint(x: 140, y: 120))
        if case .arrow(_, _, let secondColor, let secondWidth) = engine.annotations[1].payload {
            XCTAssertEqual(secondColor, .emerald)
            XCTAssertEqual(secondWidth, 12)
        } else {
            XCTFail("Expected second arrow payload")
        }

        // 4. Только если явно выделить первую стрелку инструментом «✋ Рука» — смена цвета изменит её
        engine.selectedAnnotationId = firstArrowId
        engine.updateSelectedAnnotationColor(.sky)
        if case .arrow(_, _, let updatedFirstColor, _) = engine.annotations[0].payload {
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
        if case .text(_, let t1, let f1, let s1, let c1, _, _) = engine.annotations[0].payload {
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

        if case .text(_, let updatedText1, let font1After, let size1After, let color1After, _, _) = engine.annotations[0].payload {
            XCTAssertEqual(updatedText1, "Edited First Note")
            XCTAssertEqual(font1After, .jetBrainsMono)
            XCTAssertEqual(size1After, 18)
            XCTAssertEqual(color1After, .amber)
        } else {
            XCTFail("Expected updated first text payload")
        }

        // Вторая надпись по-прежнему осталась Tektur 24pt Sky
        if case .text(_, let text2After, let font2After, let size2After, let color2After, _, _) = engine.annotations[1].payload {
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

        if case .text(let posBefore, let text, _, let fontSize, _, let targetBefore, let maxWBefore) = engine.annotations[0].payload {
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

        if case .text(let posAfter, let text, _, let fontSize, _, let targetAfter, let maxWAfter) = engine.annotations[0].payload {
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
        if case .text(_, _, _, _, _, let activeTarget, _) = engine.annotations[0].payload {
            XCTAssertEqual(activeTarget, CGPoint(x: 360, y: 260))
        } else {
            XCTFail("Expected active calloutTarget")
        }

        // 2. Перетаскиваем остриё стрелки обратно внутрь рамки текста (205, 202) и завершаем жест
        engine.updateAnnotationHandle(id: textId, handle: .textCalloutTip, to: CGPoint(x: 205, y: 202), isShiftPressed: false)
        engine.finalizeTextCalloutDrag(id: textId)
        if case .text(_, _, _, _, _, let retractedTarget, _) = engine.annotations[0].payload {
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

        if case .text(let posAfterRight, let updatedText, let font, let fontSize, _, _, let narrowedMaxW) = engine.annotations[0].payload {
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

        // 1. Короткое слово «Текст» на 16 пт и 24 пт обязано иметь ширину >= 110 пт (minBoxWidth) и оставаться строго в 1 строку
        for fontSize in [CGFloat(16), CGFloat(24)] {
            let shortRect = ScreenshotEditorEngine.textBoundingRect(
                position: startPos,
                text: "Текст",
                font: .inter,
                fontSize: fontSize,
                maxWidth: nil,
                canvasSize: canvasSize
            )
            XCTAssertGreaterThanOrEqual(shortRect.width, 110.0, "Short label 'Текст' at \(Int(fontSize))pt must have at least minBoxWidth = 110pt")
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
              case .text(let clampedPos, let text, let font, let fontSize, _, _, let maxWidth) = item.payload else {
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
}
