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

// MARK: - 可展开文本视图
// 功能：当文本超过指定行数时，显示展开/收起按钮
// 核心逻辑：使用 NSString.boundingRect 计算文本高度，判断是否需要截断

struct ExpandableTextView: View {
    // MARK: - 配置参数
    let text: String
    let maxLines: Int
    let font: Font
    let lineSpacing: CGFloat
    
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
        lineSpacing: CGFloat = 4
    ) {
        self.text = text
        self.maxLines = maxLines
        self.font = font
        self.lineSpacing = lineSpacing
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
            } else {
                Text(text)
                    .font(font)
                    .lineSpacing(lineSpacing)
                    .lineLimit(isExpanded ? nil : maxLines)
                    .truncationMode(.tail)
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
    // 方法：使用 NSString.boundingRect 计算文本在无限行数和限制行数下的高度差
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
        let horizontalPadding: CGFloat = 32 // 列表左右边距
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
        
        // 判断是否需要截断：完整高度 > 限制高度
        let needsTruncation = unlimitedRect.height > maxAllowedHeight + 5 // 添加5pt容差
        
        DispatchQueue.main.async {
            self.isTruncated = needsTruncation
            self.hasCalculatedTruncation = true
        }
        #else
        // 非 iOS 平台，默认不截断
        DispatchQueue.main.async {
            self.hasCalculatedTruncation = true
        }
        #endif
    }
    
    // MARK: - 解析富文本（支持下划线和高亮）
    private func parseRichText(_ html: String) -> AttributedString {
        let plainText = html
            .replacingOccurrences(of: "<u>", with: "")
            .replacingOccurrences(of: "</u>", with: "")
            .replacingOccurrences(of: "<mark>", with: "")
            .replacingOccurrences(of: "</mark>", with: "")
        
        var result = AttributedString(plainText)
        
        applyStyles(from: html, to: &result, plainText: plainText)
        
        return result
    }
    
    // MARK: - 应用样式（下划线和高亮）
    private func applyStyles(from html: String, to result: inout AttributedString, plainText: String) {
        var htmlIndex = html.startIndex
        var plainIndex = plainText.startIndex
        var htmlOffset = 0
        var plainOffset = 0
        
        var underlineStack: [Int] = []
        var highlightStack: [Int] = []
        
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

// MARK: - 预览
#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // 短文本（不需要展开）
            ExpandableTextView(
                text: "这是一段短文本，不需要展开。",
                maxLines: 6
            )
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // 长文本（需要展开）
            ExpandableTextView(
                text: """
                这是一段很长的文本内容，用于测试展开/收起功能。
                第二行内容：SwiftUI 是一种现代化的声明式 UI 框架。
                第三行内容：它让开发者可以用更少的代码构建用户界面。
                第四行内容：通过组合简单的视图，可以创建复杂的界面。
                第五行内容：状态管理是 SwiftUI 的核心概念之一。
                第六行内容：当状态改变时，视图会自动更新。
                第七行内容：这是超过六行的内容，应该显示展开按钮。
                第八行内容：点击展开按钮可以查看全部内容。
                第九行内容：再次点击可以收起内容。
                第十行内容：这个功能在社交媒体应用中很常见。
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
