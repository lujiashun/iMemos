//
//  ToolboxMenu.swift
//  MoeMemos
//
//  Toolbox menu for text formatting with underline and highlight
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ToolboxMenu: View {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?
    @Binding var attributedText: NSAttributedString?
    @Binding var inputMode: TextFormatMode?
    
    @State private var isExpanded = false
    
    private var currentText: String {
        attributedText?.string ?? text
    }
    
    private var hasSelection: Bool {
        guard let currentSelection = selection,
              currentSelection.lowerBound >= text.startIndex,
              currentSelection.upperBound <= text.endIndex,
              currentSelection.lowerBound != currentSelection.upperBound else {
            return false
        }
        return true
    }
    
    private var cursorPosition: Int {
        guard let currentSelection = selection,
              currentSelection.lowerBound >= text.startIndex else {
            return 0
        }
        return text.distance(from: text.startIndex, to: currentSelection.lowerBound)
    }
    
    private var isUnderlineActive: Bool {
        guard let attrText = attributedText else { return inputMode == .underline }
        let position = cursorPosition
        guard position < attrText.length else { return inputMode == .underline }
        
        let range = NSRange(location: position, length: 1)
        var hasStyle = false
        attrText.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, stop in
            if let style = value as? Int, style == NSUnderlineStyle.single.rawValue {
                hasStyle = true
                stop.pointee = true
            }
        }
        return hasStyle || inputMode == .underline
    }
    
    private var isHighlightActive: Bool {
        guard let attrText = attributedText else { return inputMode == .highlight }
        let position = cursorPosition
        guard position < attrText.length else { return inputMode == .highlight }
        
        let range = NSRange(location: position, length: 1)
        var hasStyle = false
        #if canImport(UIKit)
        attrText.enumerateAttribute(.backgroundColor, in: range, options: []) { value, _, stop in
            if let color = value as? UIColor {
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                if red > 0.9 && green > 0.7 && blue < 0.3 {
                    hasStyle = true
                    stop.pointee = true
                }
            }
        }
        #endif
        return hasStyle || inputMode == .highlight
    }
    
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 17))
        }
        .fixedSize()
        .contentShape(Rectangle())
        .overlay(alignment: .bottomLeading) {
            if isExpanded {
                ZStack {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismissPanel()
                        }
                    
                    toolboxPanel
                        .offset(y: -44)
                        .transition(.opacity)
                }
            }
        }
    }
    
    @ViewBuilder
    private var toolboxPanel: some View {
        HStack(spacing: 16) {
            Button {
                toggleUnderline()
            } label: {
                Image(systemName: "underline")
                    .font(.system(size: 17))
                    .foregroundColor(isUnderlineActive ? .accentColor : .primary)
                    .padding(8)
                    .background(isUnderlineActive ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(6)
            }
            
            Button {
                toggleHighlight()
            } label: {
                Image(systemName: "highlighter")
                    .font(.system(size: 17))
                    .foregroundColor(isHighlightActive ? .accentColor : .primary)
                    .padding(8)
                    .background(isHighlightActive ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        )
    }
    
    private func dismissPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded = false
        }
        inputMode = nil
    }
    
    private func toggleUnderline() {
        print("📝 [Toggle] toggleUnderline called, hasSelection: \(hasSelection), selection: \(String(describing: selection))")
        if hasSelection {
            toggleStyleForSelection(isUnderline: true)
        } else {
            if inputMode == .underline {
                inputMode = nil
            } else {
                inputMode = .underline
            }
        }
    }
    
    private func toggleHighlight() {
        print("📝 [Toggle] toggleHighlight called, hasSelection: \(hasSelection), selection: \(String(describing: selection))")
        if hasSelection {
            toggleStyleForSelection(isUnderline: false)
        } else {
            if inputMode == .highlight {
                inputMode = nil
            } else {
                inputMode = .highlight
            }
        }
    }
    
    private func toggleStyleForSelection(isUnderline: Bool) {
        guard let currentSelection = selection,
              currentSelection.lowerBound >= text.startIndex,
              currentSelection.upperBound <= text.endIndex else { return }
        
        let mutableAttributedString: NSMutableAttributedString
        if let attributedText = attributedText {
            mutableAttributedString = NSMutableAttributedString(attributedString: attributedText)
        } else {
            mutableAttributedString = NSMutableAttributedString(string: text)
            #if canImport(UIKit)
            let defaultFont = UIFont.preferredFont(forTextStyle: .body)
            let fullRange = NSRange(location: 0, length: mutableAttributedString.length)
            mutableAttributedString.addAttribute(.font, value: defaultFont, range: fullRange)
            #endif
        }
        
        let nsRange = NSRange(currentSelection, in: text)
        guard nsRange.location + nsRange.length <= mutableAttributedString.length else { return }
        
        let hasStyle = checkStyleInRange(mutableAttributedString, range: nsRange, isUnderline: isUnderline)
        print("📝 [Toggle] hasStyle: \(hasStyle), range: \(nsRange), isUnderline: \(isUnderline)")
        
        if hasStyle {
            removeStyle(mutableAttributedString, range: nsRange, isUnderline: isUnderline)
            print("📝 [Toggle] 移除样式后 attributedText: \(mutableAttributedString)")
        } else {
            applyStyle(mutableAttributedString, range: nsRange, isUnderline: isUnderline)
        }
        
        attributedText = mutableAttributedString
        text = mutableAttributedString.string
    }
    
    private func checkStyleInRange(_ attrString: NSAttributedString, range: NSRange, isUnderline: Bool) -> Bool {
        var hasStyle = false
        
        if isUnderline {
            attrString.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, stop in
                if let style = value as? Int, style == NSUnderlineStyle.single.rawValue {
                    hasStyle = true
                    stop.pointee = true
                }
            }
        } else {
            #if canImport(UIKit)
            attrString.enumerateAttribute(.backgroundColor, in: range, options: []) { value, _, stop in
                if let color = value as? UIColor {
                    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                    if red > 0.9 && green > 0.7 && blue < 0.3 {
                        hasStyle = true
                        stop.pointee = true
                    }
                }
            }
            #endif
        }
        
        return hasStyle
    }
    
    private func applyStyle(_ attrString: NSMutableAttributedString, range: NSRange, isUnderline: Bool) {
        if isUnderline {
            attrString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            #if canImport(UIKit)
            attrString.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: range)
            #endif
        }
    }
    
    private func removeStyle(_ attrString: NSMutableAttributedString, range: NSRange, isUnderline: Bool) {
        if isUnderline {
            attrString.removeAttribute(.underlineStyle, range: range)
        } else {
            attrString.removeAttribute(.backgroundColor, range: range)
        }
    }
}

enum TextFormatMode {
    case underline
    case highlight
}
