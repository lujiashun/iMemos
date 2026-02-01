//
//  Stats.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/4.
//

import SwiftUI
import Account
import Env
import Models

struct Stats: View {
    @Environment(MemosViewModel.self) private var memosViewModel: MemosViewModel
    @Environment(AccountViewModel.self) var userState: AccountViewModel
    @Environment(\.navigationSelect) private var navigationSelect
    @Environment(\.sidebarToggle) private var sidebarToggle
    @Environment(AppPath.self) private var appPath

    var onSidebarItemSelect: (() -> Void)? = nil

    private var isPadOrVision: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .vision
    }
    
    var body: some View {
        let heatmapColumns = 12
        let heatmapHeight: CGFloat = 180
        let heatmapMatrix = DailyUsageStat.alignedForHeatmap(matrix: memosViewModel.matrix, firstWeekday: 2)

        VStack {
            HStack {
                VStack {
                    Text("\(memosViewModel.memoList.count)")
                        .font(.title2)
                    Text("stats.memo")
                        .textCase(.uppercase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack {
                    Text("\(memosViewModel.tags.count)")
                        .font(.title2)
                    Text("stats.tag")
                        .textCase(.uppercase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack {
                    Text("\(days())")
                        .font(.title2)
                    Text("stats.day")
                        .textCase(.uppercase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            
            VStack(spacing: 6) {
                Heatmap(matrix: heatmapMatrix, alignment: .trailing, columns: heatmapColumns) { day in
                    appPath.selectedMemoDay = day.date
                    navigationSelect.perform(.memos)

                    // On iPhone, the sidebar is an overlay; explicitly dismiss it.
                    onSidebarItemSelect?()

                    // On iPad/vision, collapse the split view sidebar.
                    if isPadOrVision {
                        sidebarToggle.perform()
                    }
                }
                .frame(height: heatmapHeight)

                HeatmapMonthLabels(matrix: heatmapMatrix, gridHeight: heatmapHeight, columns: heatmapColumns)
                    .frame(height: 16)
            }
            .padding(.bottom, 10)
            .padding(.horizontal, 20)
        }
    }
    
    func days() -> Int {
        guard let user = userState.currentUser else { return 0 }
        return Calendar.current.dateComponents([.day], from: user.creationDate, to: .now).day!
    }
}

private struct HeatmapMonthLabels: View {
    let matrix: [DailyUsageStat]
    let gridHeight: CGFloat
    let columns: Int

    private let gridSpacing: CGFloat = 3
    private let daysInWeek: Int = 7
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    var body: some View {
        GeometryReader { geometry in
            let visibleCount = min(matrix.count, daysInWeek * max(columns, 1))
            let visibleDays = Array(matrix.suffix(visibleCount))
            let cellSize = heatmapCellSize(width: geometry.size.width)
            let step = cellSize + gridSpacing

            ZStack(alignment: .leading) {
                ForEach(monthMarkers(in: visibleDays, step: step), id: \.offset) { marker in
                    Text(marker.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .offset(x: marker.x)
                }
            }
        }
    }

    private func heatmapCellSize(width: CGFloat) -> CGFloat {
        let cols = max(columns, 1)
        let cellByHeight = (gridHeight - gridSpacing * CGFloat(daysInWeek - 1)) / CGFloat(daysInWeek)
        let cellByWidth = (width - gridSpacing * CGFloat(cols - 1)) / CGFloat(cols)
        return max(0, min(cellByHeight, cellByWidth))
    }

    private struct MonthMarker {
        let offset: Int
        let label: String
        let x: CGFloat
    }

    private func monthMarkers(in visibleDays: [DailyUsageStat], step: CGFloat) -> [MonthMarker] {
        guard !visibleDays.isEmpty else { return [] }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM"

        // Only show a month label if the visible range includes that month’s 1st day.
        var monthFirstDayIndex: [String: Int] = [:]
        for (index, day) in visibleDays.enumerated() {
            let comps = calendar.dateComponents([.year, .month, .day], from: day.date)
            guard (comps.day ?? 0) == 1 else { continue }
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            monthFirstDayIndex[key] = index
        }

        guard !monthFirstDayIndex.isEmpty else { return [] }

        var markers: [MonthMarker] = []
        for (_, index) in monthFirstDayIndex.sorted(by: { $0.value < $1.value }) {
            let date = visibleDays[index].date
            let column = index / daysInWeek
            markers.append(MonthMarker(offset: index, label: formatter.string(from: date), x: CGFloat(column) * step))
        }

        return markers
    }
}
