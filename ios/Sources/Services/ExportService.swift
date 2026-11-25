import Foundation
import UIKit

final class ExportService {
    static let shared = ExportService()

    private init() {}

    func exportToMarkdown(quotes: [Quote]) -> String {
        var md = "# 轻摘 Jelly\n\n"
        md += "_导出时间: \(formattedDate())_\n\n"
        md += "---\n\n"

        let grouped = Dictionary(grouping: quotes) { quote in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: quote.createdAt)
        }

        for (date, quotesOnDate) in grouped.sorted(by: { $0.key > $1.key }) {
            md += "## \(date)\n\n"
            for quote in quotesOnDate {
                md += "> \(quote.selectedText.isEmpty ? quote.fullFrameText : quote.selectedText)\n\n"
                md += "- 时间: \(quote.formattedDate)\n"
                if let page = quote.pageNumber {
                    md += "- 页码: \(page)\n"
                }
                if let book = quote.bookTitle {
                    md += "- 书名: \(book)\n"
                }
                md += "\n"
            }
        }

        return md
    }

    func exportToTXT(quotes: [Quote]) -> String {
        var txt = "轻摘 Jelly\n"
        txt += "导出时间: \(formattedDate())\n"
        txt += "=".padding(toLength: 40, withPad: "=", startingAt: 0) + "\n\n"

        for (index, quote) in quotes.enumerated() {
            txt += "[\(index + 1)] \(quote.formattedDate)\n"
            txt += "-".padding(toLength: 40, withPad: "-", startingAt: 0) + "\n"
            txt += "\(quote.selectedText.isEmpty ? quote.fullFrameText : quote.selectedText)\n"
            if let page = quote.pageNumber {
                txt += "页码: \(page)\n"
            }
            if let book = quote.bookTitle {
                txt += "书名: \(book)\n"
            }
            txt += "\n"
        }

        return txt
    }

    func saveToFiles(content: String, filename: String, type: ExportType) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ext = type == .markdown ? "md" : "txt"
        let fileURL = documentsPath.appendingPathComponent("\(filename).\(ext)")

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to save file: \(error)")
            return nil
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date())
    }
}

enum ExportType {
    case markdown
    case txt
}