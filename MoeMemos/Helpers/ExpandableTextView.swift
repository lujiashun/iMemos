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
        struct TagInfo {
            let openStart: Int
            let openEnd: Int
            let closeStart: Int
            let closeEnd: Int
            let isUnderline: Bool
        }
        
        var tags: [TagInfo] = []
        var searchStart = html.startIndex
        
        while searchStart < html.endIndex {
            let searchRange = searchStart..<html.endIndex
            
            let uRange = html.range(of: "<u>", options: [], range: searchRange)
            let markRange = html.range(of: "<mark>", options: [], range: searchRange)
            
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
            guard let closeRange = html.range(of: closeTag, options: [], range: openRange.upperBound..<html.endIndex) else {
                searchStart = openRange.upperBound
                continue
            }
            
            let openStart = html.distance(from: html.startIndex, to: openRange.lowerBound)
            let openEnd = html.distance(from: html.startIndex, to: openRange.upperBound)
            let closeStart = html.distance(from: html.startIndex, to: closeRange.lowerBound)
            let closeEnd = html.distance(from: html.startIndex, to: closeRange.upperBound)
            
            tags.append(TagInfo(openStart: openStart, openEnd: openEnd, closeStart: closeStart, closeEnd: closeEnd, isUnderline: isUnderline))
            searchStart = closeRange.upperBound
        }
        
        let plainText = html
            .replacingOccurrences(of: "<u>", with: "")
            .replacingOccurrences(of: "</u>", with: "")
            .replacingOccurrences(of: "<mark>", with: "")
            .replacingOccurrences(of: "</mark>", with: "")
        
        var result = AttributedString(plainText)
        
        for tag in tags {
            var contentStart = tag.openEnd
            var contentEnd = tag.closeStart
            
            var offset = 0
            for earlierTag in tags {
                if earlierTag.openStart < tag.openStart {
                    let openTagLen = earlierTag.openEnd - earlierTag.openStart
                    let closeTagLen = earlierTag.closeEnd - earlierTag.closeStart
                    offset += (openTagLen + closeTagLen)
                }
            }
            
            let currentOpenTagLen = tag.openEnd - tag.openStart
            contentStart -= (offset + currentOpenTagLen)
            contentEnd -= (offset + currentOpenTagLen)
            
            guard contentStart >= 0 && contentEnd <= plainText.count && contentStart < contentEnd else { continue }
            
            let startIndex = result.characters.index(result.characters.startIndex, offsetBy: contentStart)
            let endIndex = result.characters.index(result.characters.startIndex, offsetBy: contentEnd)
            
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
