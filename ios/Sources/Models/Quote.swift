import Foundation

struct Quote: Codable, Identifiable {
    let id: UUID
    var selectedText: String
    var fullFrameText: String
    var createdAt: Date
    var deletedAt: Date?
    var pageNumber: String?
    var bookTitle: String?

    init(selectedText: String, fullFrameText: String, createdAt: Date = Date(), deletedAt: Date? = nil, pageNumber: String? = nil, bookTitle: String? = nil) {
        self.id = UUID()
        self.selectedText = selectedText
        self.fullFrameText = fullFrameText
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.pageNumber = pageNumber
        self.bookTitle = bookTitle
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    var preview: String {
        let text = selectedText.isEmpty ? fullFrameText : selectedText
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 80 {
            return String(trimmed.prefix(80)) + "..."
        }
        return trimmed
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: createdAt)
    }
}
