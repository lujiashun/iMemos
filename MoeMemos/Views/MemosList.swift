//
//  MemosList.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/4.
//

import SwiftUI
import Account
import Models
import Env

struct MemosList: View {
    let tag: Tag?

    @State private var searchString = ""
    @Environment(AppPath.self) private var appPath
    @Environment(AccountManager.self) private var accountManager: AccountManager
    @Environment(AccountViewModel.self) var userState: AccountViewModel
    @Environment(MemosViewModel.self) private var memosViewModel: MemosViewModel
    @State private var filteredMemoList: [Memo] = []
    
    var body: some View {
        @Bindable var appPath = appPath
        let defaultMemoVisibility = userState.currentUser?.defaultVisibility ?? .private
        let selectedDay = appPath.selectedMemoDay
        
        ZStack(alignment: .bottomTrailing) {
            List(filteredMemoList, id: \.remoteId) { memo in
                Section {
                    MemoCard(memo, defaultMemoVisibility: defaultMemoVisibility)
                }
            }
            .listStyle(InsetGroupedListStyle())
            
            if #unavailable(iOS 26.0) {
                Button {
                    appPath.presentedSheet = .newMemo
                } label: {
                    Circle().overlay {
                        Image(systemName: "plus")
                            .resizable()
                            .frame(width: 25, height: 25)
                            .foregroundColor(.white)
                    }
                    .shadow(radius: 1)
                    .frame(width: 60, height: 60)
                }
                .padding(20)
            }
        }
        .toolbar {
            if #available(iOS 26.0, *) {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        appPath.presentedSheet = .newMemo
                    } label: {
                        Label("input.save", systemImage: "plus")
                    }
                }
            }

            if selectedDay != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        appPath.selectedMemoDay = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .accessibilityLabel(Text("Clear date filter"))
                }
            }
        }
        .overlay(content: {
            if memosViewModel.loading && !memosViewModel.inited {
                ProgressView()
            }
        })
        .searchable(text: $searchString)
        .navigationTitle(tag?.name ?? NSLocalizedString("memo.memos", comment: "Memos"))
        .onAppear {
            filteredMemoList = filterMemoList(memosViewModel.memoList, tag: tag, searchString: searchString, day: selectedDay)
        }
        .refreshable {
            do {
                try await memosViewModel.loadMemos()
            } catch {
                print(error)
            }
        }
        .onChange(of: memosViewModel.memoList) { _, newValue in
            filteredMemoList = filterMemoList(newValue, tag: tag, searchString: searchString, day: selectedDay)
        }
        .onChange(of: tag) { _, newValue in
            filteredMemoList = filterMemoList(memosViewModel.memoList, tag: newValue, searchString: searchString, day: selectedDay)
        }
        .onChange(of: searchString) { _, newValue in
            filteredMemoList = filterMemoList(memosViewModel.memoList, tag: tag, searchString: newValue, day: selectedDay)
        }
        .onChange(of: selectedDay) { _, newValue in
            filteredMemoList = filterMemoList(memosViewModel.memoList, tag: tag, searchString: searchString, day: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                if memosViewModel.inited {
                    try await memosViewModel.loadMemos()
                }
            }
        }
    }
    
    private func filterMemoList(_ memoList: [Memo], tag: Tag?, searchString: String, day: Date?) -> [Memo] {
        let pinned = memoList.filter { $0.pinned == true }
        let nonPinned = memoList.filter { $0.pinned != true }
        var fullList = pinned + nonPinned

        if let day {
            fullList = fullList.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }
        }
        
        if let tag = tag {
            fullList = fullList.filter({ memo in
                memo.content.contains("#\(tag.name) ") || memo.content.contains("#\(tag.name)/")
                || memo.content.contains("#\(tag.name)\n")
                || memo.content.hasSuffix("#\(tag.name)")
            })
        }
        
        if !searchString.isEmpty {
            fullList = fullList.filter({ memo in
                memo.content.localizedCaseInsensitiveContains(searchString)
            })
        }
        
        return fullList
    }
}
