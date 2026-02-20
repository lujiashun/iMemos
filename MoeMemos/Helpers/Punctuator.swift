//
//  Punctuator.swift
//  MoeMemos
//
//  Lightweight local punctuator for speech transcripts.
//

import Foundation

struct Punctuator {
    /// Apply a simple, local punctuation restoration to a raw transcript.
    /// This is intentionally lightweight and heuristic-based.
    static func punctuateLocally(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }

        // If text already contains common punctuation, return as-is.
        let punctSet = CharacterSet(charactersIn: "，。！？；,.!?；；")
        if s.rangeOfCharacter(from: punctSet) != nil {
            return s
        }

        // Normalize newlines to sentence breaks
        s = s.replacingOccurrences(of: "\n", with: "。")

        // Collapse multiple whitespace into single spaces
        let comps = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if comps.isEmpty { return s }

        // If the text is short, just append a full stop.
        if s.count <= 12 {
            if s.hasSuffix("。") || s.hasSuffix("?") || s.hasSuffix("!") {
                return s
            }
            return s + "。"
        }

        // Otherwise, join heuristic: insert comma between short tokens, end with a period.
        var pieces: [String] = []
        for (i, token) in comps.enumerated() {
            if i == comps.count - 1 {
                pieces.append(token)
            } else {
                pieces.append(token + "，")
            }
        }
        var result = pieces.joined(separator: " ")
        // remove spaces before Chinese punctuation
        result = result.replacingOccurrences(of: " ，", with: "，")
        if !result.hasSuffix("。") && !result.hasSuffix("?") && !result.hasSuffix("!") {
            result += "。"
        }
        return result
    }
}
