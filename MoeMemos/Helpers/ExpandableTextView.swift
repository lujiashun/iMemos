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
            let contentStart: Int
            let contentEnd: Int
            let isUnderline: Bool
        }
        
        var tagPairs: [TagPair] = []
        var resultText = html
        
        while true {
            let uRange = resultText.range(of: "<u>")
            let markRange = resultText.range(of: "<mark>")
            
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
            guard let closeRange = resultText.range(of: closeTag, range: openRange.upperBound..<resultText.endIndex) else {
                resultText.removeSubrange(openRange.lowerBound..<openRange.upperBound)
                continue
            }
            
            let contentStart = resultText.distance(from: resultText.startIndex, to: openRange.upperBound)
            let contentEnd = resultText.distance(from: resultText.startIndex, to: closeRange.lowerBound)
            
            tagPairs.append(TagPair(contentStart: contentStart, contentEnd: contentEnd, isUnderline: isUnderline))
            
            resultText.removeSubrange(closeRange.lowerBound..<closeRange.upperBound)
            resultText.removeSubrange(openRange.lowerBound..<openRange.upperBound)
        }
        
        var result = AttributedString(resultText)
        
        for tag in tagPairs {
            guard tag.contentStart >= 0 && tag.contentEnd <= resultText.count && tag.contentStart < tag.contentEnd else { continue }
            
            let startIndex = result.characters.index(result.characters.startIndex, offsetBy: tag.contentStart)
            let endIndex = result.characters.index(result.characters.startIndex, offsetBy: tag.contentEnd)
            
            if tag.isUnderline {
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
