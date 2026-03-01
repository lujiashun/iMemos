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

struct ExpandableTextView: View {
    let text: String
    let maxLines: Int
    let font: Font
    let lineSpacing: CGFloat
    
    @State private var isExpanded: Bool = false
    @State private var isTruncated: Bool = false
    
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if canImport(UIKit)
            ExpandableUILabel(
                attributedText: parseRichText(text),
                maxLines: maxLines,
                isExpanded: isExpanded,
                isTruncated: $isTruncated
            )
            #else
            Text(text)
                .font(font)
                .lineSpacing(lineSpacing)
                .lineLimit(isExpanded ? nil : maxLines)
            #endif
            
            if isTruncated {
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
        }
    }
    
    private func parseRichText(_ html: String) -> NSAttributedString {
        let mutableAttrString = NSMutableAttributedString(string: html)
        let defaultFont = UIFont.preferredFont(forTextStyle: .body)
        
        var result = mutableAttrString
        var currentString = result.string
        
        while true {
            var foundTag = false
            
            let uStartRange = currentString.range(of: "<u>")
            let markStartRange = currentString.range(of: "<mark>")
            
            let shouldProcessUnderline: Bool
            if let uStart = uStartRange, let markStart = markStartRange {
                shouldProcessUnderline = uStart.lowerBound < markStart.lowerBound
            } else {
                shouldProcessUnderline = uStartRange != nil
            }
            
            if shouldProcessUnderline,
               let uStart = uStartRange,
               let uEnd = currentString.range(of: "</u>", range: uStart.upperBound..<currentString.endIndex) {
                foundTag = true
                
                let contentRange = uStart.upperBound..<uEnd.lowerBound
                let content = String(currentString[contentRange])
                
                let nsRange = NSRange(uStart.lowerBound..<uEnd.upperBound, in: currentString)
                result.replaceCharacters(in: nsRange, with: content)
                
                let newContentRange = NSRange(location: nsRange.location, length: content.count)
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: newContentRange)
                result.addAttribute(.font, value: defaultFont, range: newContentRange)
                
                currentString = result.string
            } else if let markStart = markStartRange,
                      let markEnd = currentString.range(of: "</mark>", range: markStart.upperBound..<currentString.endIndex) {
                foundTag = true
                
                let contentRange = markStart.upperBound..<markEnd.lowerBound
                let content = String(currentString[contentRange])
                
                let nsRange = NSRange(markStart.lowerBound..<markEnd.upperBound, in: currentString)
                result.replaceCharacters(in: nsRange, with: content)
                
                let newContentRange = NSRange(location: nsRange.location, length: content.count)
                result.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: newContentRange)
                result.addAttribute(.font, value: defaultFont, range: newContentRange)
                
                currentString = result.string
            }
            
            if !foundTag {
                break
            }
        }
        
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.font, value: defaultFont, range: fullRange)
        
        return result
    }
}

#if canImport(UIKit)
struct ExpandableUILabel: UIViewRepresentable {
    let attributedText: NSAttributedString
    let maxLines: Int
    let isExpanded: Bool
    @Binding var isTruncated: Bool
    
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }
    
    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.attributedText = attributedText
        uiView.numberOfLines = isExpanded ? 0 : maxLines
        
        DispatchQueue.main.async {
            let textSize = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude))
            let limitedHeight = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude))
            
            uiView.numberOfLines = isExpanded ? 0 : maxLines
            let limitedTextSize = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude))
            
            self.isTruncated = textSize.height > limitedTextSize.height + 5
        }
    }
}
#endif
    
    /// 计算文本是否需要截断
    /// 方法：比较文本在无限行数和限制行数下的高度
    private func calculateTruncation(in width: CGFloat) {
        // 使用 NSString 的 boundingRect 方法计算文本高度
        let nsString = text as NSString
        
        // 创建字体属性
        let uiFont = UIFont.preferredFont(forTextStyle: textStyleFromFont(font))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .paragraphStyle: paragraphStyle
        ]
        
        // 计算无限行数时的总高度（实际内容高度）
        let unlimitedRect = nsString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        
        // 计算限制行数时的高度
        let maxHeight = calculateMaxHeight(for: maxLines, font: uiFont, lineSpacing: lineSpacing, width: width)
        
        // 如果实际高度大于限制高度，则需要截断
        DispatchQueue.main.async {
            self.isTruncated = unlimitedRect.height > maxHeight + uiFont.lineHeight * 0.5 // 添加容错值
        }
    }
    
    /// 计算指定行数的最大高度
    private func calculateMaxHeight(for lines: Int, font: UIFont, lineSpacing: CGFloat, width: CGFloat) -> CGFloat {
        // 创建测试文本：指定行数的 "W" 字符（最高字符）
        let testText = String(repeating: "W\n", count: lines).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        
        let rect = (testText as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        
        return rect.height
    }
    
    /// 将 SwiftUI Font 转换为 UIFont.TextStyle
    private func textStyleFromFont(_ font: Font) -> UIFont.TextStyle {
        // 根据字体特征推断文本样式
        let fontDescription = String(describing: font)
        if fontDescription.contains("largeTitle") { return .largeTitle }
        if fontDescription.contains("title") { return .title1 }
        if fontDescription.contains("headline") { return .headline }
        if fontDescription.contains("subheadline") { return .subheadline }
        if fontDescription.contains("body") { return .body }
        if fontDescription.contains("callout") { return .callout }
        if fontDescription.contains("footnote") { return .footnote }
        if fontDescription.contains("caption") { return .caption1 }
        return .body
    }
}

// MARK: - 使用示例

struct ExpandableTextView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 示例1：短文本（不需要展开）
                ExpandableTextView(
                    text: "这是一段短文本，不需要展开。",
                    maxLines: 6
                )
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // 示例2：长文本（需要展开）
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
                
                // 示例3：自定义字体
                ExpandableTextView(
                    text: """
                    使用自定义字体的长文本示例。
                    第二行内容。
                    第三行内容。
                    第四行内容。
                    第五行内容。
                    第六行内容。
                    第七行内容，应该显示展开按钮。
                    第八行内容。
                    """,
                    maxLines: 5,
                    font: .subheadline,
                    lineSpacing: 6
                )
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
    }
}

// MARK: - 在 MemoCardContent 中使用的扩展

extension MemoCardContent {
    /// 使用 ExpandableTextView 替代普通文本显示
    /// 用于"灵感"页面的 memos 文本展示
    var expandableBody: some View {
        VStack(alignment: .leading) {
            #if canImport(MarkdownUI)
            // 对于 Markdown 内容，使用原生方式
            // 注意：MarkdownUI 暂不支持动态行数限制
            MarkdownView(memo.content)
                .markdownImageProvider(.lazyImage(aspectRatio: 4 / 3))
                .markdownCodeSyntaxHighlighter(colorScheme == .dark ? .dark() : .light())
            #else
            // 使用可展开文本视图
            ExpandableTextView(
                text: memo.content,
                maxLines: 6,
                font: .body,
                lineSpacing: 4
            )
            #endif
        }
    }
}
