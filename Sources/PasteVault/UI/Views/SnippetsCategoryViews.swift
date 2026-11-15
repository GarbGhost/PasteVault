import SwiftUI
import AppKit

/// Однострочное текстовое поле с чётким плейсхолдером, который плавно скрывается при постановке курсора (focus).
public struct FocusAwareTextField: View {
    public let placeholder: String
    @Binding public var text: String
    public let font: Font
    public let textColor: Color
    public let placeholderColor: Color
    public var externalFocus: FocusState<Bool>.Binding?
    public var onSubmit: (() -> Void)?

    @FocusState private var internalFocus: Bool

    public init(
        placeholder: String,
        text: Binding<String>,
        font: Font,
        textColor: Color,
        placeholderColor: Color,
        externalFocus: FocusState<Bool>.Binding? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.externalFocus = externalFocus
        self.onSubmit = onSubmit
    }

    private var isFocused: Bool {
        externalFocus?.wrappedValue ?? internalFocus
    }

    public var body: some View {
        Group {
            if let externalFocus {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .focused(externalFocus)
            } else {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .focused($internalFocus)
            }
        }
        .font(font)
        .foregroundStyle(textColor)
        .overlay(alignment: .leading) {
            Text(placeholder)
                .font(font)
                .foregroundStyle(placeholderColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .allowsHitTesting(false)
                .opacity(text.isEmpty && !isFocused ? 1 : 0)
                .animation(.easeOut(duration: 0.14), value: isFocused)
                .animation(.easeOut(duration: 0.14), value: text.isEmpty)
        }
        .onSubmit {
            onSubmit?()
        }
    }
}

/// Ограничивает ввод названия категории максимум 2 словами и 20 символами, удаляя лишние пробелы.
public func sanitizeCategoryNameInput(_ raw: String) -> String {
    // 1. Убираем ведущие пробелы в начале строки
    var s = raw
    while s.first?.isWhitespace == true {
        s.removeFirst()
    }
    // Заменяем переводы строк и табуляции на одиночные пробелы
    s = s.replacingOccurrences(of: "[\t\r\n]", with: " ", options: .regularExpression)
    // Заменяем множественные пробелы на один пробел
    while s.contains("  ") {
        s = s.replacingOccurrences(of: "  ", with: " ")
    }
    // 2. Разрешаем максимум 2 слова (то есть максимум один пробел после первого слова)
    let parts = s.components(separatedBy: " ")
    if parts.count > 2 {
        s = parts.prefix(2).joined(separator: " ")
    }
    // 3. Ограничиваем максимальную длину названия 20 символами
    if s.count > 20 {
        s = String(s.prefix(20))
    }
    return s
}

public enum SnippetCategoryValidator {
    public static let reservedNamesLowercased: Set<String> = [
        "все",
        "все категории",
        "all",
        "all categories",
        "нет категорий",
        "no categories",
        "uncategorized"
    ]

    public static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    public static func isReservedName(_ raw: String) -> Bool {
        reservedNamesLowercased.contains(normalizedKey(raw))
    }

    public static func validateCandidate(
        _ candidate: String,
        existingCategories: [SnippetCategoryRecord],
        excludingCategoryId: UUID? = nil
    ) -> (isValid: Bool, isReserved: Bool, isDuplicate: Bool) {
        let key = normalizedKey(candidate)
        guard !key.isEmpty else { return (false, false, false) }
        if reservedNamesLowercased.contains(key) {
            return (false, true, false)
        }
        let dup = existingCategories.contains {
            $0.id != excludingCategoryId && normalizedKey($0.name) == key
        }
        return (!dup, false, dup)
    }
}

// MARK: - 25-Icon Palette Grid (5 × 5)
public struct SnippetCategoryIconBubble: View {
    public let iconName: String
    public let isSelected: Bool
    public let currentTheme: AppTheme
    public let onSelect: () -> Void

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false

    public init(iconName: String, isSelected: Bool, currentTheme: AppTheme, onSelect: @escaping () -> Void) {
        self.iconName = iconName
        self.isSelected = isSelected
        self.currentTheme = currentTheme
        self.onSelect = onSelect
    }

    public var body: some View {
        Button {
            TapticSoundAndHaptics.shared.playClick()
            onSelect()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? currentTheme.accentColor : (isHovered ? currentTheme.accentColor.opacity(0.18) : currentTheme.primaryText.opacity(0.06)))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? currentTheme.accentColor : (isHovered ? currentTheme.accentColor.opacity(0.7) : currentTheme.borderColor.opacity(0.6)), lineWidth: 1)

                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : (isHovered ? currentTheme.accentColor : currentTheme.primaryText))
            }
            .frame(width: 28, height: 28)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .opacity(isPressed ? 0.85 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointingHandCursor()
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

public struct SnippetCategoryIconPicker: View {
    public let currentTheme: AppTheme
    public let selectedIcon: String
    public let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 5), count: 5)

    public init(currentTheme: AppTheme, selectedIcon: String, onSelect: @escaping (String) -> Void) {
        self.currentTheme = currentTheme
        self.selectedIcon = selectedIcon
        self.onSelect = onSelect
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(SnippetCategoryRecord.availableIcons, id: \.self) { iconName in
                SnippetCategoryIconBubble(
                    iconName: iconName,
                    isSelected: (iconName == selectedIcon),
                    currentTheme: currentTheme
                ) {
                    onSelect(iconName)
                }
            }
        }
        .padding(8)
        .background(currentTheme.isLight ? Color.white : currentTheme.cardColor)
    }
}

// MARK: - Dedicated Category Row View (Encapsulated Hover, Click, Edit)
struct SnippetCategoryRowItemView: View {
    let category: SnippetCategoryRecord
    let existingCategories: [SnippetCategoryRecord]
    let isSelected: Bool
    let snippetCount: Int
    let currentTheme: AppTheme
    let currentFont: AppFont
    let language: AppLanguage
    let isEditing: Bool
    let onSelect: () -> Void
    let onStartEdit: () -> Void
    let onDeleteRequest: () -> Void
    let onCommitEdit: (String, String) -> Void
    let onCancelEdit: () -> Void

    @State private var editingName: String = ""
    @State private var editingIcon: String = "doc.text.fill"
    @State private var isIconPickerOpen: Bool = false
    @State private var renameInvalidWarning: Bool = false
    @State private var renameShakeOffset: CGFloat = 0

    @State private var isRowHovered: Bool = false
    @State private var isRowPressed: Bool = false

    @State private var isPencilHovered: Bool = false
    @State private var isPencilPressed: Bool = false

    @State private var isTrashHovered: Bool = false
    @State private var isTrashPressed: Bool = false

    @State private var isIconBtnHovered: Bool = false
    @State private var isIconBtnPressed: Bool = false

    @State private var isCheckHovered: Bool = false
    @State private var isCheckPressed: Bool = false

    @State private var isCancelHovered: Bool = false
    @State private var isCancelPressed: Bool = false

    var body: some View {
        if isEditing {
            // Режим редактирования строки категории
            HStack(spacing: 6) {
                // Кнопка смены иконки с открытием 25-иконочной палитры
                Button {
                    isIconPickerOpen.toggle()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: editingIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(currentTheme.accentColor)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(currentTheme.secondaryText)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 26)
                    .background(isIconBtnHovered ? currentTheme.accentColor.opacity(0.16) : currentTheme.primaryText.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isIconBtnHovered ? currentTheme.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                    .scaleEffect(isIconBtnPressed ? 0.95 : 1.0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isIconBtnHovered = $0 }
                .pointingHandCursor()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isIconBtnPressed = true }
                        .onEnded { _ in isIconBtnPressed = false }
                )
                .popover(isPresented: $isIconPickerOpen, arrowEdge: .leading) {
                    SnippetCategoryIconPicker(currentTheme: currentTheme, selectedIcon: editingIcon) { chosen in
                        editingIcon = chosen
                        isIconPickerOpen = false
                    }
                }

                FocusAwareTextField(
                    placeholder: language == .ru ? "Название" : "Name",
                    text: $editingName,
                    font: currentFont.font(size: 12, weight: .medium),
                    textColor: currentTheme.primaryText,
                    placeholderColor: currentTheme.secondaryText.opacity(0.78),
                    onSubmit: { commit() }
                )
                .padding(.horizontal, 6)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(currentTheme.isLight ? Color.white : currentTheme.primaryText.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(renameInvalidWarning ? Color.red.opacity(0.85) : currentTheme.accentColor.opacity(0.5), lineWidth: renameInvalidWarning ? 1.5 : 1)
                )
                .offset(x: renameShakeOffset)
                .onChange(of: editingName) { _, newVal in
                    let sanitized = sanitizeCategoryNameInput(newVal)
                    if sanitized != newVal {
                        editingName = sanitized
                    }
                    if renameInvalidWarning {
                        renameInvalidWarning = false
                    }
                }

                // Кнопка подтверждения [ ✓ ]
                Button {
                    commit()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 26, height: 26)
                        .background(isCheckHovered ? currentTheme.accentColor.opacity(0.85) : currentTheme.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .scaleEffect(isCheckPressed ? 0.92 : 1.0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isCheckHovered = $0 }
                .pointingHandCursor()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isCheckPressed = true }
                        .onEnded { _ in isCheckPressed = false }
                )

                // Кнопка отмены [ ✕ ]
                Button {
                    TapticSoundAndHaptics.shared.playClick()
                    onCancelEdit()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isCancelHovered ? currentTheme.primaryText : currentTheme.secondaryText)
                        .frame(width: 22, height: 26)
                        .background(isCancelHovered ? currentTheme.primaryText.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .scaleEffect(isCancelPressed ? 0.92 : 1.0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isCancelHovered = $0 }
                .pointingHandCursor()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isCancelPressed = true }
                        .onEnded { _ in isCancelPressed = false }
                )
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(currentTheme.primaryText.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onAppear {
                editingName = category.name
                editingIcon = category.iconName
            }
        } else {
            // Обычный вид строки категории
            HStack(spacing: 7) {
                // Вся левая часть строки кликабельна для выбора категории
                Button {
                    TapticSoundAndHaptics.shared.playClick()
                    onSelect()
                } label: {
                    HStack(spacing: 7) {
                        // Индикатор выбора (акцентный чекбокс)
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isSelected ? currentTheme.accentColor : currentTheme.primaryText.opacity(0.08))
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(isSelected ? currentTheme.accentColor : currentTheme.borderColor.opacity(0.8), lineWidth: 1)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                        }
                        .frame(width: 15, height: 15)

                        // Векторная иконка категории
                        Image(systemName: category.iconName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(currentTheme.accentColor)
                            .frame(width: 16)

                        // Название
                        Text(MainPanelView.localizedCategoryDisplayName(category.name, isEnglish: language == .en))
                            .font(currentFont.font(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(currentTheme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        // Счётчик фрагментов в папке
                        Text("\(snippetCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(currentTheme.primaryText.opacity(0.07))
                            .foregroundStyle(currentTheme.secondaryText)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .scaleEffect(isRowPressed ? 0.98 : 1.0)
                .onHover { isRowHovered = $0 }
                .pointingHandCursor()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isRowPressed = true }
                        .onEnded { _ in isRowPressed = false }
                )

                // Кнопка редактирования ✎
                Button {
                    TapticSoundAndHaptics.shared.playClick()
                    onStartEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isPencilHovered ? currentTheme.accentColor : currentTheme.secondaryText)
                        .frame(width: 20, height: 24)
                        .background(isPencilHovered ? currentTheme.accentColor.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .scaleEffect(isPencilPressed ? 0.92 : 1.0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isPencilHovered = $0 }
                .pointingHandCursor()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isPencilPressed = true }
                        .onEnded { _ in isPencilPressed = false }
                )
                .help(language == .ru ? "Редактировать папку" : "Edit folder")

                // Кнопка удаления 🗑️
                Button {
                    TapticSoundAndHaptics.shared.playClick()
                    onDeleteRequest()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(isTrashHovered ? 1.0 : 0.85))
                        .frame(width: 20, height: 24)
                        .background(isTrashHovered ? Color.red.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .scaleEffect(isTrashPressed ? 0.92 : 1.0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isTrashHovered = $0 }
                .pointingHandCursor()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isTrashPressed = true }
                        .onEnded { _ in isTrashPressed = false }
                )
                .help(language == .ru ? "Удалить папку" : "Delete folder")
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(isSelected ? currentTheme.accentColor.opacity(0.12) : (isRowHovered ? currentTheme.primaryText.opacity(0.06) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func commit() {
        let sanitized = sanitizeCategoryNameInput(editingName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        let validation = SnippetCategoryValidator.validateCandidate(
            sanitized,
            existingCategories: existingCategories,
            excludingCategoryId: category.id
        )
        guard validation.isValid else {
            withAnimation(.easeOut(duration: 0.14)) {
                renameInvalidWarning = true
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            NSSound.beep()
            let offsets: [(CGFloat, TimeInterval)] = [(6, 0.0), (-6, 0.05), (4, 0.10), (-4, 0.15), (0, 0.20)]
            for (value, delay) in offsets {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.linear(duration: 0.04)) {
                        renameShakeOffset = value
                    }
                }
            }
            return
        }
        renameInvalidWarning = false
        TapticSoundAndHaptics.shared.playClick()
        onCommitEdit(sanitized, editingIcon)
    }
}

// MARK: - Category Dropdown Menu
public struct SnippetCategoryDropdownMenu: View {
    public let isFilterMode: Bool
    public let categories: [SnippetCategoryRecord]
    public let selectedCategoryName: String
    public let snippets: [QuickSnippetItem]
    public let currentTheme: AppTheme
    public let currentFont: AppFont
    public let language: AppLanguage
    public let onSelectCategory: (String) -> Void
    public let onCreateCategory: (String, String) -> Void
    public let onUpdateCategory: (UUID, String, String) -> Void
    public let onDeleteCategoryRequest: (SnippetCategoryRecord) -> Void
    public let onDismiss: () -> Void

    @State private var editingCategoryId: UUID? = nil

    @State private var newCategoryName: String = ""
    @State private var newCategoryIcon: String = "doc.text.fill"
    @State private var isIconPickerOpenForNew: Bool = false
    @State private var duplicateCategoryWarning: Bool = false
    @State private var invalidCategoryIsReserved: Bool = false
    @State private var duplicateShakeOffset: CGFloat = 0

    @State private var isHoveredAll: Bool = false
    @State private var isPressedAll: Bool = false

    @State private var isNewIconBtnHovered: Bool = false
    @State private var isNewIconBtnPressed: Bool = false

    @State private var isNewPlusBtnHovered: Bool = false
    @State private var isNewPlusBtnPressed: Bool = false

    public init(
        isFilterMode: Bool,
        categories: [SnippetCategoryRecord],
        selectedCategoryName: String,
        snippets: [QuickSnippetItem],
        currentTheme: AppTheme,
        currentFont: AppFont,
        language: AppLanguage,
        onSelectCategory: @escaping (String) -> Void,
        onCreateCategory: @escaping (String, String) -> Void,
        onUpdateCategory: @escaping (UUID, String, String) -> Void,
        onDeleteCategoryRequest: @escaping (SnippetCategoryRecord) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.isFilterMode = isFilterMode
        self.categories = categories
        self.selectedCategoryName = selectedCategoryName
        self.snippets = snippets
        self.currentTheme = currentTheme
        self.currentFont = currentFont
        self.language = language
        self.onSelectCategory = onSelectCategory
        self.onCreateCategory = onCreateCategory
        self.onUpdateCategory = onUpdateCategory
        self.onDeleteCategoryRequest = onDeleteCategoryRequest
        self.onDismiss = onDismiss
    }

    private func snippetCount(for categoryName: String) -> Int {
        snippets.filter { $0.category.localizedCaseInsensitiveCompare(categoryName) == .orderedSame }.count
    }

    private var isAllSelected: Bool {
        selectedCategoryName.isEmpty || selectedCategoryName == "Все" || selectedCategoryName == "All"
    }

    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Верхний пункт «Все категории» (ТОЛЬКО для режима фильтра)
            if isFilterMode {
                allCategoriesRow
                Divider()
                    .background(currentTheme.borderColor)
            }

            // 2. Список пользовательских категорий (скрывается, если categories.isEmpty)
            if !categories.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(categories) { category in
                            SnippetCategoryRowItemView(
                                category: category,
                                existingCategories: categories,
                                isSelected: (selectedCategoryName.localizedCaseInsensitiveCompare(category.name) == .orderedSame),
                                snippetCount: snippetCount(for: category.name),
                                currentTheme: currentTheme,
                                currentFont: currentFont,
                                language: language,
                                isEditing: (editingCategoryId == category.id),
                                onSelect: {
                                    onSelectCategory(category.name)
                                    onDismiss()
                                    dismiss()
                                },
                                onStartEdit: {
                                    editingCategoryId = category.id
                                },
                                onDeleteRequest: {
                                    onDeleteCategoryRequest(category)
                                },
                                onCommitEdit: { name, icon in
                                    onUpdateCategory(category.id, name, icon)
                                    editingCategoryId = nil
                                },
                                onCancelEdit: {
                                    editingCategoryId = nil
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
                .frame(maxHeight: 170)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.08),
                            .init(color: .black, location: 0.90),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Divider()
                    .background(currentTheme.borderColor)
            }

            // 3. Нижняя строка создания новой категории
            newCategoryRow
        }
        .frame(width: 280)
        .background(currentTheme.isLight ? Color.white : currentTheme.cardColor)
        .onDisappear {
            duplicateCategoryWarning = false
        }
    }

    // MARK: - All Categories Row
    private var allCategoriesRow: some View {
        Button {
            TapticSoundAndHaptics.shared.playClick()
            onSelectCategory(language == .en ? "All" : "Все")
            onDismiss()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                // Уникальная несменяемая иконка сетки square.grid.2x2.fill (без чекбокса!)
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(currentTheme.accentColor)
                    .frame(width: 18)

                Text(language == .ru ? "Все категории" : "All Categories")
                    .font(currentFont.font(size: 12.5, weight: isAllSelected ? .bold : .medium))
                    .foregroundStyle(currentTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                // Бейдж показывает количество самих категорий внутри
                Text("\(categories.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(currentTheme.primaryText.opacity(0.08))
                    .foregroundStyle(currentTheme.secondaryText)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(isAllSelected ? currentTheme.accentColor.opacity(0.14) : (isHoveredAll ? currentTheme.primaryText.opacity(0.08) : Color.clear))
            .scaleEffect(isPressedAll ? 0.98 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveredAll = $0 }
        .pointingHandCursor()
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressedAll = true }
                .onEnded { _ in isPressedAll = false }
        )
    }

    // MARK: - New Category Row
    private var newCategoryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Кнопка выбора иконки для новой категории с открытием палитры ВЛЕВО
                Button {
                    isIconPickerOpenForNew.toggle()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: newCategoryIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(currentTheme.accentColor)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(currentTheme.secondaryText)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 26)
                    .background(isNewIconBtnHovered ? currentTheme.accentColor.opacity(0.16) : currentTheme.primaryText.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isNewIconBtnHovered ? currentTheme.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                    .scaleEffect(isNewIconBtnPressed ? 0.95 : 1.0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isNewIconBtnHovered = $0 }
                .pointingHandCursor()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isNewIconBtnPressed = true }
                        .onEnded { _ in isNewIconBtnPressed = false }
                )
                .popover(isPresented: $isIconPickerOpenForNew, arrowEdge: .leading) {
                    SnippetCategoryIconPicker(currentTheme: currentTheme, selectedIcon: newCategoryIcon) { chosen in
                        newCategoryIcon = chosen
                        isIconPickerOpenForNew = false
                    }
                }

                FocusAwareTextField(
                    placeholder: language == .ru ? "Новая категория" : "New category",
                    text: $newCategoryName,
                    font: currentFont.font(size: 12, weight: .medium),
                    textColor: currentTheme.primaryText,
                    placeholderColor: currentTheme.secondaryText.opacity(0.78),
                    onSubmit: { submitNewCategory() }
                )
                .padding(.horizontal, 7)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(currentTheme.isLight ? Color.white : currentTheme.primaryText.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(duplicateCategoryWarning ? Color.red.opacity(0.85) : currentTheme.borderColor, lineWidth: duplicateCategoryWarning ? 1.5 : 1)
                )
                .offset(x: duplicateShakeOffset)
                .onChange(of: newCategoryName) { _, newVal in
                    let sanitized = sanitizeCategoryNameInput(newVal)
                    if sanitized != newVal {
                        newCategoryName = sanitized
                    }
                    if duplicateCategoryWarning {
                        withAnimation(.easeOut(duration: 0.14)) {
                            duplicateCategoryWarning = false
                        }
                    }
                }

                Button {
                    submitNewCategory()
                } label: {
                    let isEmpty = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 26, height: 26)
                        .background(isEmpty ? currentTheme.secondaryText.opacity(0.4) : (isNewPlusBtnHovered ? currentTheme.accentColor.opacity(0.85) : currentTheme.accentColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .scaleEffect(isNewPlusBtnPressed && !isEmpty ? 0.92 : 1.0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .onHover { isNewPlusBtnHovered = $0 }
                .pointingHandCursor()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isNewPlusBtnPressed = true }
                        .onEnded { _ in isNewPlusBtnPressed = false }
                )
            }

            if duplicateCategoryWarning {
                Text(
                    invalidCategoryIsReserved
                        ? (language == .ru ? "Системное имя недоступно" : "Reserved category name")
                        : (language == .ru ? "Такая категория уже есть" : "Category already exists")
                )
                    .font(currentFont.font(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .padding(.leading, 2)
                    .transition(.opacity)
            }
        }
        .padding(8)
        .background(currentTheme.primaryText.opacity(0.03))
    }

    private func submitNewCategory() {
        let sanitized = sanitizeCategoryNameInput(newCategoryName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard !sanitized.isEmpty else { return }
        let validation = SnippetCategoryValidator.validateCandidate(sanitized, existingCategories: categories)
        if !validation.isValid {
            invalidCategoryIsReserved = validation.isReserved
            withAnimation(.easeOut(duration: 0.14)) {
                duplicateCategoryWarning = true
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            NSSound.beep()
            triggerDuplicateShake()
            return
        }
        invalidCategoryIsReserved = false
        TapticSoundAndHaptics.shared.playClick()
        duplicateCategoryWarning = false
        onCreateCategory(sanitized, newCategoryIcon)
        newCategoryName = ""
    }

    private func triggerDuplicateShake() {
        let offsets: [(CGFloat, TimeInterval)] = [(6, 0.0), (-6, 0.05), (4, 0.10), (-4, 0.15), (0, 0.20)]
        for (value, delay) in offsets {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.linear(duration: 0.04)) {
                    duplicateShakeOffset = value
                }
            }
        }
    }
}
