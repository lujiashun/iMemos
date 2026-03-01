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
        var currentText = html
        
        var underlineRanges: [Range<String.Index>] = []
        var highlightRanges: [Range<String.Index>] = []
        
        while let uStart = currentText.range(of: "<u>"),
              let uEnd = currentText.range(of: "</u>", range: uStart.upperBound..<currentText.endIndex) {
            let contentStart = uStart.upperBound
            let contentEnd = uEnd.lowerBound
            underlineRanges.append(contentStart..<contentEnd)
            currentText.removeSubrange(uEnd.lowerBound..<uEnd.upperBound)
            currentText.removeSubrange(uStart.lowerBound..<uStart.upperBound)
        }
        
        while let markStart = currentText.range(of: "<mark>"),
              let markEnd = currentText.range(of: "</mark>", range: markStart.upperBound..<currentText.endIndex) {
            let contentStart = markStart.upperBound
            let contentEnd = markEnd.lowerBound
            highlightRanges.append(contentStart..<contentEnd)
            currentText.removeSubrange(markEnd.lowerBound..<markEnd.upperBound)
            currentText.removeSubrange(markStart.lowerBound..<markStart.upperBound)
        }
        
        var result = AttributedString(currentText)
        
        for range in underlineRanges.reversed() {
            let startIndex = result.characters.index(result.characters.startIndex, offsetBy: currentText.distance(from: currentText.startIndex, to: range.lowerBound))
            let endIndex = result.characters.index(result.characters.startIndex, offsetBy: currentText.distance(from: currentText.startIndex, to: range.upperBound))
            result[startIndex..<endIndex].underlineStyle = .single
        }
        
        for range in highlightRanges.reversed() {
            let startIndex = result.characters.index(result.characters.startIndex, offsetBy: currentText.distance(from: currentText.startIndex, to: range.lowerBound))
            let endIndex = result.characters.index(result.characters.startIndex, offsetBy: currentText.distance(from: currentText.startIndex, to: range.upperBound))
            result[startIndex..<endIndex].backgroundColor = .yellow.opacity(0.3)
        }
        
        return result
    }
}
