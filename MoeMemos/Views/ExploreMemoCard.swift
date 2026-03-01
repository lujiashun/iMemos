//
//  ExploreMemoCard.swift
//  MoeMemos
//
//  Created by Mudkip on 2023/3/26.
//

import SwiftUI
import Models
import Account

struct ExploreMemoCard: View {
    let memo: Memo
    @Environment(AccountViewModel.self) private var userState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(memo.renderTime())
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                if let creatorName = memo.user?.nickname {
                    Text("@\(creatorName)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
            
            MemoCard(memo, defaultMemoVisibility: userState.currentUser?.defaultVisibility ?? .private, isExplore: true)
        }
        .padding([.top, .bottom], 2)
    }
}
