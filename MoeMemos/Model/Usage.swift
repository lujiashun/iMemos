//
//  Usage.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/4.
//

import Foundation
import Models

struct DailyUsageStat: Identifiable {
    let date: Date
    var count: Int
    
    var id: String {
        date.formatted(date: .numeric, time: .omitted)
    }
    
    static let initialMatrix: [DailyUsageStat] = {
        let today = Calendar.current.startOfDay(for: .now)
        
        return Calendar.current.range(of: .day, in: .year, for: Date())!.map { day in
            return Self.init(date: Calendar.current.date(byAdding: .day, value: 1 - day, to: today)!, count: 0)
        }.reversed()
    }()
    
    static func calculateMatrix(memoList: [Memo]) -> [DailyUsageStat] {
        var result = DailyUsageStat.initialMatrix
        var countDict = [String: Int]()
        
        for memo in memoList {
            let key = memo.createdAt.formatted(date: .numeric, time: .omitted)
            countDict[key] = (countDict[key] ?? 0) + 1
        }
        
        for (i, day) in result.enumerated() {
            result[i].count = countDict[day.id] ?? 0
        }
        
        return result
    }

    /// Aligns a day-by-day matrix to week boundaries for heatmap rendering.
    /// This pads leading days to the start of the week and also pads trailing days
    /// through the end of the current week, so grids with a fixed number of columns
    /// still map weekdays correctly.
    static func alignedForHeatmap(matrix: [DailyUsageStat], firstWeekday: Int = 2) -> [DailyUsageStat] {
        guard let first = matrix.first else { return matrix }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = firstWeekday

        let start = calendar.startOfDay(for: first.date)
        let today = calendar.startOfDay(for: .now)
        let displayStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let displayEnd: Date = {
            if let interval = calendar.dateInterval(of: .weekOfYear, for: today),
               let end = calendar.date(byAdding: .day, value: -1, to: interval.end) {
                return calendar.startOfDay(for: end)
            }
            return today
        }()

        var countsByDay: [Date: Int] = [:]
        countsByDay.reserveCapacity(matrix.count)
        for day in matrix {
            countsByDay[calendar.startOfDay(for: day.date)] = day.count
        }

        var aligned: [DailyUsageStat] = []
        var cursor = displayStart
        while cursor <= displayEnd {
            aligned.append(.init(date: cursor, count: countsByDay[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return aligned
    }
}
