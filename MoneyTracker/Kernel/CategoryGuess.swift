import Foundation

/// Suggests a category for a note, learning from the person's own history
/// first and falling back to a small built-in vocabulary. Runs on device.
nonisolated struct CategoryGuesser {

    nonisolated struct Candidate: Equatable {
        let id: UUID
        let isIncome: Bool
        /// Stable key for built-in categories (their SF Symbol name).
        let iconKey: String
        let name: String
    }

    nonisolated struct Memory {
        let note: String
        let categoryID: UUID
        let date: Date
    }

    nonisolated struct Guess: Equatable {
        let categoryID: UUID
        let confidence: Double
    }

    /// Built-in hints keyed by the default categories' icon names.
    static let vocabulary: [String: [String]] = [
        "fork.knife": [
            "coffee", "cafe", "café", "lunch", "dinner", "breakfast", "brunch", "restaurant", "pizza", "burger", "sushi", "kebab",
            "grocery", "groceries", "supermarket", "market", "food", "bakery", "tea", "snack", "snacks", "takeaway", "delivery",
            "mcdonalds", "mcdonald's", "kfc", "starbucks", "glovo", "wolt", "silpo", "atb", "novus", "auchan", "lidl", "aldi", "biedronka", "tesco",
            "кава", "каву", "кафе", "кавʼярня", "кав'ярня", "обід", "вечеря", "сніданок", "ресторан", "піца", "суші", "бургер", "шаурма",
            "продукти", "супермаркет", "сільпо", "атб", "їжа", "хліб", "чай", "доставка", "глово", "макдональдс", "фора", "варус", "ашан",
            "кофе", "обед", "ужин", "завтрак", "продукты", "еда"
        ],
        "car.fill": [
            "taxi", "uber", "bolt", "uklon", "lyft", "bus", "metro", "subway", "train", "tram", "fuel", "gas", "petrol", "diesel",
            "parking", "ticket", "tickets", "toll", "carwash", "transport", "okko", "wog", "shell", "socar", "upg",
            "таксі", "уклон", "болт", "автобус", "метро", "потяг", "поїзд", "трамвай", "тролейбус", "маршрутка", "бензин", "пальне",
            "дизель", "паркування", "парковка", "проїзд", "квиток", "квитки", "мийка", "укрзалізниця", "такси", "проезд", "билет"
        ],
        "bag.fill": [
            "clothes", "shoes", "amazon", "ebay", "aliexpress", "temu", "shein", "zara", "h&m", "uniqlo", "mall", "shopping", "store", "rozetka", "prom",
            "одяг", "взуття", "розетка", "покупки", "магазин", "кросівки", "футболка", "куртка", "одежда", "обувь"
        ],
        "house.fill": [
            "rent", "utilities", "electricity", "water", "internet", "wifi", "heating", "furniture", "ikea", "repair", "mortgage", "household",
            "оренда", "комуналка", "комунальні", "світло", "електрика", "вода", "інтернет", "опалення", "газ", "квартира", "ремонт", "меблі", "епіцентр",
            "аренда", "квартплата", "коммуналка"
        ],
        "gamecontroller.fill": [
            "cinema", "movie", "movies", "netflix", "spotify", "youtube", "games", "game", "steam", "playstation", "xbox", "concert", "bar", "club", "party", "museum",
            "кіно", "фільм", "ігри", "гра", "концерт", "бар", "клуб", "вечірка", "музей", "театр", "мегого", "кино", "игры"
        ],
        "heart.fill": [
            "pharmacy", "doctor", "dentist", "clinic", "hospital", "medicine", "pills", "vitamins", "health", "therapy", "gym", "fitness",
            "аптека", "лікар", "стоматолог", "клініка", "лікарня", "ліки", "вітаміни", "аналізи", "здоровʼя", "здоров'я", "спортзал", "фітнес",
            "аптеке", "врач", "лекарства"
        ],
        "graduationcap.fill": [
            "course", "courses", "books", "book", "school", "university", "tuition", "udemy", "coursera", "lesson", "lessons", "tutor",
            "курс", "курси", "книга", "книги", "школа", "університет", "навчання", "урок", "уроки", "репетитор", "учеба", "книжки"
        ],
        "banknote.fill": [
            "salary", "paycheck", "payday", "wage", "wages", "зарплата", "зарплату", "зп", "аванс", "зарплатня", "зарплаты"
        ],
        "laptopcomputer": [
            "freelance", "client", "invoice", "upwork", "fiverr", "project", "фриланс", "фріланс", "замовник", "проєкт", "проект", "інвойс"
        ],
        "gift.fill": [
            "gift", "gifts", "present", "birthday", "подарунок", "подарунки", "подарок", "день народження"
        ]
    ]

    let candidates: [Candidate]
    private var learned: [String: [UUID: Double]] = [:]
    private var exactNotes: [String: [UUID: Double]] = [:]

    init(candidates: [Candidate], memories: [Memory], now: Date = Date()) {
        self.candidates = candidates
        let valid = Set(candidates.map(\.id))
        for memory in memories.prefix(800) where valid.contains(memory.categoryID) {
            let age = max(now.timeIntervalSince(memory.date) / 86_400, 0)
            let weight = 1.0 / (1.0 + age / 90.0)
            let key = memory.note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            exactNotes[key, default: [:]][memory.categoryID, default: 0] += weight
            for word in Tokenizer.words(key) {
                learned[word, default: [:]][memory.categoryID, default: 0] += weight
            }
        }
    }

    func guess(note: String, isIncome: Bool?) -> Guess? {
        let key = note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let words = Tokenizer.words(key)
        guard !words.isEmpty else { return nil }

        var scores: [UUID: Double] = [:]
        let pool = candidates.filter { candidate in
            guard let isIncome else { return true }
            return candidate.isIncome == isIncome
        }
        let poolIDs = Set(pool.map(\.id))

        if let exact = exactNotes[key] {
            for (id, weight) in exact where poolIDs.contains(id) { scores[id, default: 0] += 4 * weight }
        }
        for word in words {
            if let hits = learned[word] {
                for (id, weight) in hits where poolIDs.contains(id) { scores[id, default: 0] += 1.5 * weight }
            }
        }
        for candidate in pool {
            let nameWords = Set(Tokenizer.words(candidate.name))
            if words.contains(where: { nameWords.contains($0) }) {
                scores[candidate.id, default: 0] += 2.5
            }
            if let hints = CategoryGuesser.vocabulary[candidate.iconKey] {
                for word in words where CategoryGuesser.matches(word, hints: hints) {
                    scores[candidate.id, default: 0] += 2
                }
            }
        }

        guard let best = scores.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.uuidString > rhs.key.uuidString : lhs.value < rhs.value
        }), best.value >= 1.0 else { return nil }
        let total = scores.values.reduce(0, +)
        return Guess(categoryID: best.key, confidence: total > 0 ? best.value / total : 0)
    }

    /// Exact match, or a shared stem for longer words (handles inflections like "продуктів").
    static func matches(_ word: String, hints: [String]) -> Bool {
        for hint in hints {
            if word == hint { return true }
            if hint.count >= 5 && word.count >= 5 {
                let stem = min(hint.count, word.count) - 2
                if stem >= 4 && word.prefix(stem) == hint.prefix(stem) { return true }
            }
        }
        return false
    }

    /// Whether the note's words alone point to an income category.
    func prefersIncome(note: String) -> Bool? {
        guard let guess = guess(note: note, isIncome: nil),
              let candidate = candidates.first(where: { $0.id == guess.categoryID }) else { return nil }
        return candidate.isIncome
    }
}
