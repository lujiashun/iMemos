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
    @State private var cachedAttributedString: AttributedString?
    
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
            if let attributedString = cachedAttributedString {
                Text(attributedString)
                    .font(font)
                    .lineSpacing(lineSpacing)
                    .lineLimit(isExpanded ? nil : maxLines)
            } else {
                Text(text)
                    .font(font)
                    .lineSpacing(lineSpacing)
                    .lineLimit(isExpanded ? nil : maxLines)
            }
        }
        .onAppear {
            if cachedAttributedString == nil {
                cachedAttributedString = parseRichText(text)
            }
        }
        .onChange(of: text) { _, newText in
            cachedAttributedString = parseRichText(newText)
        }
    }
    
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
