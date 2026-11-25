import Foundation

final class StorageService {
    static let shared = StorageService()

    private let userDefaults = UserDefaults.standard
    private let storageKey = "JellyQuotes"
    private var quotes: [Quote] = []

    private init() {
        load()
    }

    func load() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            quotes = []
            return
        }
        do {
            quotes = try JSONDecoder().decode([Quote].self, from: data)
        } catch {
            print("Failed to load quotes: \(error)")
            quotes = []
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(quotes)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            print("Failed to save quotes: \(error)")
        }
    }

    func getAll() -> [Quote] {
        quotes.filter { !$0.isDeleted }
    }

    func getDeleted() -> [Quote] {
        quotes.filter { $0.isDeleted }
    }

    func add(_ quote: Quote) {
        quotes.insert(quote, at: 0)
        save()
    }

    func softDelete(id: UUID) {
        if let index = quotes.firstIndex(where: { $0.id == id }) {
            quotes[index].deletedAt = Date()
            save()
        }
    }

    func restore(id: UUID) {
        if let index = quotes.firstIndex(where: { $0.id == id }) {
            quotes[index].deletedAt = nil
            save()
        }
    }

    func permanentDelete(id: UUID) {
        quotes.removeAll { $0.id == id }
        save()
    }

    func deleteExpired() {
        let threeSecondsAgo = Date().addingTimeInterval(-3)
        quotes.removeAll { $0.isDeleted && ($0.deletedAt ?? Date()) < threeSecondsAgo }
        save()
    }

    func clearAll() {
        quotes.removeAll()
        save()
    }
}