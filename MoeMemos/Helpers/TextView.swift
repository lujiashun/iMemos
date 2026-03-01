//  TextView.swift
//  MoeMemos
//
//  Created by Mudkip on 2023/6/12.
//

import SwiftUI
import VisionKit

struct TextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?
    let shouldChangeText: ((_ range: Range<String.Index>, _ replacementText: String) -> Bool)?
    @Binding var showingScanner: Bool
    var onScanComplete: ((String) -> Void)?
    
    func makeUIView(context: Context) -> ScannerTextView {
        let textView = ScannerTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.onScanComplete = { scannedText in
            context.coordinator.insertScannedText(scannedText, into: textView)
        }
        textView.onScannerDismiss = {
            context.coordinator.dismissScanner()
        }
        return textView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func updateUIView(_ uiView: ScannerTextView, context: Context) {
        context.coordinator.isUpdatingView = true
        defer { context.coordinator.isUpdatingView = false }

        if text != uiView.text {
            uiView.text = text
        }
        
        if let selection = selection, selection.upperBound <= text.endIndex {
            let range = NSRange(selection, in: text)
            if uiView.selectedRange != range {
                uiView.selectedRange = range
            }
        } else {
            if uiView.selectedRange.upperBound != 0 {
                uiView.selectedRange = NSRange()
            }
        }
        
        // Update scanner visibility
        uiView.showingScanner = showingScanner
    }
    
    @MainActor
    class Coordinator: NSObject, UITextViewDelegate {
        let parent: TextView
        var isUpdatingView = false
        
        init(_ parent: TextView) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingView else { return }
            parent._text.wrappedValue = textView.text
            parent._selection.wrappedValue = Range(textView.selectedRange, in: textView.text)
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingView else { return }
            parent._text.wrappedValue = textView.text
            parent._selection.wrappedValue = Range(textView.selectedRange, in: textView.text)
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if let shouldChangeText = parent.shouldChangeText, let textRange = Range(range, in: textView.text) {
                return shouldChangeText(textRange, text)
            }
            return true
        }
        
        func insertScannedText(_ scannedText: String, into textView: ScannerTextView) {
            let selectedRange = textView.selectedRange
            
            if let textRange = Range(selectedRange, in: textView.text) {
                let before = textView.text[..<textRange.lowerBound]
                let after = textView.text[textRange.upperBound...]
                let newText = String(before) + scannedText + String(after)
                
                parent._text.wrappedValue = newText
                textView.text = newText
                
                // Update cursor position
                let newPosition = selectedRange.location + scannedText.count
                textView.selectedRange = NSRange(location: newPosition, length: 0)
                if let newSelection = Range(textView.selectedRange, in: newText) {
                    parent._selection.wrappedValue = newSelection
                }
            }
            
            parent.onScanComplete?(scannedText)
        }
        
        func dismissScanner() {
            parent.showingScanner = false
        }
    }
}

// Custom UITextView subclass with scanner input view
class ScannerTextView: UITextView {
    var onScanComplete: ((String) -> Void)?
    var onScannerDismiss: (() -> Void)?
    var showingScanner: Bool = false {
        didSet {
            if showingScanner {
                showScannerInputView()
            } else {
                hideScannerInputView()
            }
        }
    }
    
    private var scannerViewController: DataScannerViewController?
    private var insertButton: UIButton?
    
    private func showScannerInputView() {
        // 获取键盘高度 - 使用系统键盘通知获取实际高度
        let keyboardHeight = getKeyboardHeight()
        
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = self
        
        // Create a container view for the scanner - 使用实际键盘高度
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: keyboardHeight))
        containerView.backgroundColor = .black
        
        // Add scanner view to container
        scanner.view.frame = containerView.bounds
        containerView.addSubview(scanner.view)
        
        // Add close button
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeScanner), for: .touchUpInside)
        closeButton.frame = CGRect(x: containerView.bounds.width - 50, y: 10, width: 40, height: 40)
        containerView.addSubview(closeButton)
        
        // Add insert button at bottom - 系统风格（圆角胶囊按钮）
        let button = UIButton(type: .system)
        button.setTitle("插入", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = UIColor.systemGray  // 初始为灰色
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 25  // 胶囊形状
        button.isEnabled = false  // 初始不可用
        button.addTarget(self, action: #selector(insertScannedText), for: .touchUpInside)
        
        // 设置按钮frame - 固定宽度，居中显示，底部留安全区域
        let buttonWidth: CGFloat = 120
        let buttonX = (containerView.bounds.width - buttonWidth) / 2
        let bottomPadding: CGFloat = 20  // 底部安全区域
        button.frame = CGRect(x: buttonX, y: containerView.bounds.height - 50 - bottomPadding, width: buttonWidth, height: 50)
        containerView.addSubview(button)
        self.insertButton = button
        
        self.inputView = containerView
        self.reloadInputViews()
        
        scannerViewController = scanner
        
        // Start scanning
        try? scanner.startScanning()
    }
    
    private func getKeyboardHeight() -> CGFloat {
        // 使用键盘通知获取实际高度，如果没有则使用默认值
        // 标准iPhone键盘高度约为 216 (无预测栏) 或 260 (有预测栏) 或 340 (iPad)
        // 这里使用一个合理的默认值，实际高度会根据设备动态调整
        let screenHeight = UIScreen.main.bounds.height
        let screenWidth = UIScreen.main.bounds.width
        
        // 根据屏幕尺寸估算键盘高度
        if screenHeight > screenWidth {
            // 竖屏
            if screenHeight >= 812 {
                // iPhone X 及以上 (有刘海)
                return 335
            } else {
                // iPhone 8 及以下
                return 260
            }
        } else {
            // 横屏
            return 200
        }
    }
    
    private func hideScannerInputView() {
        self.inputView = nil
        self.reloadInputViews()
        scannerViewController = nil
    }
    
    @objc private func closeScanner() {
        showingScanner = false
        onScannerDismiss?()
    }
    
    private var scannedText: String = ""
    
    @objc private func insertScannedText() {
        guard !scannedText.isEmpty else { return }
        onScanComplete?(scannedText)
        showingScanner = false
        onScannerDismiss?()
    }
}

extension ScannerTextView: DataScannerViewControllerDelegate {
    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        guard case .text(let textItem) = item else { return }
        scannedText = textItem.transcript
        updateInsertButtonState()
    }
    
    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        guard let firstItem = addedItems.first,
              case .text(let textItem) = firstItem else { return }
        scannedText = textItem.transcript
        updateInsertButtonState()
    }
    
    func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        // 当所有项目都被移除时，重置扫描文本
        if allItems.isEmpty {
            scannedText = ""
        } else if let firstItem = allItems.first,
                  case .text(let textItem) = firstItem {
            scannedText = textItem.transcript
        } else {
            scannedText = ""
        }
        updateInsertButtonState()
    }
    
    private func updateInsertButtonState() {
        DispatchQueue.main.async {
            if !self.scannedText.isEmpty {
                self.insertButton?.backgroundColor = UIColor.systemBlue
                self.insertButton?.isEnabled = true
            } else {
                self.insertButton?.backgroundColor = UIColor.systemGray
                self.insertButton?.isEnabled = false
            }
        }
    }
}

struct TextView_Previews: PreviewProvider {
    @State static var text = "Hello world"
    @State static var selection: Range<String.Index>? = nil
    @State static var showingScanner = false
    
    static var previews: some View {
        TextView(text: $text, selection: $selection, shouldChangeText: nil, showingScanner: $showingScanner)
    }
}
