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

struct Heatmap: View {
    let matrix: [DailyUsageStat]
    let alignment: HorizontalAlignment
    var columns: Int = 12
    var onSelectDay: ((DailyUsageStat) -> Void)? = nil
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cellSize = heatmapCellSize(in: size)
            let rows = [GridItem](repeating: GridItem(.fixed(cellSize), spacing: gridSpacing), count: heatmapDaysInWeek)
            let visibleCount = min(matrix.count, heatmapDaysInWeek * max(columns, 1))

            LazyHGrid(rows: rows, alignment: .top, spacing: gridSpacing) {
                ForEach(matrix.suffix(visibleCount)) { day in
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
        
    private func heatmapCellSize(in size: CGSize) -> CGFloat {
        let width = size.width
        let height = size.height
        let cols = max(columns, 1)

        let cellByHeight = (height - gridSpacing * CGFloat(heatmapDaysInWeek - 1)) / CGFloat(heatmapDaysInWeek)
        let cellByWidth = (width - gridSpacing * CGFloat(cols - 1)) / CGFloat(cols)
        return max(0, min(cellByHeight, cellByWidth))
    }
}

struct HeatMap_Previews: PreviewProvider {
    static var previews: some View {
        Heatmap(matrix: DailyUsageStat.initialMatrix, alignment: .center)
    }
}
