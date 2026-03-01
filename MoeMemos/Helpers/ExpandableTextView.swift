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
            let openTagRange: Range<String.Index>
            let closeTagRange: Range<String.Index>
            let contentRange: Range<String.Index>
            let isUnderline: Bool
        }
        
        var tagPairs: [TagPair] = []
        var searchStart = html.startIndex
        
        while searchStart < html.endIndex {
            let searchRange = searchStart..<html.endIndex
            
            guard let openTagRange = html.range(of: "<u>", options: [], range: searchRange) ??
                                      html.range(of: "<mark>", options: [], range: searchRange) else {
                break
            }
            
            let isUnderline = html[openTagRange] == "<u>"
            let closeTag = isUnderline ? "</u>" : "</mark>"
            
            guard let closeTagRange = html.range(of: closeTag, options: [], range: openTagRange.upperBound..<html.endIndex) else {
                searchStart = openTagRange.upperBound
                continue
            }
            
            let contentRange = openTagRange.upperBound..<closeTagRange.lowerBound
            tagPairs.append(TagPair(
                openTagRange: openTagRange,
                closeTagRange: closeTagRange,
                contentRange: contentRange,
                isUnderline: isUnderline
            ))
            
            searchStart = closeTagRange.upperBound
        }
        
        var resultText = html
        var offset = 0
        
        for pair in tagPairs.sorted(by: { $0.openTagRange.lowerBound < $1.openTagRange.lowerBound }) {
            let openTagLength = pair.openTagRange.upperBound - pair.openTagRange.lowerBound
            let closeTagLength = pair.closeTagRange.upperBound - pair.closeTagRange.lowerBound
            offset += openTagLength + closeTagLength
        }
        
        let plainText = html
            .replacingOccurrences(of: "<u>", with: "")
            .replacingOccurrences(of: "</u>", with: "")
            .replacingOccurrences(of: "<mark>", with: "")
            .replacingOccurrences(of: "</mark>", with: "")
        
        var result = AttributedString(plainText)
        
        for pair in tagPairs {
            let openStart = html.distance(from: html.startIndex, to: pair.openTagRange.lowerBound)
            let contentEnd = html.distance(from: html.startIndex, to: pair.contentRange.upperBound)
            
            var adjustedStart = openStart
            var adjustedEnd = contentEnd
            
            for earlierPair in tagPairs {
                if earlierPair.openTagRange.lowerBound < pair.openTagRange.lowerBound {
                    let openTagLength = html.distance(from: earlierPair.openTagRange.lowerBound, to: earlierPair.openTagRange.upperBound)
                    let closeTagLength = html.distance(from: earlierPair.closeTagRange.lowerBound, to: earlierPair.closeTagRange.upperBound)
                    adjustedStart -= (openTagLength + closeTagLength)
                    adjustedEnd -= (openTagLength + closeTagLength)
                }
            }
            
            let startIndex = result.characters.index(result.characters.startIndex, offsetBy: adjustedStart)
            let endIndex = result.characters.index(result.characters.startIndex, offsetBy: adjustedEnd)
            
            guard startIndex < endIndex && endIndex <= result.characters.endIndex else { continue }
            
            if pair.isUnderline {
                result[startIndex..<endIndex].underlineStyle = .single
            } else {
                result[startIndex..<endIndex].backgroundColor = .yellow.opacity(0.3)
            }
        }
        
        return result
    }
}
