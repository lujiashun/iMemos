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
        struct TagPair {
            let openStart: Int
            let openEnd: Int
            let closeStart: Int
            let closeEnd: Int
            let isUnderline: Bool
        }
        
        var tagPairs: [TagPair] = []
        
        var currentText = html
        var totalRemoved = 0
        
        while true {
            let uRange = currentText.range(of: "<u>")
            let markRange = currentText.range(of: "<mark>")
            
            var openTagRange: Range<String.Index>?
            var isUnderline = false
            
            if let u = uRange, let mark = markRange {
                if u.lowerBound < mark.lowerBound {
                    openTagRange = u
                    isUnderline = true
                } else {
                    openTagRange = mark
                    isUnderline = false
                }
            } else if let u = uRange {
                openTagRange = u
                isUnderline = true
            } else if let mark = markRange {
                openTagRange = mark
                isUnderline = false
            }
            
            guard let openRange = openTagRange else { break }
            
            let closeTag = isUnderline ? "</u>" : "</mark>"
            guard let closeRange = currentText.range(of: closeTag, range: openRange.upperBound..<currentText.endIndex) else {
                currentText.removeSubrange(openRange.lowerBound..<openRange.upperBound)
                continue
            }
            
            let openStart = currentText.distance(from: currentText.startIndex, to: openRange.lowerBound) + totalRemoved
            let openEnd = currentText.distance(from: currentText.startIndex, to: openRange.upperBound) + totalRemoved
            let closeStart = currentText.distance(from: currentText.startIndex, to: closeRange.lowerBound) + totalRemoved
            let closeEnd = currentText.distance(from: currentText.startIndex, to: closeRange.upperBound) + totalRemoved
            
            tagPairs.append(TagPair(openStart: openStart, openEnd: openEnd, closeStart: closeStart, closeEnd: closeEnd, isUnderline: isUnderline))
            
            let openTagLen = currentText.distance(from: openRange.lowerBound, to: openRange.upperBound)
            let closeTagLen = currentText.distance(from: closeRange.lowerBound, to: closeRange.upperBound)
            totalRemoved += openTagLen + closeTagLen
            
            currentText.removeSubrange(closeRange.lowerBound..<closeRange.upperBound)
            currentText.removeSubrange(openRange.lowerBound..<openRange.upperBound)
        }
        
        var result = AttributedString(currentText)
        
        print("📝 [Load] 输入: \(html)")
        print("📝 [Load] 纯文本: \(currentText)")
        print("📝 [Load] 标签数量: \(tagPairs.count)")
        
        for pair in tagPairs {
            var adjustedStart = pair.openEnd
            var adjustedEnd = pair.closeStart
            
            for earlier in tagPairs {
                if earlier.openStart < pair.openStart {
                    let openTagLen = earlier.openEnd - earlier.openStart
                    let closeTagLen = earlier.closeEnd - earlier.closeStart
                    adjustedStart -= (openTagLen + closeTagLen)
                    adjustedEnd -= (openTagLen + closeTagLen)
                }
            }
            
            print("📝 [Load] 标签: \(pair.isUnderline ? "<u>" : "<mark>"), 调整后位置: \(adjustedStart)-\(adjustedEnd)")
            
            guard adjustedStart >= 0 && adjustedEnd <= currentText.count && adjustedStart < adjustedEnd else {
                print("📝 [Load] 位置无效，跳过")
                continue
            }
            
            let startIndex = result.characters.index(result.characters.startIndex, offsetBy: adjustedStart)
            let endIndex = result.characters.index(result.characters.startIndex, offsetBy: adjustedEnd)
            
            if pair.isUnderline {
                result[startIndex..<endIndex].underlineStyle = .single
            } else {
                #if canImport(UIKit)
                result[startIndex..<endIndex].backgroundColor = Color(UIColor.systemYellow.withAlphaComponent(0.3))
                #else
                result[startIndex..<endIndex].backgroundColor = .yellow.opacity(0.3)
                #endif
            }
        }
        
        return result
    }
}
