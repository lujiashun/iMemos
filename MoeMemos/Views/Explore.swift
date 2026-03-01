//
//  Explore.swift
//  MoeMemos
//
//  Created by Mudkip on 2023/3/26.
//

import SwiftUI

struct Explore: View {
    @State private var viewModel = ExploreViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.memoList, id: \.remoteId) { memo in
                    ExploreMemoCard(memo: memo)
                        .padding(.horizontal, 16)
                        .onAppear {
                            Task {
                                if viewModel.memoList.firstIndex(where: { $0.remoteId == memo.remoteId }) == viewModel.memoList.count - 2 {
                                    try await viewModel.loadMoreMemos()
                                }
                            }
                        }
                }
            }
        }
        .navigationTitle("explore")
        .task {
            do {
                try await viewModel.loadMemos()
            } catch {
                print(error)
            }
        }
        .refreshable {
            do {
                try await viewModel.loadMemos()
            } catch {
                print(error)
            }
        }
    }
}

struct Explore_Previews: PreviewProvider {
    static var previews: some View {
        Explore()
    }
}
