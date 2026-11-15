import Foundation

public struct SnippetCategoryRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var iconName: String
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        iconName: String,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// Палитра из ровно 25 уникальных векторных иконок SF Symbols (сетка 5×5)
    /// Примечание: square.grid.2x2.fill зарезервирована СТРОГО для пункта «Все категории» и исключена из палитры.
    public static let availableIcons: [String] = [
        "chevron.left.forwardslash.chevron.right", // 1. Код / Разработка
        "briefcase.fill",                         // 2. Работа / Бизнес
        "doc.text.fill",                          // 3. Шаблоны / Документы
        "sparkles",                               // 4. Промпты / ИИ
        "server.rack",                            // 5. Серверы / Хостинг
        "terminal.fill",                          // 6. Терминал / CLI
        "cylinder.split.1x2.fill",                // 7. Базы данных / SQL
        "key.fill",                               // 8. Ключи / Доступы
        "creditcard.fill",                        // 9. Реквизиты / Финансы
        "globe",                                  // 10. Веб / Ссылки
        "envelope.fill",                          // 11. Письма / Почта
        "bubble.left.and.bubble.right.fill",      // 12. Ответы / Чаты
        "shield.lefthalf.filled",                 // 13. Безопасность
        "cloud.fill",                             // 14. Облако / Деплой
        "arrow.triangle.branch",                  // 15. Git / Ветки
        "ladybug.fill",                           // 16. Отладка / Фиксы
        "wrench.and.screwdriver.fill",            // 17. Конфиги / Настройки
        "book.fill",                              // 18. База знаний / Доки
        "bolt.fill",                              // 19. Быстрые команды
        "star.fill",                              // 20. Избранное / Важное
        "cpu.fill",                               // 21. Система / Железо
        "lock.fill",                              // 22. Секреты / Токены
        "paperplane.fill",                        // 23. Релизы / Отправка
        "flame.fill",                             // 24. Срочное / Хотфиксы
        "number"                                  // 25. Теги / Каналы
    ]
}
