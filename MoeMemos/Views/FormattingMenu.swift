//
//  FormattingMenu.swift
//  MoeMemos
//
//  Formatting menu for text editing with list and indent operations
//

import SwiftUI

enum ListType {
    case none
    case unordered
    case ordered
    case todo
}

struct FormattingMenu: View {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?
    var onDismiss: (() -> Void)? = nil
    
    @State private var isExpanded = false
    @State private var currentListType: ListType = .none
    @State private var canIncreaseIndent = true
    @State private var canDecreaseIndent = false
    
    private let maxIndentLevel = 4
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: mainButtonIcon)
                    .font(.system(size: 17))
                    .foregroundColor(isExpanded ? .accentColor : .primary)
            }
            .contentShape(Rectangle())
            
            if isExpanded {
                formattingPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
            }
        }
        .onAppear {
            updateCurrentState()
        }
        .onChange(of: text) { _, _ in
            updateCurrentState()
        }
        .onChange(of: selection) { _, _ in
            updateCurrentState()
        }
    }
    
    @ViewBuilder
    private var formattingPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                formatButton(
                    icon: "list.bullet",
                    title: "无序列表",
                    isActive: currentListType == .unordered,
                    action: { applyUnorderedList() }
                )
                
                formatButton(
                    icon: "list.number",
                    title: "有序列表",
                    isActive: currentListType == .ordered,
                    action: { applyOrderedList() }
                )
                
                formatButton(
                    icon: "increase.indent",
                    title: "增加缩进",
                    isDisabled: !canIncreaseIndent,
                    action: { increaseIndent() }
                )
                
                formatButton(
                    icon: "decrease.indent",
                    title: "减少缩进",
                    isDisabled: !canDecreaseIndent,
                    action: { decreaseIndent() }
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            )
            .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    private func formatButton(icon: String, title: String, isActive: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            if !isDisabled {
                action()
                dismissPanel()
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                .foregroundColor(isDisabled ? .gray : (isActive ? .accentColor : .primary))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
    
    private var mainButtonIcon: String {
        switch currentListType {
        case .none:
            return "list.bullet"
        case .unordered:
            return "list.bullet"
        case .ordered:
            return "list.number"
        case .todo:
            return "checklist"
        }
    }
    
    private func dismissPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded = false
        }
        onDismiss?()
    }
    
    private func updateCurrentState() {
        guard let currentSelection = selection else {
            currentListType = .none
            canDecreaseIndent = false
            canIncreaseIndent = true
            return
        }
        
        let currentText = text
        let contentBefore = currentText[currentText.startIndex..<currentSelection.lowerBound]
        let lastLineBreak = contentBefore.lastIndex(of: "\n")
        let nextLineBreak = currentText[currentSelection.lowerBound...].firstIndex(of: "\n") ?? currentText.endIndex
        
        let currentLine: Substring
        if let lastLineBreak = lastLineBreak {
            currentLine = currentText[currentText.index(after: lastLineBreak)..<nextLineBreak]
        } else {
            currentLine = currentText[currentText.startIndex..<nextLineBreak]
        }
        
        let lineString = String(currentLine)
        
        if lineString.hasPrefix("- ") || lineString.hasPrefix("- [ ] ") || lineString.hasPrefix("- [x] ") {
            currentListType = (lineString.hasPrefix("- [ ] ") || lineString.hasPrefix("- [x] ")) ? .todo : .unordered
        } else if lineString.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            currentListType = .ordered
        } else {
            currentListType = .none
        }
        
        let indentMatch = lineString.prefix(while: { $0 == " " || $0 == "\t" })
        let currentIndent = indentMatch.count / 2
        canDecreaseIndent = currentIndent > 0
        canIncreaseIndent = currentIndent < maxIndentLevel
    }
    
    private func applyUnorderedList() {
        applyListPrefix("- ")
    }
    
    private func applyOrderedList() {
        applyListPrefix("1. ")
    }
    
    private func applyListPrefix(_ prefix: String) {
        let currentText = text
        guard let currentSelection = selection else {
            text = prefix + text
            return
        }
        
        let contentBefore = currentText[currentText.startIndex..<currentSelection.lowerBound]
        let lastLineBreak = contentBefore.lastIndex(of: "\n")
        let nextLineBreak = currentText[currentSelection.lowerBound...].firstIndex(of: "\n") ?? currentText.endIndex
        
        let currentLine: Substring
        let lineStartIndex: String.Index
        if let lastLineBreak = lastLineBreak {
            lineStartIndex = currentText.index(after: lastLineBreak)
            currentLine = currentText[lineStartIndex..<nextLineBreak]
        } else {
            lineStartIndex = currentText.startIndex
            currentLine = currentText[currentText.startIndex..<nextLineBreak]
        }
        
        let lineString = String(currentLine)
        let existingPrefix = getExistingListPrefix(from: lineString)
        let indentPrefix = getIndentPrefix(from: lineString)
        
        if let existing = existingPrefix {
            if existing == prefix {
                text = currentText[currentText.startIndex..<lineStartIndex] + indentPrefix + lineString.replacingOccurrences(of: "^" + existing, with: "", options: .regularExpression) + currentText[nextLineBreak..<currentText.endIndex]
            } else {
                text = currentText[currentText.startIndex..<lineStartIndex] + indentPrefix + prefix + lineString.replacingOccurrences(of: "^" + existing.replacingOccurrences(of: "([.])", with: "\\$1", options: .regularExpression), with: "", options: .regularExpression) + currentText[nextLineBreak..<currentText.endIndex]
            }
        } else {
            text = currentText[currentText.startIndex..<lineStartIndex] + indentPrefix + prefix + lineString + currentText[nextLineBreak..<currentText.endIndex]
        }
        
        let newOffset = prefix.count
        selection = text.index(currentSelection.lowerBound, offsetBy: newOffset)..<text.index(currentSelection.upperBound, offsetBy: newOffset)
    }
    
    private func getExistingListPrefix(from line: String) -> String? {
        let trimmed = line.replacingOccurrences(of: "^[ \\t]+", with: "", options: .regularExpression)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") {
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") {
                return "- [ ] "
            }
            return "- "
        }
        if let match = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            return String(trimmed[match])
        }
        return nil
    }
    
    private func getIndentPrefix(from line: String) -> String {
        let indentMatch = line.prefix(while: { $0 == " " || $0 == "\t" })
        return String(indentMatch)
    }
    
    private func increaseIndent() {
        let currentText = text
        guard let currentSelection = selection else { return }
        
        let contentBefore = currentText[currentText.startIndex..<currentSelection.lowerBound]
        let lastLineBreak = contentBefore.lastIndex(of: "\n")
        let nextLineBreak = currentText[currentSelection.lowerBound...].firstIndex(of: "\n") ?? currentText.endIndex
        
        let lineStartIndex: String.Index
        if let lastLineBreak = lastLineBreak {
            lineStartIndex = currentText.index(after: lastLineBreak)
        } else {
            lineStartIndex = currentText.startIndex
        }
        
        let indentToAdd = "  "
        text = currentText[currentText.startIndex..<lineStartIndex] + indentToAdd + currentText[lineStartIndex..<currentText.endIndex]
        
        selection = text.index(currentSelection.lowerBound, offsetBy: 2)..<text.index(currentSelection.upperBound, offsetBy: 2)
    }
    
    private func decreaseIndent() {
        let currentText = text
        guard let currentSelection = selection else { return }
        
        let contentBefore = currentText[currentText.startIndex..<currentSelection.lowerBound]
        let lastLineBreak = contentBefore.lastIndex(of: "\n")
        
        let lineStartIndex: String.Index
        if let lastLineBreak = lastLineBreak {
            lineStartIndex = currentText.index(after: lastLineBreak)
        } else {
            lineStartIndex = currentText.startIndex
        }
        
        let lineContent = currentText[lineStartIndex..<currentText.endIndex]
        let indentMatch = lineContent.prefix(while: { $0 == " " || $0 == "\t" })
        
        guard indentMatch.count >= 2 else { return }
        
        let removeCount = min(2, indentMatch.count)
        let removeEndIndex = currentText.index(lineStartIndex, offsetBy: removeCount)
        
        text = currentText[currentText.startIndex..<lineStartIndex] + currentText[removeEndIndex..<currentText.endIndex]
        
        let newLower = text.index(currentSelection.lowerBound, offsetBy: -removeCount, limitedBy: text.startIndex) ?? text.startIndex
        let newUpper = text.index(currentSelection.upperBound, offsetBy: -removeCount, limitedBy: text.startIndex) ?? text.startIndex
        selection = newLower..<newUpper
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
                
                FormattingMenu(text: $text, selection: $selection)
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
