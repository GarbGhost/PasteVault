import SwiftUI
import AppKit

// MARK: - Deck Enums & Types

/// Направление перекладывания 3D-колоды фрагментов
public enum DeckScrollDirection: Equatable, Sendable {
    case up
    case down
}

/// Фазы двухфазной 3D-анимации колоды
public enum DeckAnimPhase: Equatable, Sendable {
    case idle
    case lift
    case settle
}

/// Рассчитанная 3D-поза для карточки колоды
public struct DeckCardCalculatedPose: Equatable, Sendable {
    public var offsetY: CGFloat
    public var rotateX: Double
    public var scaleX: CGFloat
    public var scaleY: CGFloat
    public var zIndex: Double
    public var shadowDarkness: Double
    public var opacity: Double

    public init(
        offsetY: CGFloat,
        rotateX: Double,
        scaleX: CGFloat,
        scaleY: CGFloat,
        zIndex: Double,
        shadowDarkness: Double,
        opacity: Double
    ) {
        self.offsetY = offsetY
        self.rotateX = rotateX
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.zIndex = zIndex
        self.shadowDarkness = shadowDarkness
        self.opacity = opacity
    }

    /// Базовые координаты покоя (resting state) для slot = 0...4
    public static func resting(slot: Int) -> DeckCardCalculatedPose {
        switch slot {
        case 0:
            return DeckCardCalculatedPose(offsetY: 82, rotateX: 0, scaleX: 1.0, scaleY: 1.0, zIndex: 30, shadowDarkness: 0.0, opacity: 1.0)
        case 1:
            return DeckCardCalculatedPose(offsetY: 34, rotateX: -4, scaleX: 0.96, scaleY: 0.96, zIndex: 25, shadowDarkness: 0.14, opacity: 1.0)
        case 2:
            return DeckCardCalculatedPose(offsetY: -4, rotateX: -7, scaleX: 0.92, scaleY: 0.92, zIndex: 20, shadowDarkness: 0.26, opacity: 1.0)
        case 3:
            return DeckCardCalculatedPose(offsetY: -36, rotateX: -10, scaleX: 0.88, scaleY: 0.88, zIndex: 15, shadowDarkness: 0.36, opacity: 1.0)
        case 4:
            return DeckCardCalculatedPose(offsetY: -64, rotateX: -13, scaleX: 0.845, scaleY: 0.845, zIndex: 10, shadowDarkness: 0.46, opacity: 1.0)
        default:
            return DeckCardCalculatedPose(offsetY: -64, rotateX: -13, scaleX: 0.845, scaleY: 0.845, zIndex: 10, shadowDarkness: 0.46, opacity: 1.0)
        }
    }
}

// MARK: - Deck Geometry & Pose Helper

public enum SnippetDeckHelper {
    /// Сдвиг вертикального центрирования стопки в зависимости от общего количества карточек
    public static func centeringShiftUp(forTotal total: Int) -> CGFloat {
        switch total {
        case 0, 1: return -68   // 1 карточка стоит строго по центру поля (+14 pt)
        case 2:    return -46   // 2 карточки аккуратно по центру
        case 3:    return -28   // 3 карточки
        case 4:    return -12   // 4 карточки
        default:   return 0     // 5 и более карточек — полная колода
        }
    }

    /// Расчёт целевого индекса карточки по Y-координате внутри капсулы Scrubber
    public static func scrubberTargetIndex(locationY: CGFloat, capsuleHeight: CGFloat, total: Int) -> Int {
        guard total > 1 else { return 0 }
        let h = max(capsuleHeight, 1)
        let ratio = min(max(locationY / h, 0.0), 1.0)
        return Int(round(ratio * Double(total - 1)))
    }

    /// Форматирование счётчика колоды (например, "114/114")
    public static func counterText(activeIndex: Int, total: Int) -> String {
        "\(activeIndex + 1)/\(total)"
    }

    /// Диапазон индексов точек в вертикальной капсуле Scrubber (до `maxVisibleDots`, по умолчанию 10)
    public static func visibleDotIndices(total: Int, activeIndex: Int, maxVisibleDots: Int = 10) -> [Int] {
        guard total > 0, maxVisibleDots > 0 else { return [] }
        guard total > maxVisibleDots else { return Array(0..<total) }
        let clampedActive = min(max(0, activeIndex), total - 1)
        let halfWindow = max(0, (maxVisibleDots / 2) - 1)
        let start = max(0, min(clampedActive - halfWindow, total - maxVisibleDots))
        return Array(start..<(start + maxVisibleDots))
    }

    /// Интервал шага при непрерывном каскадном скролле:
    /// первые 5 карточек — 0.11 сек (~9/сек), далее ускорение до 0.065 сек (~15/сек)
    public static func continuousStepInterval(stepCount: Int) -> TimeInterval {
        stepCount < 5 ? 0.11 : 0.065
    }

    /// Циклический расчёт следующего индекса колоды с учётом граничных значений 0 и total - 1
    public static func wrappedDeckIndex(currentIndex: Int, direction: DeckScrollDirection, total: Int) -> Int {
        guard total > 1 else { return 0 }
        let safeCurrent = ((currentIndex % total) + total) % total
        switch direction {
        case .up:
            return (safeCurrent + 1) % total
        case .down:
            return (safeCurrent - 1 + total) % total
        }
    }

    /// Сквозная нумерация всех фрагментов по порядку создания (`createdAt` от старых к новым, tie-break по `id`):
    /// первый созданный фрагмент = #1, последний = #N. Не зависит от выбранной категории или сортировки.
    public static func computeGlobalNumbers(for allSnippets: [QuickSnippetItem]) -> [String: Int] {
        let sorted = allSnippets.sorted { a, b in
            if a.createdAt != b.createdAt {
                return a.createdAt < b.createdAt
            }
            return a.id < b.id
        }
        var map: [String: Int] = [:]
        map.reserveCapacity(sorted.count)
        for (idx, item) in sorted.enumerated() {
            map[item.id] = idx + 1
        }
        return map
    }

    /// Проверка совпадения поискового запроса с номером карточки (`#19` или `19`)
    public static func matchesNumberQuery(globalNumber: Int, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              globalNumber > 0,
              trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return false }
        let numTag = "#\(globalNumber)"
        let numStr = "\(globalNumber)"
        return numTag.localizedCaseInsensitiveContains(trimmed) || numStr.localizedCaseInsensitiveContains(trimmed)
    }

    private static func makeUniqueRankMap(_ ids: [String]) -> [String: Int] {
        var rankById: [String: Int] = [:]
        rankById.reserveCapacity(ids.count)
        for (offset, id) in ids.enumerated() where rankById[id] == nil {
            rankById[id] = offset
        }
        return rankById
    }

    /// Сортировка фрагментов по одному из 5 режимов (pinned / mostUsed / newest / oldest / alphabetical)
    public static func sortSnippets(
        _ list: [QuickSnippetItem],
        order: String,
        pinnedSnapshotIds: [String] = [],
        titleTransform: (String) -> String = { $0 }
    ) -> [QuickSnippetItem] {
        switch order {
        case "mostUsed":
            if !pinnedSnapshotIds.isEmpty {
                let rankById = makeUniqueRankMap(pinnedSnapshotIds)
                return list.sorted { a, b in
                    switch (rankById[a.id], rankById[b.id]) {
                    case (let rA?, let rB?):
                        return rA < rB
                    case (nil, _?):
                        return false
                    case (_?, nil):
                        return true
                    case (nil, nil):
                        if a.useCount != b.useCount { return a.useCount > b.useCount }
                        return a.createdAt > b.createdAt
                    }
                }
            }
            return list.sorted { a, b in
                if a.useCount != b.useCount { return a.useCount > b.useCount }
                return a.createdAt > b.createdAt
            }
        case "newest":
            return list.sorted { $0.createdAt > $1.createdAt }
        case "oldest":
            return list.sorted { $0.createdAt < $1.createdAt }
        case "alphabetical":
            return list.sorted { a, b in
                let ta = titleTransform(a.title)
                let tb = titleTransform(b.title)
                let cmp = ta.localizedStandardCompare(tb)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return a.createdAt > b.createdAt
            }
        default: // "pinned"
            if !pinnedSnapshotIds.isEmpty {
                let rankById = makeUniqueRankMap(pinnedSnapshotIds)
                return list.sorted { a, b in
                    let rankA = rankById[a.id]
                    let rankB = rankById[b.id]
                    switch (rankA, rankB) {
                    case (let rA?, let rB?):
                        return rA < rB
                    case (nil, _?):
                        return false
                    case (_?, nil):
                        return true
                    case (nil, nil):
                        if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                        return a.createdAt > b.createdAt
                    }
                }
            }
            return list.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                return a.createdAt > b.createdAt
            }
        }
    }

    /// Итоговый вертикальный сдвиг карточки с учётом центрирования и высоты подъёма для 2/3 карточек
    public static func finalOffsetY(
        baseOffsetY: CGFloat,
        centeringShiftUp: CGFloat,
        total: Int,
        isBeingShuffled: Bool,
        phase: DeckAnimPhase
    ) -> CGFloat {
        if isBeingShuffled && phase == .lift {
            switch total {
            case 2: return -18
            case 3: return -42
            default: return baseOffsetY + centeringShiftUp
            }
        }
        return baseOffsetY + centeringShiftUp
    }

    /// Круговая глубина карточки в стопке
    public static func circularDepth(index: Int, activeIndex: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return (index - activeIndex + total) % total
    }

    /// Условие видимости карточки в ZStack:
    /// depth <= 4 || isShuffling (snippets[idx].id == shuffleCardId)
    /// При total > 5 и активном перелистывании, если перекладываемая карточка находится в slot 4 (depth >= 4),
    /// вторая карточка с depth == 4 временно не рендерится, исключая наложение двух карточек в slot 4.
    public static func isCardVisible(
        depth: Int,
        total: Int,
        isShuffling: Bool,
        isShufflingActive: Bool = false,
        shufflingCardDepth: Int? = nil
    ) -> Bool {
        if isShuffling { return true }
        if depth > 4 { return false }
        if depth == 4 && isShufflingActive && total > 5 {
            if let shufDepth = shufflingCardDepth, shufDepth >= 4 {
                return false
            }
        }
        return depth <= 4
    }

    /// Расчёт слота visualSlot (0...4)
    public static func visualSlot(forDepth depth: Int, total: Int) -> Int {
        return min(depth, 4)
    }

    /// Расчёт позы карточки с учётом фазы анимации, направления и роли (перекладываемая vs волна остальных)
    public static func calculatePose(
        slot: Int,
        depth: Int,
        isBeingShuffled: Bool,
        direction: DeckScrollDirection,
        phase: DeckAnimPhase,
        total: Int
    ) -> DeckCardCalculatedPose {
        if isBeingShuffled {
            switch phase {
            case .lift:
                if direction == .up {
                    // Фаза 1 — подъём передней карточки вверх и наклон в плоскость над макушкой колоды
                    return DeckCardCalculatedPose(
                        offsetY: -104,
                        rotateX: -72,
                        scaleX: 0.855,
                        scaleY: 0.72,
                        zIndex: 38, // строго поверх всех карточек во время подъёма!
                        shadowDarkness: 0.28,
                        opacity: 1.0
                    )
                } else { // direction == .down
                    // Фаза 1 — подъём последней карточки ИЗ КОНЦА КОЛОДЫ вверх
                    return DeckCardCalculatedPose(
                        offsetY: -104,
                        rotateX: -72,
                        scaleX: 0.88,
                        scaleY: 0.72,
                        zIndex: 10, // КРИТИЧНО: во время фазы .lift при листании вниз карточка ОБЯЗАНА сохранять задний слой zIndex = 10!
                        shadowDarkness: 0.18,
                        opacity: 1.0
                    )
                }
            case .settle:
                if direction == .up {
                    // Фаза 2 — плавное опускание сверху вниз в задний карман колоды
                    var p = DeckCardCalculatedPose.resting(slot: slot)
                    p.zIndex = 10 // позади колоды!
                    return p
                } else { // direction == .down
                    // Фаза 2 — плавное опускание в начало колоды на передний план
                    var p = DeckCardCalculatedPose.resting(slot: 0)
                    p.zIndex = 38 // поверх всех карточек!
                    return p
                }
            case .idle:
                return DeckCardCalculatedPose.resting(slot: slot)
            }
        }

        // Для остальных карточек (!isBeingShuffled):
        switch phase {
        case .lift:
            if direction == .up {
                switch slot {
                case 1:
                    return DeckCardCalculatedPose(offsetY: 58, rotateX: -2, scaleX: 0.98, scaleY: 0.98, zIndex: 25, shadowDarkness: 0.06, opacity: 1.0)
                case 2:
                    return DeckCardCalculatedPose(offsetY: 15, rotateX: -5.5, scaleX: 0.94, scaleY: 0.94, zIndex: 20, shadowDarkness: 0.20, opacity: 1.0)
                case 3:
                    return DeckCardCalculatedPose(offsetY: -20, rotateX: -8.5, scaleX: 0.90, scaleY: 0.90, zIndex: 15, shadowDarkness: 0.31, opacity: 1.0)
                case 4:
                    return DeckCardCalculatedPose(offsetY: -50, rotateX: -11.5, scaleX: 0.862, scaleY: 0.862, zIndex: 10, shadowDarkness: 0.41, opacity: 1.0)
                default:
                    return DeckCardCalculatedPose.resting(slot: slot)
                }
            } else { // direction == .down
                switch slot {
                case 0:
                    return DeckCardCalculatedPose(offsetY: 58, rotateX: -2, scaleX: 0.98, scaleY: 0.98, zIndex: 30, shadowDarkness: 0.07, opacity: 1.0)
                case 1:
                    return DeckCardCalculatedPose(offsetY: 15, rotateX: -5.5, scaleX: 0.94, scaleY: 0.94, zIndex: 25, shadowDarkness: 0.20, opacity: 1.0)
                case 2:
                    return DeckCardCalculatedPose(offsetY: -20, rotateX: -8.5, scaleX: 0.90, scaleY: 0.90, zIndex: 20, shadowDarkness: 0.31, opacity: 1.0)
                case 3:
                    return DeckCardCalculatedPose(offsetY: -50, rotateX: -11.5, scaleX: 0.862, scaleY: 0.862, zIndex: 15, shadowDarkness: 0.41, opacity: 1.0)
                default:
                    return DeckCardCalculatedPose.resting(slot: slot)
                }
            }
        case .settle, .idle:
            return DeckCardCalculatedPose.resting(slot: slot)
        }
    }
}

// MARK: - Pointing hand cursor helper

extension View {
    fileprivate func deckPointingHand(_ enabled: Bool = true) -> some View {
        Group {
            if enabled {
                self.pointingHandCursor()
            } else {
                self
            }
        }
    }
}

// MARK: - Compact Square Action Button (28 × 28 pt)

public struct DeckSquareIconButton: View {
    public enum Role { case normal, destructive }

    let systemName: String
    let role: Role
    let currentTheme: AppTheme
    let tooltip: String
    let isActive: Bool
    let isCursorEnabled: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    public init(
        systemName: String,
        role: Role = .normal,
        currentTheme: AppTheme,
        tooltip: String,
        isActive: Bool = false,
        isCursorEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.role = role
        self.currentTheme = currentTheme
        self.tooltip = tooltip
        self.isActive = isActive
        self.isCursorEnabled = isCursorEnabled
        self.action = action
    }

    public var body: some View {
        let destructive = (role == .destructive)
        Button {
            TapticSoundAndHaptics.shared.playClick()
            action()
        } label: {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    destructive
                        ? (isHovered ? Color.red : currentTheme.secondaryText)
                        : (isActive ? Color.green : (isHovered ? currentTheme.accentColor : currentTheme.primaryText))
                )
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            destructive && isHovered
                                ? Color.red.opacity(0.14)
                                : currentTheme.primaryText.opacity(isHovered ? 0.12 : 0.06)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            destructive && isHovered ? Color.red.opacity(0.55) : currentTheme.borderColor,
                            lineWidth: 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltip)
        .deckPointingHand(isCursorEnabled)
    }
}

// MARK: - Snippet Deck Card View

/// Цельная карточка колоды: постоянная высота 250 pt, никогда не обрезается снизу и не убирает внутреннее текстовое поле!
public struct SnippetDeckCardView: View {
    public let snippet: QuickSnippetItem
    public let index: Int
    public let cardNumber: Int
    public let depth: Int
    public let total: Int
    public let pose: DeckCardCalculatedPose
    public let centeringShiftUp: CGFloat
    public let isBeingShuffled: Bool
    public let shuffleDirection: DeckScrollDirection
    public let shufflePhase: DeckAnimPhase
    public let customFinalOffsetY: CGFloat?
    public let titleText: String
    public let titleView: Text?
    public let isNumberHighlighted: Bool
    public let categoryName: String
    public let categoryIconName: String
    public let bodySegments: [SnippetDeckBodySegment]
    public let targetAppName: String
    public let targetAppIcon: NSImage?
    public let isPasted: Bool
    public let isPasteFailed: Bool
    public let isCopied: Bool
    public let currentTheme: AppTheme
    public let currentFont: AppFont

    public let onTogglePin: () -> Void
    public let onEdit: () -> Void
    public let onCopy: () -> Void
    public let onDelete: () -> Void
    public let onPaste: () -> Void
    public let onTapRearCard: () -> Void
    public let isCategoryFilterActive: Bool
    public let isContinuousScrolling: Bool
    public let onTapCategory: (() -> Void)?

    @State private var isPasteHovered: Bool = false
    @State private var isPinHovered: Bool = false
    @State private var isHoveringCategoryBadge: Bool = false
    @State private var isHeaderImagePopoverPresented: Bool = false

    public init(
        snippet: QuickSnippetItem,
        index: Int,
        cardNumber: Int? = nil,
        depth: Int,
        total: Int,
        pose: DeckCardCalculatedPose,
        centeringShiftUp: CGFloat? = nil,
        isBeingShuffled: Bool = false,
        shuffleDirection: DeckScrollDirection = .up,
        shufflePhase: DeckAnimPhase = .idle,
        customFinalOffsetY: CGFloat? = nil,
        titleText: String,
        titleView: Text? = nil,
        isNumberHighlighted: Bool = false,
        categoryName: String,
        categoryIconName: String,
        bodySegments: [SnippetDeckBodySegment],
        targetAppName: String,
        targetAppIcon: NSImage? = nil,
        isPasted: Bool,
        isPasteFailed: Bool = false,
        isCopied: Bool,
        currentTheme: AppTheme,
        currentFont: AppFont,
        isCategoryFilterActive: Bool = false,
        isContinuousScrolling: Bool = false,
        onTogglePin: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onPaste: @escaping () -> Void,
        onTapRearCard: @escaping () -> Void,
        onTapCategory: (() -> Void)? = nil
    ) {
        self.snippet = snippet
        self.index = index
        self.cardNumber = cardNumber ?? (index + 1)
        self.depth = depth
        self.total = total
        self.pose = pose
        self.centeringShiftUp = centeringShiftUp ?? SnippetDeckHelper.centeringShiftUp(forTotal: total)
        self.isBeingShuffled = isBeingShuffled
        self.shuffleDirection = shuffleDirection
        self.shufflePhase = shufflePhase
        self.customFinalOffsetY = customFinalOffsetY
        self.titleText = titleText
        self.titleView = titleView
        self.isNumberHighlighted = isNumberHighlighted
        self.categoryName = categoryName
        self.categoryIconName = categoryIconName
        self.bodySegments = bodySegments
        self.targetAppName = targetAppName
        self.targetAppIcon = targetAppIcon
        self.isPasted = isPasted
        self.isPasteFailed = isPasteFailed
        self.isCopied = isCopied
        self.currentTheme = currentTheme
        self.currentFont = currentFont
        self.isCategoryFilterActive = isCategoryFilterActive
        self.isContinuousScrolling = isContinuousScrolling
        self.onTogglePin = onTogglePin
        self.onEdit = onEdit
        self.onCopy = onCopy
        self.onDelete = onDelete
        self.onPaste = onPaste
        self.onTapRearCard = onTapRearCard
        self.onTapCategory = onTapCategory
    }

    private var previewBoxFill: Color {
        currentTheme.isLight ? Color.white : Color(red: 0.06, green: 0.07, blue: 0.09)
    }

    public var body: some View {
        let isFront = (depth == 0)
        let isLightTheme = currentTheme.isLight
        let continuousLiftY: CGFloat = (isContinuousScrolling && depth > 0) ? -4 : 0
        let continuousFanTilt: Double = (isContinuousScrolling && depth > 0) ? -4 : 0
        let finalOffsetY = (customFinalOffsetY ?? SnippetDeckHelper.finalOffsetY(
            baseOffsetY: pose.offsetY,
            centeringShiftUp: centeringShiftUp,
            total: total,
            isBeingShuffled: isBeingShuffled,
            phase: shufflePhase
        )) + continuousLiftY

        VStack(alignment: .leading, spacing: 8) {
            header
                .frame(height: 30)

            cardBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 11)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .background(currentTheme.cardColor)
        // Клик мышью по любой выступающей сзади карточке (depth > 0)
        .overlay(
            Group {
                if !isFront {
                    Color.clear
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture {
                            TapticSoundAndHaptics.shared.playClick()
                            onTapRearCard()
                        }
                }
            }
        )
        // Плавное затемнение яркости самой карточки без накладного оверлея
        .brightness(isLightTheme ? (-pose.shadowDarkness * 0.24) : (-pose.shadowDarkness * 0.14))
        // Строгий порядок 3D-модификаторов на карточке:
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isPasteFailed
                        ? Color.red
                        : (isFront
                           ? currentTheme.accentColor
                           : (isLightTheme ? currentTheme.borderColor.opacity(0.65) : Color.white.opacity(0.16))),
                    lineWidth: isPasteFailed ? 2.2 : (isFront ? 1.8 : 1.0)
                )
        )
        .shadow(
            color: isPasteFailed
                ? Color.red.opacity(0.45)
                : Color.black.opacity(isLightTheme ? (depth == 0 ? 0.20 : 0.18) : (depth == 0 ? 0.30 : 0.18)),
            radius: depth == 0 ? 20 : 10,
            x: 0,
            y: isLightTheme ? (depth == 0 ? 10 : -4) : (depth == 0 ? 12 : 5)
        )
        .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .top)
        .rotation3DEffect(
            .degrees(pose.rotateX + continuousFanTilt),
            axis: (x: 1, y: 0, z: 0),
            anchor: .top,
            perspective: 0.55
        )
        .offset(y: finalOffsetY)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: total)
        .opacity(pose.opacity)
        .zIndex(pose.zIndex)
    }

    private var categoryBadgeLabel: some View {
        let isHovered = (depth == 0 && isHoveringCategoryBadge)
        let fillOpacity: Double = isCategoryFilterActive
            ? (isHovered ? 0.36 : 0.24)
            : (isHovered ? 0.28 : 0.14)
        let strokeOpacity: Double = isHovered ? 0.90 : 0.45

        return HStack(spacing: 4) {
            Image(systemName: categoryIconName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 10, weight: .semibold))
            Text(categoryName)
                .font(currentFont.font(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(currentTheme.accentColor)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(currentTheme.accentColor.opacity(fillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(currentTheme.accentColor.opacity(strokeOpacity), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var headerImage: NSImage? {
        guard let path = snippet.imagePath, !path.isEmpty else { return nil }
        return SnippetInlineContent.image(forName: path)
    }

    // MARK: Header (монолитная структура на ВСЕХ карточках колоды без ветвления if depth == 0)
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            // Слева: булавка, жирный заголовок + капсула категории (вплотную к названию)
            HStack(spacing: 8) {
                pinView

                HStack(spacing: 8) {
                    (titleView ?? Text(titleText))
                        .font(currentFont.font(size: 13.5, weight: .bold))
                        .foregroundStyle(currentTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(depth == 0 && !titleText.isEmpty ? titleText : "")

                    Button {
                        TapticSoundAndHaptics.shared.playClick()
                        onTapCategory?()
                    } label: {
                        categoryBadgeLabel
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        guard depth == 0 else {
                            if isHoveringCategoryBadge { isHoveringCategoryBadge = false }
                            return
                        }
                        withAnimation(.easeInOut(duration: 0.14)) {
                            isHoveringCategoryBadge = hovering
                        }
                    }
                    .onChange(of: depth) { _, newDepth in
                        if newDepth != 0 && isHoveringCategoryBadge {
                            isHoveringCategoryBadge = false
                        }
                    }
                    .allowsHitTesting(depth == 0 && onTapCategory != nil)
                    .help(isCategoryFilterActive
                          ? tr("Показать все категории", "Show all categories")
                          : tr("Перейти в категорию «\(categoryName)»", "Filter by category \"\(categoryName)\""))
                    .deckPointingHand(depth == 0 && onTapCategory != nil)
                }
                .frame(maxWidth: 330, alignment: .leading)
            }
            .allowsHitTesting(depth == 0)

            Spacer(minLength: 16)

            // Справа: макет фото (если есть) + 4 кнопки действий + сквозной номер
            HStack(spacing: 6) {
                if let img = headerImage {
                    Button {
                        TapticSoundAndHaptics.shared.playClick()
                        isHeaderImagePopoverPresented.toggle()
                    } label: {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(depth == 0)
                    .help(tr("Нажмите, чтобы просмотреть картинку", "Click to preview image"))
                    .deckPointingHand(depth == 0)
                    .popover(isPresented: $isHeaderImagePopoverPresented, arrowEdge: .bottom) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 320, maxHeight: 240)
                            .padding(10)
                    }
                }

                frontControls
                    .allowsHitTesting(depth == 0)

                Text("\(cardNumber)")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(isNumberHighlighted ? currentTheme.accentColor : currentTheme.secondaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 26, alignment: .center)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                isNumberHighlighted
                                    ? currentTheme.accentColor.opacity(0.22)
                                    : (currentTheme.isLight ? Color.black.opacity(0.05) : Color.primary.opacity(0.06))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                isNumberHighlighted ? currentTheme.accentColor : currentTheme.borderColor.opacity(0.65),
                                lineWidth: 1
                            )
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private var pinView: some View {
        Button {
            TapticSoundAndHaptics.shared.playClick()
            onTogglePin()
        } label: {
            Image(systemName: snippet.isPinned ? "pin.fill" : "pin")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(
                    snippet.isPinned
                        ? Color.orange
                        : (isPinHovered ? currentTheme.accentColor : currentTheme.secondaryText.opacity(0.55))
                )
                .rotationEffect(.degrees(45))
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isPinHovered = $0 }
        .allowsHitTesting(depth == 0)
        .help(snippet.isPinned
              ? tr("Открепить фрагмент", "Unpin snippet")
              : tr("Закрепить фрагмент", "Pin snippet"))
        .deckPointingHand(depth == 0)
    }

    private var frontControls: some View {
        HStack(spacing: 6) {
            DeckSquareIconButton(
                systemName: "pencil",
                role: .normal,
                currentTheme: currentTheme,
                tooltip: tr("Редактировать фрагмент", "Edit snippet"),
                isActive: false,
                isCursorEnabled: depth == 0,
                action: onEdit
            )

            DeckSquareIconButton(
                systemName: isCopied ? "checkmark" : "doc.on.doc",
                role: .normal,
                currentTheme: currentTheme,
                tooltip: tr("Скопировать фрагмент в буфер обмена", "Copy snippet to clipboard"),
                isActive: isCopied,
                isCursorEnabled: depth == 0,
                action: onCopy
            )

            DeckSquareIconButton(
                systemName: "trash",
                role: .destructive,
                currentTheme: currentTheme,
                tooltip: tr("Удалить фрагмент", "Delete snippet"),
                isActive: false,
                isCursorEnabled: depth == 0,
                action: onDelete
            )

            Button {
                TapticSoundAndHaptics.shared.playClick()
                onPaste()
            } label: {
                HStack(spacing: 5) {
                    if isPasted && !isPasteFailed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text(tr("Вставлено", "Pasted"))
                            .font(currentFont.font(size: 12, weight: .bold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        DoubleClickCursorIcon(size: 14, color: .white)
                            .frame(width: 14, height: 14)
                        Text(targetAppIcon != nil ? tr("Вставить в", "Paste to") : tr("Вставить", "Paste"))
                            .font(currentFont.font(size: 12, weight: .bold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if let icon = targetAppIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                    }
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isPasteFailed ? Color.red : currentTheme.accentColor.opacity(isPasteHovered ? 0.88 : 1.0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isPasteHovered = $0 }
            .help(tr("Вставить фрагмент в \(targetAppName)", "Paste snippet to \(targetAppName)"))
            .deckPointingHand(depth == 0)
        }
    }

    // MARK: Card Body (фиксированная высота 155 pt — никогда не удаляется!)
    private var isImageOnlyBody: Bool {
        bodySegments.count == 1 && bodySegments[0].image != nil && bodySegments[0].text == nil
    }

    private var cardBody: some View {
        let isFront = (depth == 0)

        return Group {
            if isImageOnlyBody, let img = bodySegments.first?.image {
                VStack {
                    Spacer(minLength: 0)
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: isFront ? 165 : 120)
                        .clipShape(RoundedRectangle(cornerRadius: isFront ? 8 : 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: isFront ? 8 : 6, style: .continuous)
                                .strokeBorder(currentTheme.borderColor.opacity(isFront ? 0.6 : 0), lineWidth: 1)
                        )
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .allowsHitTesting(isFront)
            } else if isFront {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(bodySegments) { seg in
                            segmentView(seg, imageMaxHeight: 165, cornerRadius: 8, bordered: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .padding(.top, 4)
                .padding(.trailing, 2)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bodySegments) { seg in
                        segmentView(seg, imageMaxHeight: 120, cornerRadius: 6, bordered: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .allowsHitTesting(false)
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(previewBoxFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(currentTheme.borderColor.opacity(0.8), lineWidth: 1)
        )
    }
}

extension SnippetDeckCardView {
    @ViewBuilder
    fileprivate func segmentView(_ seg: SnippetDeckBodySegment, imageMaxHeight: CGFloat, cornerRadius: CGFloat, bordered: Bool) -> some View {
        if let text = seg.text {
            if depth == 0 {
                text
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                text
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if let image = seg.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: imageMaxHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(currentTheme.borderColor.opacity(bordered ? 0.6 : 0), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Блок содержимого карточки колоды: либо готовый Text, либо картинка (порядок как в редакторе)
public struct SnippetDeckBodySegment: Identifiable {
    public let id: Int
    public let text: Text?
    public let image: NSImage?

    public init(id: Int, text: Text) {
        self.id = id
        self.text = text
        self.image = nil
    }

    public init(id: Int, image: NSImage) {
        self.id = id
        self.text = nil
        self.image = image
    }
}

// MARK: - Deck Control Rail (▲ / track / counter / ▼)

public struct SnippetDeckControlRail: View {
    public let total: Int
    public let activeIndex: Int
    public let currentTheme: AppTheme
    public let onUp: () -> Void
    public let onDown: () -> Void
    public let onSelectIndex: (Int) -> Void
    public let onContinuousStart: ((DeckScrollDirection) -> Void)?
    public let onContinuousEnd: (() -> Void)?
    public let onScrubberChange: ((Int) -> Void)?
    public let onScrubberEnd: (() -> Void)?

    @State private var capsuleHeight: CGFloat = 1

    public init(
        total: Int,
        activeIndex: Int,
        currentTheme: AppTheme,
        onUp: @escaping () -> Void,
        onDown: @escaping () -> Void,
        onSelectIndex: @escaping (Int) -> Void,
        onContinuousStart: ((DeckScrollDirection) -> Void)? = nil,
        onContinuousEnd: (() -> Void)? = nil,
        onScrubberChange: ((Int) -> Void)? = nil,
        onScrubberEnd: (() -> Void)? = nil
    ) {
        self.total = total
        self.activeIndex = activeIndex
        self.currentTheme = currentTheme
        self.onUp = onUp
        self.onDown = onDown
        self.onSelectIndex = onSelectIndex
        self.onContinuousStart = onContinuousStart
        self.onContinuousEnd = onContinuousEnd
        self.onScrubberChange = onScrubberChange
        self.onScrubberEnd = onScrubberEnd
    }

    private var visibleDotIndices: [Int] {
        SnippetDeckHelper.visibleDotIndices(total: total, activeIndex: activeIndex, maxVisibleDots: 10)
    }

    public var body: some View {
        VStack(spacing: 10) {
            DeckChevronButton(
                systemName: "chevron.up",
                currentTheme: currentTheme,
                tooltip: tr("Предыдущий фрагмент (↑)", "Previous snippet (↑)"),
                action: onUp,
                onHoldStart: { onContinuousStart?(.up) },
                onHoldEnd: { onContinuousEnd?() }
            )

            VStack(spacing: 6) {
                ForEach(visibleDotIndices, id: \.self) { i in
                    DeckTrackDot(isActive: i == activeIndex, currentTheme: currentTheme) {
                        onSelectIndex(i)
                    }
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .background(
                ZStack {
                    currentTheme.cardBackground
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { capsuleHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, newH in
                                capsuleHeight = newH
                            }
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(currentTheme.borderColor, lineWidth: 1))
            .contentShape(Capsule())
            .deckPointingHand()
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard total > 1 else { return }
                        let targetIndex: Int
                        if total > visibleDotIndices.count && !visibleDotIndices.isEmpty {
                            let h = max(capsuleHeight, 1)
                            let ratio = min(max(value.location.y / h, 0.0), 1.0)
                            targetIndex = Int(round(ratio * Double(total - 1)))
                        } else {
                            targetIndex = SnippetDeckHelper.scrubberTargetIndex(
                                locationY: value.location.y,
                                capsuleHeight: capsuleHeight,
                                total: total
                            )
                        }
                        if targetIndex != activeIndex {
                            if let onScrubberChange {
                                onScrubberChange(targetIndex)
                            } else {
                                onSelectIndex(targetIndex)
                            }
                        }
                    }
                    .onEnded { _ in
                        onScrubberEnd?()
                    }
            )

            DeckChevronButton(
                systemName: "chevron.down",
                currentTheme: currentTheme,
                tooltip: tr("Следующий фрагмент (↓)", "Next snippet (↓)"),
                action: onDown,
                onHoldStart: { onContinuousStart?(.down) },
                onHoldEnd: { onContinuousEnd?() }
            )
        }
        .frame(width: 44)
    }
}

private struct DeckChevronButton: View {
    let systemName: String
    let currentTheme: AppTheme
    let tooltip: String
    let action: () -> Void
    var onHoldStart: (() -> Void)? = nil
    var onHoldEnd: (() -> Void)? = nil

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    @State private var holdWorkItem: DispatchWorkItem?
    @State private var didStartContinuousHold: Bool = false

    private func stopHoldTimer() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }

    var body: some View {
        Button {
            if !didStartContinuousHold {
                TapticSoundAndHaptics.shared.playClick()
                action()
            }
            didStartContinuousHold = false
        } label: {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isHovered ? currentTheme.accentColor : currentTheme.primaryText)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(currentTheme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isHovered ? currentTheme.accentColor.opacity(0.6) : currentTheme.borderColor, lineWidth: 1)
                )
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .deckPointingHand()
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    didStartContinuousHold = false
                    let work = DispatchWorkItem {
                        didStartContinuousHold = true
                        onHoldStart?()
                    }
                    holdWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
                }
                .onEnded { _ in
                    isPressed = false
                    let held = didStartContinuousHold
                    stopHoldTimer()
                    if held {
                        onHoldEnd?()
                    }
                }
        )
        .onDisappear {
            stopHoldTimer()
            if didStartContinuousHold {
                didStartContinuousHold = false
                onHoldEnd?()
            }
        }
        .help(tooltip)
    }
}

private struct DeckTrackDot: View {
    let isActive: Bool
    let currentTheme: AppTheme
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            TapticSoundAndHaptics.shared.playClick()
            action()
        } label: {
            Capsule()
                .fill(isActive
                      ? currentTheme.accentColor
                      : currentTheme.secondaryText.opacity(isHovered ? 0.65 : 0.35))
                .frame(width: 8, height: isActive ? 18 : 8)
                .frame(width: 16, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .deckPointingHand()
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActive)
    }
}

// MARK: - Scroll Wheel Catcher (Дебаунс 0.75 сек, 1 взмах = 1 карточка)

public struct DeckScrollWheelCatcher: NSViewRepresentable {
    public var isEnabled: Bool
    public var frontOffsetY: CGFloat
    public var onStep: (DeckScrollDirection) -> Void

    public init(isEnabled: Bool, frontOffsetY: CGFloat = 82, onStep: @escaping (DeckScrollDirection) -> Void) {
        self.isEnabled = isEnabled
        self.frontOffsetY = frontOffsetY
        self.onStep = onStep
    }

    public nonisolated static func frontTextRect(in bounds: NSRect, frontOffsetY: CGFloat) -> NSRect {
        let centerY = bounds.height / 2
        let cardTop = centerY + frontOffsetY - 125
        let cardBottom = cardTop + 250
        let bodyTop = cardTop + 49
        return NSRect(
            x: 0,
            y: bodyTop,
            width: max(0, bounds.width),
            height: max(0, cardBottom - bodyTop)
        )
    }

    public nonisolated static func frontTextRect(in bounds: NSRect, visibleCardCount: Int) -> NSRect {
        let frontOffsetY = DeckCardCalculatedPose.resting(slot: 0).offsetY + SnippetDeckHelper.centeringShiftUp(forTotal: visibleCardCount)
        return frontTextRect(in: bounds, frontOffsetY: frontOffsetY)
    }

    public func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.isEnabled = isEnabled
        view.frontOffsetY = frontOffsetY
        view.onStep = onStep
        return view
    }

    public func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.frontOffsetY = frontOffsetY
        nsView.onStep = onStep
    }

    public static func dismantleNSView(_ nsView: CatcherView, coordinator: ()) {
        nsView.removeMonitor()
    }

    public final class CatcherView: NSView {
        var isEnabled: Bool = true
        var frontOffsetY: CGFloat = 82
        var onStep: ((DeckScrollDirection) -> Void)?

        private var monitor: Any?
        private var lastStepTime: Date = .distantPast
        private var hasStepped: Bool = false

        public override var isFlipped: Bool { true }

        public override func hitTest(_ point: NSPoint) -> NSView? { nil }

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        /// Зона текста передней карточки (прокручивается как обычный ScrollView)
        private var frontTextRect: NSRect {
            DeckScrollWheelCatcher.frontTextRect(in: bounds, frontOffsetY: frontOffsetY)
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled, let window, event.window === window else { return event }

            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return event }

            if frontTextRect.contains(point) { return event }

            if event.momentumPhase != [] { return nil }

            if event.phase == .ended || event.phase == .cancelled {
                hasStepped = false
                return nil
            }
            if event.phase == .began || event.phase == .mayBegin {
                hasStepped = false
            }

            let dy = event.scrollingDeltaY
            guard abs(dy) > 0.5 else { return nil }

            let isTrackpadGesture = (event.phase != [])
            if isTrackpadGesture && hasStepped { return nil }

            let now = Date()
            guard now.timeIntervalSince(lastStepTime) >= 0.75 else { return nil }
            lastStepTime = now
            hasStepped = true

            onStep?(dy < 0 ? .up : .down)
            return nil
        }
    }
}
