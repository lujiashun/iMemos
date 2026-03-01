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
    
    private var isTruncated: Bool {
        let attributedText = parseRichText(text)
        let label = UILabel()
        label.attributedText = attributedText
        label.numberOfLines = maxLines
        
        let maxWidth: CGFloat = UIScreen.main.bounds.width - 32
        let fullHeight = label.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude)).height
        let lineHeight: CGFloat = 22
        let limitedHeight = lineHeight * CGFloat(maxLines)
        
        return fullHeight > limitedHeight
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if canImport(UIKit)
            RichTextLabel(
                attributedText: parseRichText(text),
                maxLines: isExpanded ? 0 : maxLines
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
struct RichTextLabel: UIViewRepresentable {
    let attributedText: NSAttributedString
    let maxLines: Int
    
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = maxLines
        label.lineBreakMode = .byWordWrapping
        return label
    }
    
    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.attributedText = attributedText
        uiView.numberOfLines = maxLines
    }
}
#endif
