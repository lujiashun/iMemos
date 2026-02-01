//
//  Heatmap.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/4.
//

import SwiftUI
import Foundation

fileprivate let gridSpacing: CGFloat = 3
fileprivate let heatmapDaysInWeek: Int = 7
fileprivate let defaultRows = [GridItem](repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: gridSpacing), count: heatmapDaysInWeek)

struct Heatmap: View {
    let rows = defaultRows
    let matrix: [DailyUsageStat]
    let alignment: HorizontalAlignment
    var onSelectDay: ((DailyUsageStat) -> Void)? = nil
    
    var body: some View {
        GeometryReader { geometry in
            LazyHGrid(rows: rows, alignment: .top, spacing: gridSpacing) {
                ForEach(matrix.suffix(count(in: geometry.frame(in: .local).size))) { day in
                    HeatmapStat(day: day, onTap: onSelectDay)
                }
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
    }
    
    private var frameAlignment: Alignment {
        switch alignment {
        case .center: return .center
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }
        
    private func count(in size: CGSize) -> Int {
        let cellHeight = (size.height + gridSpacing) / CGFloat(heatmapDaysInWeek)
        if cellHeight <= 0 {
            return 0
        }
        let cellWidth = cellHeight
        let columns = Int(floor((size.width + gridSpacing) / cellWidth))
        let fullCells = Int(columns) * heatmapDaysInWeek
        
        let today = Calendar.current.startOfDay(for: .now)
        let weekday = Calendar.current.dateComponents([.weekday], from: today).weekday!
        let lastColumn = (weekday + 1) - Calendar.current.firstWeekday
        if lastColumn % heatmapDaysInWeek == 0 {
            return fullCells
        }
        return fullCells - heatmapDaysInWeek + lastColumn
    }
}

struct HeatMap_Previews: PreviewProvider {
    static var previews: some View {
        Heatmap(matrix: DailyUsageStat.initialMatrix, alignment: .center)
    }
}
