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

fileprivate let weekDaySymbols: [String] = {
    var symbols = Calendar.current.shortWeekdaySymbols
    let firstWeekday = Calendar.current.firstWeekday - 1
    return [String](symbols[firstWeekday...] + symbols[0..<firstWeekday])
}()

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
            
            HStack {
                VStack(alignment: .trailing) {
                    Text(weekDaySymbols.first ?? "")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Text(weekDaySymbols[weekDaySymbols.count / 2])
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Text(weekDaySymbols.last ?? "")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Heatmap(matrix: memosViewModel.matrix, alignment: .trailing) { day in
                    appPath.selectedMemoDay = day.date
                    navigationSelect.perform(.memos)

                    // On iPhone, the sidebar is an overlay; explicitly dismiss it.
                    onSidebarItemSelect?()

                    // On iPad/vision, collapse the split view sidebar.
                    if isPadOrVision {
                        sidebarToggle.perform()
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 120)
            .padding(.bottom, 10)
            .padding(.horizontal, 20)
        }
    }
    
    func days() -> Int {
        guard let user = userState.currentUser else { return 0 }
        return Calendar.current.dateComponents([.day], from: user.creationDate, to: .now).day!
    }
}
