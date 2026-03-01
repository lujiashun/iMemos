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
            let openTagStart: Int
            let openTagEnd: Int
            let closeTagStart: Int
            let closeTagEnd: Int
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
            
            let openTagStart = html.distance(from: html.startIndex, to: openTagRange.lowerBound)
            let openTagEnd = html.distance(from: html.startIndex, to: openTagRange.upperBound)
            let closeTagStart = html.distance(from: html.startIndex, to: closeTagRange.lowerBound)
            let closeTagEnd = html.distance(from: html.startIndex, to: closeTagRange.upperBound)
            
            tagPairs.append(TagPair(
                openTagStart: openTagStart,
                openTagEnd: openTagEnd,
                closeTagStart: closeTagStart,
                closeTagEnd: closeTagEnd,
                isUnderline: isUnderline
            ))
            
            searchStart = closeTagRange.upperBound
        }
        
        let plainText = html
            .replacingOccurrences(of: "<u>", with: "")
            .replacingOccurrences(of: "</u>", with: "")
            .replacingOccurrences(of: "<mark>", with: "")
            .replacingOccurrences(of: "</mark>", with: "")
        
        var result = AttributedString(plainText)
        
        for pair in tagPairs {
            var adjustedStart = pair.openTagStart
            var adjustedEnd = pair.closeTagStart
            
            for earlierPair in tagPairs {
                if earlierPair.openTagStart < pair.openTagStart {
                    let openTagLength = earlierPair.openTagEnd - earlierPair.openTagStart
                    let closeTagLength = earlierPair.closeTagEnd - earlierPair.closeTagStart
                    adjustedStart -= (openTagLength + closeTagLength)
                    adjustedEnd -= (openTagLength + closeTagLength)
                }
            }
            
            guard adjustedStart >= 0 && adjustedEnd <= plainText.count && adjustedStart < adjustedEnd else { continue }
            
            let startIndex = result.characters.index(result.characters.startIndex, offsetBy: adjustedStart)
            let endIndex = result.characters.index(result.characters.startIndex, offsetBy: adjustedEnd)
            
            if pair.isUnderline {
                result[startIndex..<endIndex].underlineStyle = .single
            } else {
                result[startIndex..<endIndex].backgroundColor = .yellow.opacity(0.3)
            }
        }
        
        return result
    }
}
