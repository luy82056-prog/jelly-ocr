import Foundation
import Combine
import UIKit

final class QuoteViewModel: ObservableObject {
    static let quotesDidChangeNotification = Notification.Name("JellyQuotesDidChange")

    @Published var quotes: [Quote] = []
    @Published var recognizedTexts: [String] = []
    @Published var selectedText: String = ""
    @Published var fullFrameText: String = ""
    @Published var showCopiedToast: Bool = false
    @Published var showDeletedToast: Bool = false
    @Published var deletedQuote: Quote?

    private let storage = StorageService.shared
    private let export = ExportService.shared
    private var pendingDeleteTimer: Timer?

    init() {
        loadQuotes()
    }

    func loadQuotes() {
        quotes = storage.getAll()
    }

    func addQuote(clearRecognitionAfterAdding: Bool = true) {
        let text = selectedText.isEmpty ? fullFrameText : selectedText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let quote = Quote(selectedText: selectedText, fullFrameText: fullFrameText)
        storage.add(quote)
        loadQuotes()
        NotificationCenter.default.post(name: Self.quotesDidChangeNotification, object: nil)

        if clearRecognitionAfterAdding {
            clearRecognition()
        }
    }

    func addLockedQuote(selectedText: String, fullFrameText: String) {
        self.selectedText = selectedText
        self.fullFrameText = fullFrameText
        addQuote(clearRecognitionAfterAdding: false)
    }

    func deleteQuote(_ quote: Quote) {
        storage.softDelete(id: quote.id)
        deletedQuote = quote
        loadQuotes()
        NotificationCenter.default.post(name: Self.quotesDidChangeNotification, object: nil)

        showDeletedToast = true

        pendingDeleteTimer?.invalidate()
        pendingDeleteTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.confirmDelete()
        }
    }

    func undoDelete() {
        pendingDeleteTimer?.invalidate()
        pendingDeleteTimer = nil

        if let quote = deletedQuote {
            storage.restore(id: quote.id)
            loadQuotes()
            NotificationCenter.default.post(name: Self.quotesDidChangeNotification, object: nil)
        }
        deletedQuote = nil
        showDeletedToast = false
    }

    func confirmDelete() {
        if let quote = deletedQuote {
            storage.permanentDelete(id: quote.id)
            NotificationCenter.default.post(name: Self.quotesDidChangeNotification, object: nil)
        }
        deletedQuote = nil
        showDeletedToast = false
        storage.deleteExpired()
    }

    func copyQuote(_ quote: Quote) {
        UIPasteboard.general.string = quote.selectedText.isEmpty ? quote.fullFrameText : quote.selectedText
        showCopiedToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showCopiedToast = false
        }
    }

    func copyAllQuotesAsTXT() {
        UIPasteboard.general.string = exportToTXT()
        showCopiedToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showCopiedToast = false
        }
    }

    func clearRecognition() {
        recognizedTexts = []
        selectedText = ""
        fullFrameText = ""
    }

    func updateRecognizedText(_ texts: [String]) {
        recognizedTexts = texts
        fullFrameText = texts.joined(separator: "\n")
    }

    func exportToMarkdown() -> String {
        export.exportToMarkdown(quotes: quotes)
    }

    func exportToTXT() -> String {
        export.exportToTXT(quotes: quotes)
    }

    func saveToFiles(type: ExportType) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let filename = "Jelly-摘录-\(dateFormatter.string(from: Date()))"

        let content = type == .markdown ? exportToMarkdown() : exportToTXT()
        return export.saveToFiles(content: content, filename: filename, type: type)
    }
}
