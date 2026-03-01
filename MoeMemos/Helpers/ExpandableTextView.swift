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
        var result = AttributedString(html)
        
        var currentIndex = result.characters.startIndex
        while currentIndex < result.characters.endIndex {
            let substring = result.characters[currentIndex...]
            
            if let uStart = substring.range(of: "<u>"),
               let uEnd = substring.range(of: "</u>", range: uStart.upperBound..<substring.endIndex) {
                let contentRange = uStart.upperBound..<uEnd.lowerBound
                
                result.characters.removeSubrange(uEnd.lowerBound..<uEnd.upperBound)
                result.characters.removeSubrange(uStart.lowerBound..<uStart.upperBound)
                
                let newContentRange = result.characters.index(uStart.lowerBound, offsetBy: 0)..<result.characters.index(uStart.lowerBound, offsetBy: contentRange.count)
                result[newContentRange].underlineStyle = .single
                
                currentIndex = result.characters.index(after: newContentRange.upperBound)
            } else if let markStart = substring.range(of: "<mark>"),
                      let markEnd = substring.range(of: "</mark>", range: markStart.upperBound..<substring.endIndex) {
                let contentRange = markStart.upperBound..<markEnd.lowerBound
                
                result.characters.removeSubrange(markEnd.lowerBound..<markEnd.upperBound)
                result.characters.removeSubrange(markStart.lowerBound..<markStart.upperBound)
                
                let newContentRange = result.characters.index(markStart.lowerBound, offsetBy: 0)..<result.characters.index(markStart.lowerBound, offsetBy: contentRange.count)
                result[newContentRange].backgroundColor = .yellow.opacity(0.3)
                
                currentIndex = result.characters.index(after: newContentRange.upperBound)
            } else {
                break
            }
        }
        
        return result
    }
}
