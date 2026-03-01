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
    
    private var hasSelection: Bool {
        guard let currentSelection = selection,
              let currentText = text as String?,
              currentSelection.lowerBound >= currentText.startIndex,
              currentSelection.upperBound <= currentText.endIndex,
              currentSelection.lowerBound != currentSelection.upperBound else {
            return false
        }
        return true
    }
    
    var body: some View {
        Menu {
            Button(action: {
                applyUnderline()
            }) {
                Label("加下划线", systemImage: "underline")
            }
            .disabled(!hasSelection)
            
            Button(action: {
                applyHighlight()
            }) {
                Label("划重点", systemImage: "highlighter")
            }
            .disabled(!hasSelection)
        } label: {
            Image(systemName: "ellipsis.vertical")
                .font(.system(size: 17))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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

#Preview {
    struct PreviewWrapper: View {
        @State var text = "Hello world"
        @State var selection: Range<String.Index>? = nil
        
        var body: some View {
            VStack {
                TextEditor(text: $text)
                    .frame(height: 200)
                    .border(Color.gray)
                
                HStack {
                    ToolboxMenu(text: $text, selection: $selection)
                }
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
