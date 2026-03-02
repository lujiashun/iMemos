//
//  ExpandableTextView.swift
//  MoeMemos
//
//  Created by AI Assistant on 2026/3/1.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MarkdownUI)
@preconcurrency import MarkdownUI
#endif
import Models

// MARK: - 可展开文本视图
// 功能：当文本超过指定行数时，显示展开/收起按钮
// 支持标签点击交互

struct ExpandableTextView: View {
    // MARK: - 配置参数
    let text: String
    let maxLines: Int
    let font: Font
    let lineSpacing: CGFloat
    var onTagTapped: ((String) -> Void)? = nil
    
    // MARK: - 状态
    @State private var isExpanded: Bool = false
    @State private var cachedAttributedString: AttributedString?
    @State private var isTruncated: Bool = false
    @State private var hasCalculatedTruncation: Bool = false
    
    // MARK: - 初始化
    init(
        text: String,
        maxLines: Int = 6,
        font: Font = .body,
        lineSpacing: CGFloat = 4,
        onTagTapped: ((String) -> Void)? = nil
    ) {
        self.text = text
        self.maxLines = maxLines
        self.font = font
        self.lineSpacing = lineSpacing
        self.onTagTapped = onTagTapped
    }
    
    // MARK: - 主体视图
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 文本内容
            if let attributedString = cachedAttributedString {
                Text(attributedString)
                    .font(font)
                    .lineSpacing(lineSpacing)
                    .lineLimit(isExpanded ? nil : maxLines)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            } else {
                Text(text)
                    .font(font)
                    .lineSpacing(lineSpacing)
                    .lineLimit(isExpanded ? nil : maxLines)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
            
            // 展开/收起按钮（仅在文本被截断时显示）
            if isTruncated {
                expandButton
            }
        }
        .onAppear {
            if cachedAttributedString == nil {
                cachedAttributedString = parseRichText(text)
            }
            // 延迟计算截断状态，确保布局完成
            if !hasCalculatedTruncation {
                DispatchQueue.main.async {
                    calculateTruncation()
                }
            }
        }
        .onChange(of: text) { _, newText in
            cachedAttributedString = parseRichText(newText)
            hasCalculatedTruncation = false
            isTruncated = false
            DispatchQueue.main.async {
                calculateTruncation()
            }
        }
    }
    
    // MARK: - 展开/收起按钮
    private var expandButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 4) {
                Text(isExpanded ? "收起" : "展开")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
    
    // MARK: - 核心逻辑：计算文本是否需要截断
    private func calculateTruncation() {
        #if canImport(UIKit)
        // 获取纯文本内容
        let plainText: String
        if let attrString = cachedAttributedString {
            plainText = String(attrString.characters)
        } else {
            plainText = text
        }
        
        // 获取屏幕宽度（减去列表边距）
        let screenWidth = UIScreen.main.bounds.width
        let horizontalPadding: CGFloat = 32
        let availableWidth = screenWidth - horizontalPadding
        
        // 创建字体和段落样式
        let uiFont = UIFont.preferredFont(forTextStyle: .body)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .paragraphStyle: paragraphStyle
        ]
        
        // 计算单行高度
        let singleLineHeight = uiFont.lineHeight + lineSpacing
        
        // 计算限制行数的最大高度
        let maxAllowedHeight = singleLineHeight * CGFloat(maxLines)
        
        // 计算文本完整高度（无行数限制）
        let nsString = plainText as NSString
        let unlimitedRect = nsString.boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        
        // 判断是否需要截断
        let needsTruncation = unlimitedRect.height > maxAllowedHeight + 5
        
        DispatchQueue.main.async {
            self.isTruncated = needsTruncation
            self.hasCalculatedTruncation = true
        }
        #else
        DispatchQueue.main.async {
            self.hasCalculatedTruncation = true
        }
        #endif
    }
    
    // MARK: - 解析富文本（支持下划线、高亮和标签）
    private func parseRichText(_ html: String) -> AttributedString {
        let plainText = html
            .replacingOccurrences(of: "<u>", with: "")
            .replacingOccurrences(of: "</u>", with: "")
            .replacingOccurrences(of: "<mark>", with: "")
            .replacingOccurrences(of: "</mark>", with: "")
            .replacingOccurrences(of: "<tag>", with: "")
            .replacingOccurrences(of: "</tag>", with: "")
        
        var result = AttributedString(plainText)
        
        applyStyles(from: html, to: &result, plainText: plainText)
        
        return result
    }
    
    // MARK: - 应用样式（下划线、高亮和标签）
    private func applyStyles(from html: String, to result: inout AttributedString, plainText: String) {
        var htmlIndex = html.startIndex
        var plainIndex = plainText.startIndex
        var htmlOffset = 0
        var plainOffset = 0
        
        var underlineStack: [Int] = []
        var highlightStack: [Int] = []
        var tagStack: [Int] = []
        
        while htmlIndex < html.endIndex {
            if html[htmlIndex...].hasPrefix("<u>") {
                let plainOffsetAtTag = plainOffset
                underlineStack.append(plainOffsetAtTag)
                htmlIndex = html.index(htmlIndex, offsetBy: 3)
                htmlOffset += 3
            } else if html[htmlIndex...].hasPrefix("</u>") {
                if let startOffset = underlineStack.popLast() {
                    let endOffset = plainOffset
                    if startOffset < endOffset {
                        let startIndex = result.characters.index(result.characters.startIndex, offsetBy: startOffset)
                        let endIndex = result.characters.index(result.characters.startIndex, offsetBy: endOffset)
                        result[startIndex..<endIndex].underlineStyle = .single
                    }
                }
                htmlIndex = html.index(htmlIndex, offsetBy: 4)
                htmlOffset += 4
            } else if html[htmlIndex...].hasPrefix("<mark>") {
                let plainOffsetAtTag = plainOffset
                highlightStack.append(plainOffsetAtTag)
                htmlIndex = html.index(htmlIndex, offsetBy: 6)
                htmlOffset += 6
            } else if html[htmlIndex...].hasPrefix("</mark>") {
                if let startOffset = highlightStack.popLast() {
                    let endOffset = plainOffset
                    if startOffset < endOffset {
                        let startIndex = result.characters.index(result.characters.startIndex, offsetBy: startOffset)
                        let endIndex = result.characters.index(result.characters.startIndex, offsetBy: endOffset)
                        #if canImport(UIKit)
                        result[startIndex..<endIndex].backgroundColor = Color(UIColor.systemYellow.withAlphaComponent(0.3))
                        #else
                        result[startIndex..<endIndex].backgroundColor = .yellow.opacity(0.3)
                        #endif
                    }
                }
                htmlIndex = html.index(htmlIndex, offsetBy: 7)
                htmlOffset += 7
            } else if html[htmlIndex...].hasPrefix("<tag>") {
                let plainOffsetAtTag = plainOffset
                tagStack.append(plainOffsetAtTag)
                htmlIndex = html.index(htmlIndex, offsetBy: 5)
                htmlOffset += 5
            } else if html[htmlIndex...].hasPrefix("</tag>") {
                if let startOffset = tagStack.popLast() {
                    let endOffset = plainOffset
                    if startOffset < endOffset {
                        let startIndex = result.characters.index(result.characters.startIndex, offsetBy: startOffset)
                        let endIndex = result.characters.index(result.characters.startIndex, offsetBy: endOffset)
                        #if canImport(UIKit)
                        // MARK: 标签样式：蓝色字体+灰色背景
                        result[startIndex..<endIndex].foregroundColor = Color(UIColor.systemBlue)
                        result[startIndex..<endIndex].backgroundColor = Color(UIColor.lightGray.withAlphaComponent(0.3))
                        #else
                        result[startIndex..<endIndex].foregroundColor = .blue
                        result[startIndex..<endIndex].backgroundColor = .gray.opacity(0.3)
                        #endif
                    }
                }
                htmlIndex = html.index(htmlIndex, offsetBy: 6)
                htmlOffset += 6
            } else {
                htmlIndex = html.index(after: htmlIndex)
                if plainIndex < plainText.endIndex {
                    plainIndex = plainText.index(after: plainIndex)
                    plainOffset += 1
                }
            }
        }
    }
}

// MARK: - 可点击标签的文本视图（用于灵感页面）
struct ClickableTagTextView: UIViewRepresentable {
    let text: String
    let maxLines: Int
    var onTagTapped: ((String) -> Void)?
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isSelectable = true
        textView.dataDetectorTypes = []
        
        // 添加点击手势
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        textView.addGestureRecognizer(tapGesture)
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        let attributedString = context.coordinator.parseRichText(text)
        textView.attributedText = attributedString
        
        // 设置行数限制
        textView.textContainer.maximumNumberOfLines = context.coordinator.isExpanded ? 0 : maxLines
        textView.textContainer.lineBreakMode = .byTruncatingTail
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ClickableTagTextView
        var isExpanded: Bool = false
        var tagRanges: [(range: NSRange, tagName: String)] = []
        
        init(_ parent: ClickableTagTextView) {
            self.parent = parent
        }
        
        func parseRichText(_ html: String) -> NSAttributedString {
            // 先移除 HTML 标签获取纯文本
            let plainText = html
                .replacingOccurrences(of: "<u>", with: "")
                .replacingOccurrences(of: "</u>", with: "")
                .replacingOccurrences(of: "<mark>", with: "")
                .replacingOccurrences(of: "</mark>", with: "")
                .replacingOccurrences(of: "<tag>", with: "")
                .replacingOccurrences(of: "</tag>", with: "")
            
            let mutableAttrString = NSMutableAttributedString(string: plainText)
            let defaultFont = UIFont.preferredFont(forTextStyle: .body)
            
            // 应用默认字体
            let fullRange = NSRange(location: 0, length: mutableAttrString.length)
            mutableAttrString.addAttribute(.font, value: defaultFont, range: fullRange)
            
            // 清空标签范围
            tagRanges = []
            
            // MARK: - 解析 HTML 标签格式（<tag>...</tag>）
            var htmlIndex = html.startIndex
            var plainOffset = 0
            
            var underlineStack: [Int] = []
            var highlightStack: [Int] = []
            var tagStack: [Int] = []
            
            while htmlIndex < html.endIndex {
                if html[htmlIndex...].hasPrefix("<u>") {
                    underlineStack.append(plainOffset)
                    htmlIndex = html.index(htmlIndex, offsetBy: 3)
                } else if html[htmlIndex...].hasPrefix("</u>") {
                    if let startOffset = underlineStack.popLast(), plainOffset > startOffset {
                        let range = NSRange(location: startOffset, length: plainOffset - startOffset)
                        mutableAttrString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    }
                    htmlIndex = html.index(htmlIndex, offsetBy: 4)
                } else if html[htmlIndex...].hasPrefix("<mark>") {
                    highlightStack.append(plainOffset)
                    htmlIndex = html.index(htmlIndex, offsetBy: 6)
                } else if html[htmlIndex...].hasPrefix("</mark>") {
                    if let startOffset = highlightStack.popLast(), plainOffset > startOffset {
                        let range = NSRange(location: startOffset, length: plainOffset - startOffset)
                        mutableAttrString.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: range)
                    }
                    htmlIndex = html.index(htmlIndex, offsetBy: 7)
                } else if html[htmlIndex...].hasPrefix("<tag>") {
                    tagStack.append(plainOffset)
                    htmlIndex = html.index(htmlIndex, offsetBy: 5)
                } else if html[htmlIndex...].hasPrefix("</tag>") {
                    if let startOffset = tagStack.popLast(), plainOffset > startOffset {
                        let range = NSRange(location: startOffset, length: plainOffset - startOffset)
                        // 应用标签样式
                        mutableAttrString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
                        mutableAttrString.addAttribute(.backgroundColor, value: UIColor.lightGray.withAlphaComponent(0.3), range: range)
                        
                        // 记录标签范围用于点击检测
                        let tagName = (plainText as NSString).substring(with: range)
                        tagRanges.append((range: range, tagName: tagName))
                    }
                    htmlIndex = html.index(htmlIndex, offsetBy: 6)
                } else {
                    htmlIndex = html.index(after: htmlIndex)
                    plainOffset += 1
                }
            }
            
            // MARK: - 解析普通标签格式（#标签名）
            // 匹配 #标签名 格式（后面跟空格、斜杠、换行或结尾）
            let tagPattern = "#([^#\\s/]+?)(?=[\\s/\\n]|$)"
            guard let regex = try? NSRegularExpression(pattern: tagPattern, options: []) else {
                return mutableAttrString
            }
            
            let plainNsString = plainText as NSString
            let matches = regex.matches(in: plainText, options: [], range: fullRange)
            
            for match in matches.reversed() {
                let range = match.range
                let tagName = plainNsString.substring(with: range)
                
                // 检查是否已经被 <tag> 标记过
                var alreadyTagged = false
                for tagInfo in tagRanges {
                    if NSIntersectionRange(tagInfo.range, range).length > 0 {
                        alreadyTagged = true
                        break
                    }
                }
                
                if !alreadyTagged {
                    // 应用标签样式
                    mutableAttrString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
                    mutableAttrString.addAttribute(.backgroundColor, value: UIColor.lightGray.withAlphaComponent(0.3), range: range)
                    
                    // 记录标签范围
                    tagRanges.append((range: range, tagName: tagName))
                }
            }
            
            return mutableAttrString
        }
        
        // MARK: - 处理点击手势
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            
            let location = gesture.location(in: textView)
            let characterIndex = textView.layoutManager.characterIndex(for: location, in: textView.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            
            // 检查点击位置是否在标签范围内
            for tagInfo in tagRanges {
                if NSLocationInRange(characterIndex, tagInfo.range) {
                    // MARK: 触发标签点击回调
                    // 提供触觉反馈
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    
                    parent.onTagTapped?(tagInfo.tagName)
                    return
                }
            }
        }
        
        // MARK: - UITextViewDelegate
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            return false
        }
    }
}

// MARK: - 预览
#Preview {
    ScrollView {
        VStack(spacing: 20) {
            ExpandableTextView(
                text: "这是一段短文本，不需要展开。",
                maxLines: 6
            )
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            ExpandableTextView(
                text: """
                这是一段很长的文本内容，用于测试展开/收起功能。
                第二行内容：SwiftUI 是一种现代化的声明式 UI 框架。
                第三行内容：它让开发者可以用更少的代码构建用户界面。
                第四行内容：通过组合简单的视图，可以创建复杂的界面。
                第五行内容：状态管理是 SwiftUI 的核心概念之一。
                第六行内容：当状态改变时，视图会自动更新。
                第七行内容：这是超过六行的内容，应该显示展开按钮。
                """,
                maxLines: 6
            )
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
    }
}
