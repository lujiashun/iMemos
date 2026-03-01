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
        
        let selectedText = String(text[currentSelection.lowerBound..<currentSelection.upperBound])
        let beforeSelection = String(text[text.startIndex..<currentSelection.lowerBound])
        let afterSelection = String(text[currentSelection.upperBound..<text.endIndex])
        
        let wrappedText = "<u>\(selectedText)</u>"
        let newText = beforeSelection + wrappedText + afterSelection
        text = newText
        
        let newCursorOffset = beforeSelection.count + wrappedText.count
        let safeOffset = min(newCursorOffset, newText.count)
        let newCursorPos = newText.index(newText.startIndex, offsetBy: safeOffset)
        selection = newCursorPos..<newCursorPos
    }
    
    private func applyHighlight() {
        guard let currentSelection = selection,
              currentSelection.lowerBound >= text.startIndex,
              currentSelection.upperBound <= text.endIndex,
              currentSelection.lowerBound != currentSelection.upperBound else { return }
        
        let selectedText = String(text[currentSelection.lowerBound..<currentSelection.upperBound])
        let beforeSelection = String(text[text.startIndex..<currentSelection.lowerBound])
        let afterSelection = String(text[currentSelection.upperBound..<text.endIndex])
        
        let wrappedText = "<mark>\(selectedText)</mark>"
        let newText = beforeSelection + wrappedText + afterSelection
        text = newText
        
        let newCursorOffset = beforeSelection.count + wrappedText.count
        let safeOffset = min(newCursorOffset, newText.count)
        let newCursorPos = newText.index(newText.startIndex, offsetBy: safeOffset)
        selection = newCursorPos..<newCursorPos
    }
}
