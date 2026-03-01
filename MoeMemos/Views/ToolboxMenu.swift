//
//  ToolboxMenu.swift
//  MoeMemos
//
//  Toolbox menu for text formatting with underline and highlight
//

import SwiftUI

struct ToolboxMenu: View {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?
    @Binding var attributedText: NSAttributedString?
    
    @State private var isExpanded = false
    
    private var hasSelection: Bool {
        guard let currentSelection = selection,
              currentSelection.lowerBound >= text.startIndex,
              currentSelection.upperBound <= text.endIndex,
              currentSelection.lowerBound != currentSelection.upperBound else {
            return false
        }
        return true
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
                if hasSelection {
                    applyUnderline()
                    dismissPanel()
                }
            } label: {
                Image(systemName: "underline")
                    .font(.system(size: 17))
                    .foregroundColor(hasSelection ? .primary : .gray)
            }
            .disabled(!hasSelection)
            
            Button {
                if hasSelection {
                    applyHighlight()
                    dismissPanel()
                }
            } label: {
                Image(systemName: "highlighter")
                    .font(.system(size: 17))
                    .foregroundColor(hasSelection ? .primary : .gray)
            }
            .disabled(!hasSelection)
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
    }
    
    private func applyUnderline() {
        guard let currentSelection = selection,
              currentSelection.lowerBound >= text.startIndex,
              currentSelection.upperBound <= text.endIndex,
              currentSelection.lowerBound != currentSelection.upperBound else { return }
        
        let nsRange = NSRange(currentSelection, in: text)
        
        let mutableAttributedString: NSMutableAttributedString
        if let attributedText = attributedText {
            mutableAttributedString = NSMutableAttributedString(attributedString: attributedText)
        } else {
            mutableAttributedString = NSMutableAttributedString(string: text)
        }
        
        mutableAttributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        
        attributedText = mutableAttributedString
        
        let newCursorOffset = text.distance(from: text.startIndex, to: currentSelection.upperBound)
        let safeOffset = min(newCursorOffset, text.count)
        let newCursorPos = text.index(text.startIndex, offsetBy: safeOffset)
        selection = newCursorPos..<newCursorPos
    }
    
    private func applyHighlight() {
        guard let currentSelection = selection,
              currentSelection.lowerBound >= text.startIndex,
              currentSelection.upperBound <= text.endIndex,
              currentSelection.lowerBound != currentSelection.upperBound else { return }
        
        let nsRange = NSRange(currentSelection, in: text)
        
        let mutableAttributedString: NSMutableAttributedString
        if let attributedText = attributedText {
            mutableAttributedString = NSMutableAttributedString(attributedString: attributedText)
        } else {
            mutableAttributedString = NSMutableAttributedString(string: text)
        }
        
        mutableAttributedString.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: nsRange)
        
        attributedText = mutableAttributedString
        
        let newCursorOffset = text.distance(from: text.startIndex, to: currentSelection.upperBound)
        let safeOffset = min(newCursorOffset, text.count)
        let newCursorPos = text.index(text.startIndex, offsetBy: safeOffset)
        selection = newCursorPos..<newCursorPos
    }
}
