//
//  MemoInsight.swift
//  MoeMemos
//

import SwiftUI
import Account
import Models
import Factory
import MarkdownUI

@MainActor
@Observable
final class MemoInsightViewModel {
    @ObservationIgnored
    @Injected(\.accountManager) private var accountManager

    private(set) var content: String = ""
    private(set) var loading = false
    private(set) var errorMessage: String?

    private var service: RemoteService { get throws { try accountManager.mustCurrentService } }

    func generate(startDay: Date, endDay: Date, tag: String?, prompt: String) async {
        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            let timeFieldsToTry: [String] = [
                "create_time",
                "createTime",
                "update_time",
                "updateTime",
            ]

            for timeField in timeFieldsToTry {
                let filter = Self.buildFilter(startDay: startDay, endDay: endDay, tag: tag, timeField: timeField)
                do {
                    content = try await service.getMemoInsight(filter: filter, prompt: prompt)
                    return
                } catch {
                    if Self.shouldRetryWithDifferentTimeField(error: error, attemptedTimeField: timeField) {
                        continue
                    }
                    throw error
                }
            }

            // Last resort: drop the time range clause and only apply tag filtering.
            let filter = Self.buildFilter(startDay: startDay, endDay: endDay, tag: tag, timeField: nil)
            content = try await service.getMemoInsight(filter: filter, prompt: prompt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    static func buildFilter(startDay: Date, endDay: Date, tag: String?, timeField: String? = "create_time") -> String? {
        var clauses: [String] = []

        let calendar = Calendar.current

        let rawStart = calendar.startOfDay(for: startDay)
        let rawEnd = calendar.startOfDay(for: endDay)
        let start = min(rawStart, rawEnd)
        let inclusiveEnd = max(rawStart, rawEnd)

        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) else {
            return nil
        }

        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        // Some servers are picky about fractional seconds in CEL timestamp parsing.
        iso.formatOptions = [.withInternetDateTime]

        let startStr = iso.string(from: start)
        let endStr = iso.string(from: endExclusive)

        if let timeField {
            clauses.append("(\(timeField) >= timestamp(\"\(startStr)\") && \(timeField) < timestamp(\"\(endStr)\"))")
        }

        if let tag, !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let rawTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = rawTag.hasPrefix("#") ? rawTag : "#\(rawTag)"
            let escaped = escapeCELStringLiteral(normalized)
            clauses.append("content.contains(\"\(escaped)\")")
        }

        return clauses.isEmpty ? nil : clauses.joined(separator: " && ")
    }

    private static func escapeCELStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shouldRetryWithDifferentTimeField(error: Error, attemptedTimeField: String) -> Bool {
        guard case let MoeMemosError.invalidStatusCode(_, message) = error,
              let message
        else {
            return false
        }

        // Typical backend error:
        // "invalid filter: failed to compile filter: ... undeclared reference to 'display_time'"
        let lowercased = message.lowercased()
        guard lowercased.contains("invalid filter"), lowercased.contains("undeclared reference") else {
            return false
        }

        // Be conservative: only retry on filters where the undeclared identifier is our time field.
        if lowercased.contains("'\(attemptedTimeField.lowercased())'") {
            return true
        }

        // If server explicitly complains about display_time, that's also a time-field mismatch.
        if lowercased.contains("'display_time'") {
            return true
        }

        return false
    }
}

struct MemoInsight: View {
    private enum DateRangePreset: String, CaseIterable, Identifiable {
        case today
        case last7Days
        case last30Days
        case custom

        var id: String { rawValue }
    }

    private enum Defaults {
        static let legacyPromptKey = "memo.deep-insight.prompt"

        static func promptStorageKey(for locale: Locale) -> String {
            "memo.deep-insight.prompt.\(promptLanguageID(for: locale))"
        }

        static func promptLanguageID(for locale: Locale) -> String {
            let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()

            if identifier.hasPrefix("zh") {
                if identifier.contains("hant") { return "zh-Hant" }
                // Default Chinese to Simplified.
                return "zh-Hans"
            }
            if identifier.hasPrefix("ja") { return "ja" }
            if identifier.hasPrefix("de") { return "de" }
            if identifier.hasPrefix("fr") { return "fr" }
            if identifier.hasPrefix("it") { return "it" }
            if identifier.hasPrefix("ru") { return "ru" }
            return "en"
        }

        static func defaultPrompt(for locale: Locale) -> String {
            switch promptLanguageID(for: locale) {
            case "zh-Hans":
                return "请总结并提炼今天的 memo 洞察：用简洁要点列出关键事件/主题、重复模式、待办事项（TODO）、未解问题，并给出可执行的下一步建议。"
            case "zh-Hant":
                return "請總結並提煉今天的 memo 洞察：用簡潔要點列出關鍵事件/主題、重複模式、待辦事項（TODO）、未解問題，並給出可執行的下一步建議。"
            case "ja":
                return "今日のメモを要約し、重要な気づきを抽出してください。簡潔な箇条書きで、主要トピック、繰り返しパターン、TODO、未解決の疑問、次のアクションを示してください。"
            case "de":
                return "Fasse die heutigen Memos zusammen und extrahiere die wichtigsten Erkenntnisse. Nutze kurze Bullet Points und hebe Muster, TODOs, offene Fragen und nächste Schritte hervor."
            case "fr":
                return "Résume les mémos d'aujourd'hui et extrais les principaux enseignements. Donne des puces concises et mets en avant les tendances, TODO, questions ouvertes et prochaines étapes."
            case "it":
                return "Riassumi i memo di oggi ed estrai le intuizioni principali. Usa punti elenco concisi ed evidenzia pattern, TODO, domande aperte e prossimi passi."
            case "ru":
                return "Суммируй сегодняшние заметки и выдели ключевые инсайты. Кратко в пунктах: основные темы, повторяющиеся паттерны, TODO, открытые вопросы и следующие шаги."
            default:
                return "Summarize and extract key insights from today's memos. Use concise bullets and highlight patterns, TODOs, open questions, and actionable next steps."
            }
        }
    }

    @Environment(MemosViewModel.self) private var memosViewModel: MemosViewModel
    @Environment(\.locale) private var locale

    @State private var viewModel = MemoInsightViewModel()

    @State private var rangePreset: DateRangePreset = .today
    @State private var startDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var endDay: Date = Calendar.current.startOfDay(for: .now)

    @State private var selectedTag: String? = nil

    @State private var savedPrompt: String = ""
    @State private var prompt: String = ""
    @State private var promptExpanded = false

    @State private var showingError = false

    var body: some View {
        let content = viewModel.content

        List {
            Section {
                Picker("memo.deep-insight.range.preset", selection: $rangePreset) {
                    Text("memo.deep-insight.range.preset.today").tag(DateRangePreset.today)
                    Text("memo.deep-insight.range.preset.last7days").tag(DateRangePreset.last7Days)
                    Text("memo.deep-insight.range.preset.last30days").tag(DateRangePreset.last30Days)
                    Text("memo.deep-insight.range.preset.custom").tag(DateRangePreset.custom)
                }
                .pickerStyle(.segmented)

                HStack {
                    DatePicker(
                        "memo.deep-insight.range.from",
                        selection: $startDay,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)

                    Spacer(minLength: 12)

                    DatePicker(
                        "memo.deep-insight.range.to",
                        selection: $endDay,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                }

                Picker("memo.deep-insight.tag", selection: $selectedTag) {
                    Text("memo.deep-insight.tag.all").tag(String?.none)
                    ForEach(memosViewModel.tags) { tag in
                        Text(tag.name).tag(String?.some(tag.name))
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("memo.deep-insight.range")
            }

            Section {
                DisclosureGroup(
                    isExpanded: $promptExpanded,
                    content: {
                        VStack(alignment: .leading, spacing: 10) {
                            TextEditor(text: $prompt)
                                .font(.body)
                                .frame(minHeight: 140)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.secondary.opacity(0.25))
                                )

                            HStack {
                                Spacer()
                                Button {
                                    savePrompt(prompt)
                                } label: {
                                    Text("memo.deep-insight.prompt.save")
                                }
                                .disabled(prompt == savedPrompt)
                            }
                        }
                        .padding(.top, 6)
                    },
                    label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("memo.deep-insight.prompt")
                            if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(prompt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                )
            }

            Section {
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("memo.deep-insight.empty")
                        .foregroundStyle(.secondary)
                } else {
                    MarkdownView(content)
                }
            } header: {
                Text("memo.deep-insight.result")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("memo.deep-insight")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.generate(startDay: startDay, endDay: endDay, tag: selectedTag, prompt: prompt) }
                } label: {
                    Text("memo.deep-insight.generate")
                }
                .disabled(viewModel.loading)
            }

            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.loading {
                    ProgressView()
                }
            }
        }
        .onAppear {
            loadPromptForCurrentLocale()
            applyPreset(rangePreset)
            Task { try? await memosViewModel.loadTags() }
        }
        .onChange(of: rangePreset) { _, newValue in
            applyPreset(newValue)
        }
        .onChange(of: startDay) { _, _ in
            normalizeDateRange(userInitiated: true)
        }
        .onChange(of: endDay) { _, _ in
            normalizeDateRange(userInitiated: true)
        }
        .onChange(of: locale.identifier) { _, _ in
            loadPromptForCurrentLocale()
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showingError = (newValue != nil)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func loadPromptForCurrentLocale() {
        let defaults = UserDefaults.standard
        let key = Defaults.promptStorageKey(for: locale)

        // One-time migration from the legacy global prompt key.
        if defaults.object(forKey: key) == nil,
           let legacy = defaults.string(forKey: Defaults.legacyPromptKey),
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(legacy, forKey: key)
            defaults.removeObject(forKey: Defaults.legacyPromptKey)
        }

        let newSaved = defaults.string(forKey: key) ?? Defaults.defaultPrompt(for: locale)
        let oldSaved = savedPrompt
        savedPrompt = newSaved

        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt == oldSaved {
            prompt = newSaved
        }
    }

    private func savePrompt(_ newValue: String) {
        let defaults = UserDefaults.standard
        let key = Defaults.promptStorageKey(for: locale)
        defaults.set(newValue, forKey: key)
        savedPrompt = newValue
    }

    private func applyPreset(_ preset: DateRangePreset) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        switch preset {
        case .today:
            startDay = today
            endDay = today
        case .last7Days:
            startDay = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            endDay = today
        case .last30Days:
            startDay = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            endDay = today
        case .custom:
            break
        }

        normalizeDateRange(userInitiated: false)
    }

    private func normalizeDateRange(userInitiated: Bool) {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDay)
        let normalizedEnd = calendar.startOfDay(for: endDay)

        if normalizedStart != startDay { startDay = normalizedStart }
        if normalizedEnd != endDay { endDay = normalizedEnd }

        if endDay < startDay {
            endDay = startDay
        }

        if userInitiated {
            rangePreset = .custom
        }
    }
}
