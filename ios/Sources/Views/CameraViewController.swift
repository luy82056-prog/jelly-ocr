import UIKit
import AVFoundation
import Vision
import VisionKit

class CameraViewController: UIViewController {
    private enum ScanState {
        case scanning
        case locked
    }

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var dataScannerViewController: UIViewController?
    private var recognizedItemsTask: Task<Void, Never>?

    private let overlayView = RecognitionOverlayView()
    private let resultCardView = ResultCardView()
    private let viewModel = QuoteViewModel()
    private let instructionLabel = PaddedLabel()
    private let primaryButton = UIButton(type: .system)
    private let savedToastLabel = PaddedLabel()

    private var lastRecognitionTime: Date = Date()
    private let recognitionInterval: TimeInterval = 0.8
    private var isRecognizing = false
    private var lastRecognizedText = ""
    private var repeatedTextCount = 0
    private var pendingResultUpdate: DispatchWorkItem?
    private var lastDisplayedText = ""
    private var scanState: ScanState = .scanning
    private var lockedFullText = ""
    private var savedCountInLockSession = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        if !setupLiveTextScannerIfAvailable() {
            setupCamera()
        }

        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if scanState == .scanning {
            startScanning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateLiveTextRegion()
    }

    private func setupLiveTextScannerIfAvailable() -> Bool {
        guard #available(iOS 16.0, *), DataScannerViewController.isSupported else {
            return false
        }

        let textTypes: Set<DataScannerViewController.RecognizedDataType> = [
            .text(languages: ["zh-Hans", "zh-Hant", "en-US"], textContentType: nil)
        ]

        let scanner = DataScannerViewController(
            recognizedDataTypes: textTypes,
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )

        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(scanner)
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
        dataScannerViewController = scanner

        return true
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high

        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            showCameraError()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
        } catch {
            showCameraError()
            return
        }

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.video.queue"))
        videoOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        if captureSession?.canAddOutput(videoOutput!) == true {
            captureSession?.addOutput(videoOutput!)
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds
        view.layer.addSublayer(previewLayer!)
    }

    private func setupUI() {
        overlayView.frame = view.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.isDraggable = true
        overlayView.onFrameChanged = { [weak self] in
            self?.updateLiveTextRegion()
        }
        view.addSubview(overlayView)

        resultCardView.translatesAutoresizingMaskIntoConstraints = false
        resultCardView.isHidden = true
        resultCardView.onSave = { [weak self, weak resultCardView] in
            guard let self else { return }
            self.saveLockedQuote(selectedText: resultCardView?.selectedText)
        }
        resultCardView.onCopy = { [weak self, weak resultCardView] in
            self?.copyLockedQuote(selectedText: resultCardView?.selectedText)
        }
        view.addSubview(resultCardView)

        primaryButton.addTarget(self, action: #selector(primaryButtonTapped), for: .touchUpInside)
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(primaryButton)

        NSLayoutConstraint.activate([
            resultCardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            resultCardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            resultCardView.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -12),
            resultCardView.heightAnchor.constraint(equalToConstant: 230),

            primaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            primaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            primaryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            primaryButton.heightAnchor.constraint(equalToConstant: 52)
        ])

        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        instructionLabel.textAlignment = .center
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        instructionLabel.layer.cornerRadius = 8
        instructionLabel.layer.masksToBounds = true
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)

        savedToastLabel.text = "已保存"
        savedToastLabel.textColor = .white
        savedToastLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        savedToastLabel.textAlignment = .center
        savedToastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.56)
        savedToastLabel.layer.cornerRadius = 10
        savedToastLabel.layer.masksToBounds = true
        savedToastLabel.alpha = 0
        savedToastLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(savedToastLabel)

        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),

            savedToastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            savedToastLabel.bottomAnchor.constraint(equalTo: resultCardView.topAnchor, constant: -12)
        ])

        updateScanUI()
        updateLiveTextRegion()
    }

    private func startScanning() {
        guard scanState == .scanning else { return }

        if #available(iOS 16.0, *), let scanner = dataScannerViewController as? DataScannerViewController {
            do {
                try scanner.startScanning()
                observeLiveTextItems(from: scanner)
            } catch {
                showScannerUnavailableError(error)
            }
            return
        }

        sessionQueue.async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    private func stopScanning() {
        pendingResultUpdate?.cancel()
        pendingResultUpdate = nil
        recognizedItemsTask?.cancel()
        recognizedItemsTask = nil

        if #available(iOS 16.0, *), let scanner = dataScannerViewController as? DataScannerViewController {
            scanner.stopScanning()
            return
        }

        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    private func showCameraError() {
        let alert = UIAlertController(
            title: "摄像头不可用",
            message: "请在设置中允许使用摄像头",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func showScannerUnavailableError(_ error: Error) {
        let alert = UIAlertController(
            title: "扫描不可用",
            message: "请确认已允许相机权限，并尝试重新打开扫描页。\n\(error.localizedDescription)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    @available(iOS 16.0, *)
    private func observeLiveTextItems(from scanner: DataScannerViewController) {
        recognizedItemsTask?.cancel()
        recognizedItemsTask = Task { [weak self, weak scanner] in
            guard let scanner else { return }
            for await items in scanner.recognizedItems {
                guard !Task.isCancelled else { return }
                let texts = items.compactMap { item -> String? in
                    guard case .text(let text) = item else { return nil }
                    return text.transcript
                }

                await MainActor.run {
                    guard self?.scanState == .scanning else { return }
                    self?.scheduleResultUpdate(texts)
                }
            }
        }
    }

    private func updateLiveTextRegion() {
        guard #available(iOS 16.0, *), let scanner = dataScannerViewController as? DataScannerViewController else {
            return
        }

        let frameRect = overlayView.frameRect
        guard !frameRect.isEmpty else {
            scanner.regionOfInterest = scanner.view.bounds
            return
        }

        scanner.regionOfInterest = overlayView.convert(frameRect, to: scanner.view)
    }

    private func recognizeText(in pixelBuffer: CVPixelBuffer) {
        guard scanState == .scanning else { return }
        guard !isRecognizing else { return }
        isRecognizing = true

        let regionOfInterest = currentRecognitionRegion()
        OCRService.shared.recognizeText(in: pixelBuffer, regionOfInterest: regionOfInterest) { [weak self] result in
            guard let self = self else { return }
            self.isRecognizing = false

            switch result {
            case .success(let texts):
                self.updateResult(texts)
            case .failure(let error):
                print("OCR Error: \(error)")
            }
        }
    }

    private func updateResult(_ texts: [String], requireStableText: Bool = true) {
        guard scanState == .scanning else { return }
        let fullText = normalized(texts.joined(separator: "\n"))
        guard !requireStableText || shouldDisplay(fullText) else { return }

        applyResultText(fullText)
    }

    private func scheduleResultUpdate(_ texts: [String]) {
        guard scanState == .scanning else { return }
        let fullText = normalized(texts.joined(separator: "\n"))
        guard fullText != lastDisplayedText else { return }

        pendingResultUpdate?.cancel()
        let update = DispatchWorkItem { [weak self] in
            self?.applyResultText(fullText)
        }
        pendingResultUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: update)
    }

    private func applyResultText(_ fullText: String) {
        guard scanState == .scanning else { return }
        lastDisplayedText = fullText
        viewModel.updateRecognizedText(fullText.isEmpty ? [] : fullText.components(separatedBy: "\n"))
        viewModel.selectedText = fullText

        if !fullText.isEmpty {
            resultCardView.isHidden = false
            resultCardView.updateText(fullText)
            resultCardView.setLocked(false)
        } else {
            resultCardView.isHidden = true
        }
    }

    @objc private func primaryButtonTapped() {
        switch scanState {
        case .scanning:
            lockCurrentText()
        case .locked:
            resetForScanning()
        }
    }

    private func lockCurrentText() {
        let frozenText = viewModel.fullFrameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !frozenText.isEmpty else {
            instructionLabel.text = "先对准有文字的书页"
            return
        }

        scanState = .locked
        stopScanning()
        lockedFullText = frozenText
        savedCountInLockSession = 0
        viewModel.selectedText = frozenText
        resultCardView.updateText(frozenText, force: true)
        resultCardView.setLocked(true)
        updateScanUI()
    }

    private func saveLockedQuote(selectedText: String?) {
        guard scanState == .locked else { return }
        let selected = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if selected.isEmpty && savedCountInLockSession > 0 {
            instructionLabel.text = "请选择下一段文字再保存"
            showSavedToast(message: "先选择文字")
            return
        }

        let text = preferredQuoteText(selectedText: selectedText)
        guard !text.isEmpty else { return }

        viewModel.addLockedQuote(selectedText: text, fullFrameText: lockedFullText)
        savedCountInLockSession += 1
        resultCardView.clearSelection()
        instructionLabel.text = "已保存 \(savedCountInLockSession) 条，可继续选择下一段"
        showSavedToast(message: "已保存 \(savedCountInLockSession) 条")
    }

    private func copyLockedQuote(selectedText: String?) {
        guard scanState == .locked else { return }
        let text = preferredQuoteText(selectedText: selectedText)
        guard !text.isEmpty else { return }

        UIPasteboard.general.string = text
        resetForScanning(message: "已复制，继续扫描")
    }

    private func preferredQuoteText(selectedText: String?) -> String {
        let selected = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !selected.isEmpty {
            return selected
        }

        let frozenText = lockedFullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !frozenText.isEmpty {
            return frozenText
        }

        return viewModel.fullFrameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetForScanning(message: String? = nil) {
        scanState = .scanning
        viewModel.clearRecognition()
        lastRecognizedText = ""
        repeatedTextCount = 0
        lastDisplayedText = ""
        lockedFullText = ""
        savedCountInLockSession = 0
        isRecognizing = false
        resultCardView.updateText("", force: true)
        resultCardView.setLocked(false)
        resultCardView.isHidden = true
        updateScanUI(message: message)
        startScanning()
    }

    private func updateScanUI(message: String? = nil) {
        switch scanState {
        case .scanning:
            instructionLabel.text = message ?? "拖动或双指缩放取景框"
            configurePrimaryButton(title: "锁定文字", systemImage: "text.viewfinder", color: .systemBlue)
        case .locked:
            instructionLabel.text = "文字已锁定，可慢慢选取摘录"
            configurePrimaryButton(title: "重新扫描", systemImage: "arrow.clockwise", color: .systemGray)
        }
    }

    private func showSavedToast(message: String = "已保存") {
        savedToastLabel.text = message
        savedToastLabel.alpha = 0
        UIView.animate(withDuration: 0.18) {
            self.savedToastLabel.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.24, delay: 1.0) {
                self.savedToastLabel.alpha = 0
            }
        }
    }

    private func configurePrimaryButton(title: String, systemImage: String, color: UIColor) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePadding = 8
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        primaryButton.configuration = configuration
    }

    private func currentRecognitionRegion() -> CGRect {
        guard let previewLayer = previewLayer else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let layerRect = overlayView.convert(overlayView.frameRect, to: view)
        let metadataRect = previewLayer.metadataOutputRectConverted(fromLayerRect: layerRect)
        return CGRect(
            x: metadataRect.minX,
            y: 1 - metadataRect.maxY,
            width: metadataRect.width,
            height: metadataRect.height
        )
    }

    private func normalized(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func shouldDisplay(_ text: String) -> Bool {
        if text == lastRecognizedText {
            repeatedTextCount += 1
        } else {
            lastRecognizedText = text
            repeatedTextCount = 1
        }

        return text.isEmpty || repeatedTextCount >= 2
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastRecognitionTime) >= recognitionInterval else { return }
        lastRecognitionTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.recognizeText(in: pixelBuffer)
        }
    }
}

class RecognitionOverlayView: UIView {
    var onFrameChanged: (() -> Void)?
    var isDraggable = true {
        didSet {
            panGesture?.isEnabled = isDraggable
            pinchGesture?.isEnabled = isDraggable
            frameView.isUserInteractionEnabled = isDraggable
        }
    }

    private let frameView = UIView()
    private let cornerView = UIView()
    private var panGesture: UIPanGestureRecognizer?
    private var pinchGesture: UIPinchGestureRecognizer?

    var frameRect: CGRect {
        frameView.frame
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupGestures()
    }

    private func setupUI() {
        backgroundColor = .clear

        frameView.backgroundColor = .clear
        frameView.layer.borderColor = UIColor.white.withAlphaComponent(0.72).cgColor
        frameView.layer.borderWidth = 1.5
        frameView.layer.cornerRadius = 8
        addSubview(frameView)

        cornerView.backgroundColor = .clear
        cornerView.isHidden = true
        cornerView.layer.cornerRadius = 2
        addSubview(cornerView)
    }

    private func setupGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        frameView.addGestureRecognizer(panGesture)
        frameView.addGestureRecognizer(pinchGesture)
        self.panGesture = panGesture
        self.pinchGesture = pinchGesture
        frameView.isUserInteractionEnabled = true
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)

        var newFrame = frameView.frame
        newFrame.origin.x += translation.x
        newFrame.origin.y += translation.y

        let padding: CGFloat = 20
        newFrame.origin.x = max(padding, min(newFrame.origin.x, bounds.width - newFrame.width - padding))
        newFrame.origin.y = max(padding + 60, min(newFrame.origin.y, bounds.height - newFrame.height - padding - 80))

        frameView.frame = newFrame
        updateCorner()
        onFrameChanged?()
        gesture.setTranslation(.zero, in: self)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        let scale = gesture.scale
        gesture.scale = 1

        let currentFrame = frameView.frame
        let center = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        let minWidth: CGFloat = 140
        let minHeight: CGFloat = 90
        let maxWidth = max(minWidth, bounds.width - 40)
        let maxHeight = max(minHeight, bounds.height - 190)

        let newWidth = min(maxWidth, max(minWidth, currentFrame.width * scale))
        let newHeight = min(maxHeight, max(minHeight, currentFrame.height * scale))
        var newFrame = CGRect(
            x: center.x - newWidth / 2,
            y: center.y - newHeight / 2,
            width: newWidth,
            height: newHeight
        )

        newFrame = clampedFrame(newFrame)
        frameView.frame = newFrame
        updateCorner()
        onFrameChanged?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if frameView.frame == .zero {
            let frameWidth = min(bounds.width - 40, 360)
            let frameHeight = min(bounds.height * 0.58, 520)
            frameView.frame = clampedFrame(CGRect(
                x: (bounds.width - frameWidth) / 2,
                y: max(90, (bounds.height - frameHeight) / 2 - 30),
                width: frameWidth,
                height: frameHeight
            ))
            onFrameChanged?()
        }

        updateCorner()
    }

    private func clampedFrame(_ frame: CGRect) -> CGRect {
        let padding: CGFloat = 20
        var clamped = frame
        clamped.origin.x = max(padding, min(clamped.origin.x, bounds.width - clamped.width - padding))
        clamped.origin.y = max(padding + 60, min(clamped.origin.y, bounds.height - clamped.height - padding - 80))
        return clamped
    }

    private func updateCorner() {
        cornerView.frame = CGRect(x: frameView.frame.minX - 4, y: frameView.frame.minY - 4, width: 8, height: 8)
    }
}

final class PaddedLabel: UILabel {
    var contentInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }
}

class ResultCardView: UIView {
    var onSave: (() -> Void)?
    var onCopy: (() -> Void)?
    var selectedText: String? {
        if let cachedSelectedText, !cachedSelectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cachedSelectedText
        }

        let range = textView.selectedRange
        guard range.length > 0, let text = textView.text, range.location + range.length <= (text as NSString).length else {
            return nil
        }

        return (text as NSString).substring(with: range)
    }

    private let textView = UITextView()
    private let titleLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let buttonsStack = UIStackView()
    private let materialView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private var cachedSelectedText: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .clear
        layer.cornerRadius = 8
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 18

        materialView.layer.cornerRadius = 8
        materialView.layer.masksToBounds = true
        materialView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(materialView)

        layer.borderColor = UIColor.separator.withAlphaComponent(0.2).cgColor
        layer.borderWidth = 0.5

        titleLabel.text = "识别文本"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = false
        textView.alwaysBounceVertical = true
        textView.delegate = self
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        configureActionButton(saveButton, title: "保存", systemImage: "tray.and.arrow.down.fill", style: .filled)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        configureActionButton(copyButton, title: "复制", systemImage: "doc.on.doc", style: .tinted)
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)

        buttonsStack.axis = .horizontal
        buttonsStack.spacing = 10
        buttonsStack.distribution = .fillEqually
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.addArrangedSubview(copyButton)
        buttonsStack.addArrangedSubview(saveButton)
        addSubview(buttonsStack)

        NSLayoutConstraint.activate([
            materialView.topAnchor.constraint(equalTo: topAnchor),
            materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
            materialView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            textView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            buttonsStack.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 10),
            buttonsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            buttonsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            buttonsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            buttonsStack.heightAnchor.constraint(equalToConstant: 40)
        ])

        setLocked(false)
    }

    private enum ActionButtonStyle {
        case filled
        case tinted
    }

    private func configureActionButton(_ button: UIButton, title: String, systemImage: String, style: ActionButtonStyle) {
        var configuration: UIButton.Configuration = style == .filled ? .filled() : .tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePadding = 6
        configuration.cornerStyle = .medium
        configuration.baseForegroundColor = style == .filled ? .white : .systemBlue
        configuration.baseBackgroundColor = .systemBlue
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        button.configuration = configuration
    }

    func updateText(_ text: String, force: Bool = false) {
        guard textView.text != text else { return }
        guard force || !textView.isFirstResponder else { return }

        cachedSelectedText = nil
        let selectedRange = textView.selectedRange
        textView.text = text
        if selectedRange.location + selectedRange.length <= (text as NSString).length {
            textView.selectedRange = selectedRange
        }
    }

    func clearSelection() {
        cachedSelectedText = nil
        textView.selectedRange = NSRange(location: 0, length: 0)
    }

    func setLocked(_ locked: Bool) {
        titleLabel.text = locked ? "选取摘录" : "识别文本"
        textView.isSelectable = locked
        buttonsStack.isHidden = !locked

        if !locked {
            cachedSelectedText = nil
            textView.resignFirstResponder()
        }
    }

    @objc private func saveTapped() {
        onSave?()
    }

    @objc private func copyTapped() {
        onCopy?()
    }
}

extension ResultCardView: UITextViewDelegate {
    func textViewDidChangeSelection(_ textView: UITextView) {
        let range = textView.selectedRange
        guard range.length > 0, let text = textView.text, range.location + range.length <= (text as NSString).length else {
            cachedSelectedText = nil
            return
        }

        cachedSelectedText = (text as NSString).substring(with: range)
    }
}
