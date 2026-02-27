//
//  Constants.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/11/5.
//

import Foundation

let listItemSymbolList = ["- [ ] ", "- [x] ", "- [X] ", "* ", "- "]

let audioTranscriptRefinePromptPrefix = """
请将以下语音转写文本进行专业级文本整理，严格遵守以下所有规则:

1. 仅输出整理后的最终文本，禁止添加任何解释性文字、标题、注释、说明、前缀或后缀,包括但不限于：“改写说明”、“优化后：”、“以下是结果：”等。
2. 修正所有错别字、口误、重复语句、语义冗余内容，但不得删减任何关键信息或语义单元。
3. 自动补全缺失的标点符号（句号、逗号、问号、引号、顿号等），确保符合现代汉语书面语规范。
4. 重组语序，使语句通顺、逻辑清晰、层次分明，符合自然语言表达习惯。
5. 根据语义自然分段，每段不超过5行，提升可读性，便于阅读与后续处理。
6. 保留原始说话人的语气、风格与情感倾向（如口语化、情绪化表达），仅做语法与结构优化，不进行主观改写或扩写。
7. 输出格式要求：纯文本，无Markdown，无HTML，无编号，无项目符号，无空行分隔段落（段落间仅用一个换行符分隔）。
待整理内容：
"""

func makeAudioTranscriptRefinePrompt(_ transcript: String) -> String {
	audioTranscriptRefinePromptPrefix + transcript
}
