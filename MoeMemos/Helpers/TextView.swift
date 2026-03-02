//  TextView.swift
//  MoeMemos
//
//  Created by Mudkip on 2023/6/12.
//

import SwiftUI
import VisionKit
import UIKit

struct TextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?
    @Binding var attributedText: NSAttributedString?
    @Binding var inputMode: TextFormatMode?
    let shouldChangeText: ((_ range: Range<String.Index>, _ replacementText: String) -> Bool)?
    @Binding var showingScanner: Bool
    var onScanComplete: ((String) -> Void)?
    var onTextInsert: ((_ range: NSRange, _ text: String) -> NSAttributedString?)?
    
    func makeUIView(context: Context) -> ScannerTextView {
        let textView = ScannerTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        print("📝 [TextView] makeUIView called, delegate set: \(textView.delegate != nil)")
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
        
        var attrs = uiView.typingAttributes ?? [:]
        if let mode = inputMode {
            if mode.contains(.underline) {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                attrs.removeValue(forKey: .underlineStyle)
            }
            if mode.contains(.highlight) {
                attrs[.backgroundColor] = UIColor.systemYellow.withAlphaComponent(0.3)
            } else {
                attrs.removeValue(forKey: .backgroundColor)
            }
        } else {
            attrs.removeValue(forKey: .underlineStyle)
            attrs.removeValue(forKey: .backgroundColor)
        }
        uiView.typingAttributes = attrs

        if let attributedText = attributedText {
            if !attributedText.isEqual(to: uiView.attributedText) {
                uiView.attributedText = attributedText
            }
        } else if text != uiView.text {
            uiView.text = text
        }
        
        let currentText = attributedText?.string ?? text
        if let selection = selection, selection.upperBound <= currentText.endIndex {
            let range = NSRange(selection, in: currentText)
            if uiView.selectedRange != range {
                uiView.selectedRange = range
            }
        } else {
            if uiView.selectedRange.upperBound != 0 {
                uiView.selectedRange = NSRange()
            }
        }
        
        uiView.showingScanner = showingScanner
    }
    
    @MainActor
    class Coordinator: NSObject, UITextViewDelegate {
        let parent: TextView
        var isUpdatingView = false
        var previousTextLength = 0
        var previousSelectedRange = NSRange(location: 0, length: 0)
        var wasComposing = false
        var composingStartPosition: Int?
        
        init(_ parent: TextView) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            NSLog("📝 [TextView] ===== textViewDidChange called =====")
            
            let currentLength = textView.attributedText.length
            let currentSelectedRange = textView.selectedRange
            let isComposing = textView.markedTextRange != nil
            
            NSLog("📝 [TextView] textViewDidChange: currentLength=\(currentLength), previousLength=\(previousTextLength), currentSelectedRange=\(currentSelectedRange), previousSelectedRange=\(previousSelectedRange), isComposing=\(isComposing), wasComposing=\(wasComposing)")
            
            // MARK: - 实时标签识别和样式应用
            let mutableAttrText = NSMutableAttributedString(attributedString: textView.attributedText)
            let fullRange = NSRange(location: 0, length: mutableAttrText.length)
            guard let currentText = textView.text else { return }
            
            // 识别所有标签（#开头，以空格、换行或结尾结束，标签内容可包含/）
            let tagPattern = "#([^\\s#]+)"
            if let regex = try? NSRegularExpression(pattern: tagPattern, options: []) {
                let matches = regex.matches(in: currentText, options: [], range: fullRange)
                
                // 先清除所有非标签区域的蓝色样式
                mutableAttrText.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                    if let color = value as? UIColor {
                        // 检查是否是标签蓝色
                        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                        // 如果是系统蓝色（蓝色>0.9, 红色<0.2, 绿色<0.6）
                        if blue > 0.9 && red < 0.2 && green < 0.6 {
                            // 检查这个范围是否还是标签
                            var isStillTag = false
                            for match in matches {
                                if NSEqualRanges(match.range, range) {
                                    isStillTag = true
                                    break
                                }
                            }
                            if !isStillTag {
                                // 不再是标签，移除蓝色样式
                                mutableAttrText.removeAttribute(.foregroundColor, range: range)
                                mutableAttrText.removeAttribute(.backgroundColor, range: range)
                            }
                        }
                    }
                }
                
                // 应用标签样式：蓝色字体+透明背景
                for match in matches {
                    let tagRange = match.range
                    // 标签样式：蓝色字体+透明背景
                    mutableAttrText.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: tagRange)
                    mutableAttrText.addAttribute(.backgroundColor, value: UIColor.clear, range: tagRange)
                }
            }
            
            // 更新 attributedText
            textView.attributedText = mutableAttrText
            
            if let onTextInsert = parent.onTextInsert {
                if wasComposing && !isComposing {
                    if let startPos = composingStartPosition {
                        let range = NSRange(location: startPos, length: currentLength - startPos)
                        if range.location >= 0 && range.location + range.length <= currentLength && range.length > 0 {
                            let insertedAttrText = textView.attributedText.attributedSubstring(from: range)
                            let insertedText = insertedAttrText.string
                            NSLog("📝 [TextView] composition ended, checking style for: \"\(insertedText)\" at range: \(range)")
                            
                            let hasUnderline = insertedAttrText.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil
                            let hasHighlight = insertedAttrText.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil
                            
                            if !hasUnderline && !hasHighlight {
                                if let newAttrText = onTextInsert(range, insertedText) {
                                    NSLog("📝 [TextView] style applied successfully")
                                    textView.attributedText = newAttrText
                                    parent._attributedText.wrappedValue = newAttrText
                                    parent._text.wrappedValue = newAttrText.string
                                }
                            } else {
                                NSLog("📝 [TextView] text already has style, skipping")
                            }
                        }
                    }
                    composingStartPosition = nil
                } else if !isComposing {
                    let textAdded = currentLength > previousTextLength
                    
                    if textAdded {
                        let insertedLength = currentLength - previousTextLength
                        let insertStart = previousSelectedRange.location
                        let insertRange = NSRange(location: insertStart, length: insertedLength)
                        
                        NSLog("📝 [TextView] non-composing insert at range: \(insertRange)")
                        
                        if insertRange.location + insertRange.length <= currentLength {
                            let insertedAttrText = textView.attributedText.attributedSubstring(from: insertRange)
                            let insertedText = insertedAttrText.string
                            NSLog("📝 [TextView] detecting inserted text: \"\(insertedText)\" at range: \(insertRange)")
                            
                            let hasUnderline = insertedAttrText.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil
                            let hasHighlight = insertedAttrText.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil
                            
                            if !hasUnderline && !hasHighlight {
                                if let newAttrText = onTextInsert(insertRange, insertedText) {
                                    NSLog("📝 [TextView] applying style to inserted text")
                                    textView.attributedText = newAttrText
                                    parent._attributedText.wrappedValue = newAttrText
                                    parent._text.wrappedValue = newAttrText.string
                                }
                            } else {
                                NSLog("📝 [TextView] text already has style, skipping")
                            }
                        }
                    }
                } else if isComposing && !wasComposing {
                    composingStartPosition = previousSelectedRange.location
                    NSLog("📝 [TextView] composition started at position: \(String(describing: composingStartPosition))")
                }
            }
            
            wasComposing = isComposing
            previousTextLength = textView.attributedText.length
            previousSelectedRange = textView.selectedRange
            
            parent._text.wrappedValue = textView.text
            parent._attributedText.wrappedValue = textView.attributedText
            parent._selection.wrappedValue = Range(textView.selectedRange, in: textView.text)
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingView else { return }
            parent._text.wrappedValue = textView.text
            parent._attributedText.wrappedValue = textView.attributedText
            parent._selection.wrappedValue = Range(textView.selectedRange, in: textView.text)
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if let shouldChangeText = parent.shouldChangeText, let textRange = Range(range, in: textView.text) {
                if !shouldChangeText(textRange, text) {
                    return false
                }
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
    @State static var attributedText: NSAttributedString? = nil
    @State static var inputMode: TextFormatMode? = nil
    @State static var showingScanner = false
    
    static var previews: some View {
        TextView(text: $text, selection: $selection, attributedText: $attributedText, inputMode: $inputMode, shouldChangeText: nil, showingScanner: $showingScanner)
    }
}
