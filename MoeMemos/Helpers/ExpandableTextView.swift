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
        
        while true {
            let stringContent = String(result.characters)
            
            guard let uStart = stringContent.range(of: "<u>"),
                  let uEnd = stringContent.range(of: "</u>", range: uStart.upperBound..<stringContent.endIndex) else {
                break
            }
            
            let contentRange = uStart.upperBound..<uEnd.lowerBound
            let content = String(stringContent[contentRange])
            
            let attrStart = AttributedString.CharacterView.Index(uStart.lowerBound, within: result)!
            let attrEnd = AttributedString.CharacterView.Index(uEnd.upperBound, within: result)!
            result.characters.removeSubrange(attrStart..<attrEnd)
            
            let insertIndex = AttributedString.CharacterView.Index(uStart.lowerBound, within: result)!
            result.insert(AttributedString(content), at: insertIndex)
            
            let newStart = AttributedString.CharacterView.Index(uStart.lowerBound, within: result)!
            let newEnd = AttributedString.CharacterView.Index(uStart.lowerBound, offsetBy: content.count, within: result)!
            result[newStart..<newEnd].underlineStyle = .single
        }
        
        while true {
            let stringContent = String(result.characters)
            
            guard let markStart = stringContent.range(of: "<mark>"),
                  let markEnd = stringContent.range(of: "</mark>", range: markStart.upperBound..<stringContent.endIndex) else {
                break
            }
            
            let contentRange = markStart.upperBound..<markEnd.lowerBound
            let content = String(stringContent[contentRange])
            
            let attrStart = AttributedString.CharacterView.Index(markStart.lowerBound, within: result)!
            let attrEnd = AttributedString.CharacterView.Index(markEnd.upperBound, within: result)!
            result.characters.removeSubrange(attrStart..<attrEnd)
            
            let insertIndex = AttributedString.CharacterView.Index(markStart.lowerBound, within: result)!
            result.insert(AttributedString(content), at: insertIndex)
            
            let newStart = AttributedString.CharacterView.Index(markStart.lowerBound, within: result)!
            let newEnd = AttributedString.CharacterView.Index(markStart.lowerBound, offsetBy: content.count, within: result)!
            result[newStart..<newEnd].backgroundColor = .yellow.opacity(0.3)
        }
        
        return result
    }
}
