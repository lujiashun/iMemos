//
//  Constants.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/11/5.
//

import Foundation

let listItemSymbolList = ["- [ ] ", "- [x] ", "- [X] ", "* ", "- "]

let audioTranscriptRefinePromptPrefix = """
你是“语音转写文本整理器”，只能做最小必要编辑，禁止创作。

【硬性规则（必须全部满足）】
1. 仅输出整理后的文本，不得输出任何说明。
2. 只允许：纠错别字、去口误重复、补标点、轻微语序调整。
3. 严禁新增任何原文未明确出现的信息、事实、人物、地点、事件、观点、例子。
4. 严禁扩写、联想续写、举例、解释、发挥。
5. 若原文过短、语义不完整或无法确定（如少于8个汉字），必须原样返回。
6. 输出长度不得超过原文的1.2倍；若原文少于20字，最多仅可比原文多8个字。
7. 保留原始语气，不改变核心语义。

【输入文本开始】
"""

func makeAudioTranscriptRefinePrompt(_ transcript: String) -> String {
	audioTranscriptRefinePromptPrefix + transcript + "\n【输入文本结束】"
}

private let minAudioTranscriptCharsForRefine = 8
private let audioRefineMaxExpansionRatio = 1.2
private let audioRefineMaxExpansionForShortText = 8

private func normalizedAudioTranscriptCharCount(_ text: String) -> Int {
	text
		.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
		.count
}

func shouldSkipAudioTranscriptRefine(_ transcript: String) -> Bool {
	normalizedAudioTranscriptCharCount(transcript) < minAudioTranscriptCharsForRefine
}

func shouldUseRefinedAudioTranscript(original: String, refined: String) -> Bool {
	let originalTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
	let refinedTrimmed = refined.trimmingCharacters(in: .whitespacesAndNewlines)
	guard !originalTrimmed.isEmpty, !refinedTrimmed.isEmpty else { return false }

	let originalCount = normalizedAudioTranscriptCharCount(originalTrimmed)
	let refinedCount = normalizedAudioTranscriptCharCount(refinedTrimmed)
	guard originalCount > 0, refinedCount > 0 else { return false }

	let maxAllowed: Int
	if originalCount < 20 {
		maxAllowed = originalCount + audioRefineMaxExpansionForShortText
	} else {
		maxAllowed = Int(ceil(Double(originalCount) * audioRefineMaxExpansionRatio))
	}

	return refinedCount <= maxAllowed
}
