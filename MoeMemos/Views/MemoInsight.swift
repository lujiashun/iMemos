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
    @State private var showingDateRangeSheet = false
    @State private var showingResultSheet = false
    
    // For MultiDatePicker range logic
    @State private var dateSelection: Set<DateComponents> = []
    @State private var rangeAnchor: Date? = nil
    @State private var isProgrammaticUpdate = false

    var body: some View {
        mainList
            .sheet(isPresented: $showingDateRangeSheet) {
                dateRangeSheet
                    .environment(\.locale, locale)
            }
            .sheet(isPresented: $showingResultSheet) {
                resultSheet
            }
            .onAppear {
                loadPromptForCurrentLocale()
                applyPreset(rangePreset)
                Task { try? await memosViewModel.loadTags() }
            }
            .onChange(of: rangePreset) { _, newValue in
                applyPreset(newValue)
                if newValue == .custom {
                    showingDateRangeSheet = true
                }
            }
            .onChange(of: showingDateRangeSheet) { _, isShowing in
                if isShowing {
                    synchronizeSelectionFromRange()
                }
            }
            .onChange(of: dateSelection) { oldValue, newValue in
                handleDateSelectionChange(oldValue, newValue)
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

    private var mainList: some View {
        List {
            Section {
                if promptExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: $prompt)
                            .font(.footnote)
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
                }

                Picker("memo.deep-insight.range.preset", selection: $rangePreset) {
                    Text("memo.deep-insight.range.preset.today").tag(DateRangePreset.today)
                    Text("memo.deep-insight.range.preset.last7days").tag(DateRangePreset.last7Days)
                    Text("memo.deep-insight.range.preset.last30days").tag(DateRangePreset.last30Days)
                    Text("memo.deep-insight.range.preset.custom").tag(DateRangePreset.custom)
                }
                .pickerStyle(.segmented)

                Button {
                    showingDateRangeSheet = true
                } label: {
                    HStack {
                        Spacer()
                        if Calendar.current.isDate(startDay, inSameDayAs: endDay) {
                            Text(startDay, style: .date)
                        } else {
                            Text("\(startDay, style: .date) - \(endDay, style: .date)")
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(.primary)

                Picker("memo.deep-insight.tag", selection: $selectedTag) {
                    Text("memo.deep-insight.tag.all").tag(String?.none)
                    ForEach(memosViewModel.tags) { tag in
                        Text(tag.name).tag(String?.some(tag.name))
                    }
                }
                .pickerStyle(.menu)
            } header: {
                HStack {
                    Text("memo.deep-insight.range")
                    Spacer()
                    Button {
                        withAnimation {
                            promptExpanded.toggle()
                        }
                    } label: {
                        Text("memo.deep-insight.prompt")
                            .font(.caption)
                    }
                }
            }

            Section {
                Button {
                    Task {
                        await viewModel.generate(startDay: startDay, endDay: endDay, tag: selectedTag, prompt: prompt)
                        if viewModel.errorMessage == nil {
                            showingResultSheet = true
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.loading {
                            ProgressView()
                        } else {
                            Text("memo.deep-insight.generate")
                                .bold()
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.loading)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("memo.deep-insight")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.loading {
                    ProgressView()
                }
            }
        }
    }

    private var resultSheet: some View {
        NavigationStack {
            ScrollView {
                if viewModel.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("memo.deep-insight.empty")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    MarkdownView(viewModel.content)
                        .padding()
                }
            }
            .navigationTitle("memo.deep-insight.result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingResultSheet = false
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var dateRangeSheet: some View {
        NavigationStack {
            VStack {
                if let anchor = rangeAnchor {
                    Text(localizedAnchorPrompt(anchor: anchor))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                } else {
                    Text(localizedSelectPrompt())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                }
                
                MultiDatePicker("Range", selection: $dateSelection)
                    .datePickerStyle(.graphical)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("memo.deep-insight.range")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("memo.action.ok") { showingDateRangeSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // Helpers for manual localization logic, similar to prompt text.
    private func localizedSelectPrompt() -> String {
        let lang = Defaults.promptLanguageID(for: locale)
        if lang == "zh-Hans" { return "选择开始日期或日期范围" }
        if lang == "zh-Hant" { return "選擇開始日期或日期範圍" }
        if lang == "ja" { return "開始日または期間を選択してください" }
        return "Select start date or range"
    }

    private func localizedAnchorPrompt(anchor: Date) -> String {
        let lang = Defaults.promptLanguageID(for: locale)
        let dateStr = anchor.formatted(date: .abbreviated, time: .omitted)
        
        if lang == "zh-Hans" { return "已选择 \(dateStr)，请选择结束日期" }
        if lang == "zh-Hant" { return "已選擇 \(dateStr)，請選擇結束日期" }
        if lang == "ja" { return "\(dateStr) からの終了日を選択してください" }
        
        return "Select ending date starting from \(dateStr)"
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

        normalizeDates()
    }

    private func normalizeDates() {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDay)
        let normalizedEnd = calendar.startOfDay(for: endDay)

        if normalizedStart != startDay { startDay = normalizedStart }
        if normalizedEnd != endDay { endDay = normalizedEnd }

        if endDay < startDay {
            endDay = startDay
        }
    }

    
    private func synchronizeSelectionFromRange() {
        var dates: Set<DateComponents> = []
        let calendar = Calendar.current
        
        let start = calendar.startOfDay(for: startDay)
        let end = calendar.startOfDay(for: endDay)
        
        // Safety check: Don't enumerate if range is absurdly large (e.g. 10 years).
        // Cap at 365 days for UI performance if needed, but here simple loop is fine for reasonable usage.
        var date = start
        while date <= end {
            let components = calendar.dateComponents([.calendar, .era, .year, .month, .day], from: date)
            dates.insert(components)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
            
            // Limit loop
            if dates.count > 1000 { break }
        }
        
        if dateSelection != dates {
            isProgrammaticUpdate = true
            dateSelection = dates
        }
        rangeAnchor = nil
    }

    private func handleDateSelectionChange(_ oldValue: Set<DateComponents>, _ newValue: Set<DateComponents>) {
        if isProgrammaticUpdate {
            isProgrammaticUpdate = false
            return
        }
        // Did we just synchronize? If so, newValue should match start/end derived set.
        // We can check if the change implies a user tap.
        // Usually, user tap adds or removes ONE day.
        
        // 1. Calculate diff
        let inserted = newValue.subtracting(oldValue)
        let removed = oldValue.subtracting(newValue)
        
        let calendar = Calendar.current
        
        // Identify the "Intent Date"
        // If user tapped a selected date -> it's in `removed`.
        // If user tapped an unselected date -> it's in `inserted`.
        
        var tappedComponents: DateComponents?
        if let first = inserted.first {
            tappedComponents = first
        } else if let first = removed.first {
            tappedComponents = first
        }
        
        guard let tapped = tappedComponents, let tappedDate = calendar.date(from: tapped) else {
            // No single identifiable tap, maybe bulk update or sync?
            // If dateSelection is empty, we probably shouldn't set date to weird value,
            // but empty selection in MultiDatePicker allows "0 items".
            if newValue.isEmpty && !oldValue.isEmpty {
                // User deselected the last item. Reset to today? Or keep last valid?
                // Let's keep last valid logic or do nothing.
            }
            return
        }
        
        // 2. Logic
        if let anchor = rangeAnchor {
            // We have an anchor. User is selecting the second date (End of range).
            // Range is anchor...tappedDate
            let start = min(anchor, tappedDate)
            let end = max(anchor, tappedDate)
            
            startDay = start
            endDay = end
            
            normalizeDates()
            rangePreset = .custom
            
            // Clear anchor to reset state
            rangeAnchor = nil
            
            // We need to fill the selection visually
            synchronizeSelectionFromRange()
            
        } else {
            // No anchor. This is the "First click" of a new range selection.
            // Reset everything to just this date.
            startDay = tappedDate
            endDay = tappedDate
            
            normalizeDates()
            rangePreset = .custom
            
            rangeAnchor = tappedDate
            
            // Update visual selection to just this one date
            let newSet = Set([tapped])
            if dateSelection != newSet {
                isProgrammaticUpdate = true
                dateSelection = newSet
            }
        }
    }
}
