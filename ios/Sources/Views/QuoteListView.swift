import SwiftUI
import UIKit

struct QuoteListView: View {
    @StateObject private var viewModel = QuoteViewModel()
    @State private var exportedFile: ExportedFile?

    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.quotes.isEmpty {
                    emptyStateView
                } else {
                    quoteListContent
                }

                if viewModel.showCopiedToast {
                    toastView(message: "已复制")
                }

                if viewModel.showDeletedToast {
                    deletedToastView
                }
            }
            .navigationTitle("轻摘")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: copyAllQuotes) {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }
                    .disabled(viewModel.quotes.isEmpty)

                    Button(action: exportTXT) {
                        Label("导出 TXT", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.quotes.isEmpty)
                }
            }
            .sheet(item: $exportedFile) { file in
                ActivityView(activityItems: [file.url])
            }
            .onAppear {
                viewModel.loadQuotes()
            }
            .onReceive(NotificationCenter.default.publisher(for: QuoteViewModel.quotesDidChangeNotification)) { _ in
                viewModel.loadQuotes()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.quote")
                .font(.system(size: 52, weight: .light))
                .foregroundColor(.secondary.opacity(0.55))

            Text("暂无摘录")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)

            Text("扫描书页，保存喜欢的句子")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }

    private var quoteListContent: some View {
        List {
            Section {
                ForEach(viewModel.quotes) { quote in
                    NavigationLink(destination: QuoteDetailView(quote: quote)) {
                        QuoteRowView(quote: quote)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteQuote(quote)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            viewModel.copyQuote(quote)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = quoteDisplayText(quote)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }

                        Button(role: .destructive) {
                            viewModel.deleteQuote(quote)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func quoteDisplayText(_ quote: Quote) -> String {
        quote.selectedText.isEmpty ? quote.fullFrameText : quote.selectedText
    }

    private var deletedToastView: some View {
        VStack {
            Spacer()

            HStack {
                Text("已删除")
                    .foregroundColor(.primary)

                Button("撤回") {
                    viewModel.undoDelete()
                }
                .foregroundColor(.blue)
                .font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .cornerRadius(8)
            .padding(.bottom, 100)
        }
    }

    private func toastView(message: String) -> some View {
        VStack {
            Spacer()

            Text(message)
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .cornerRadius(8)
                .padding(.bottom, 100)
        }
    }

    private func copyAllQuotes() {
        viewModel.copyAllQuotesAsTXT()
    }

    private func exportTXT() {
        if let fileURL = viewModel.saveToFiles(type: .txt) {
            exportedFile = ExportedFile(url: fileURL)
        }
    }
}

struct QuoteDetailView: View {
    let quote: Quote
    @State private var showCopiedToast = false
    @State private var selectedText = ""

    private var text: String {
        quote.selectedText.isEmpty ? quote.fullFrameText : quote.selectedText
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                SelectableQuoteTextView(text: text, selectedText: $selectedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text(detailDate)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 4)
            }
            .padding(16)

            if showCopiedToast {
                VStack {
                    Spacer()

                    Text("已复制")
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                        .cornerRadius(8)
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("摘录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: copyText) {
                    Label(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "复制全部" : "复制选中", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private var detailDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: quote.createdAt)
    }

    private func copyText() {
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        UIPasteboard.general.string = trimmedSelection.isEmpty ? text : trimmedSelection
        showCopiedToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedToast = false
        }
    }
}

private struct SelectableQuoteTextView: UIViewRepresentable {
    let text: String
    @Binding var selectedText: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.showsHorizontalScrollIndicator = false
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.font = .systemFont(ofSize: 17)
        textView.textContainerInset = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byCharWrapping
        textView.textContainer.maximumNumberOfLines = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.adjustsFontForContentSizeCategory = true
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var selectedText: String

        init(selectedText: Binding<String>) {
            _selectedText = selectedText
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            guard range.length > 0, let text = textView.text, range.location + range.length <= (text as NSString).length else {
                selectedText = ""
                return
            }

            selectedText = (text as NSString).substring(with: range)
        }
    }
}

private struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct QuoteRowView: View {
    let quote: Quote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quote.preview)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .lineLimit(4)

            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(quote.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !quote.fullFrameText.isEmpty && quote.selectedText != quote.fullFrameText {
                    Text("已选摘录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    QuoteListView()
}
