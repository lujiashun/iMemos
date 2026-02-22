//
//  MemoInputResourceView.swift
//  MoeMemos
//
//  Created by Mudkip on 2023/1/24.
//

import SwiftUI

struct MemoInputResourceView: View {
    var viewModel: MemoInputViewModel
    var textContent: String
    
    var body: some View {
        if !viewModel.resourceList.isEmpty || viewModel.imageUploading {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack {
                    ForEach(viewModel.resourceList, id: \.id) { resource in
                        if resource.mimeType.hasPrefix("image/") == true {
                            ResourceCard(resource: resource, resourceManager: viewModel)
                        } else if resource.mimeType.hasPrefix("audio/") {
                            // Use a compact card width in horizontal list so layout resembles Explore cards
                            VStack(alignment: .leading, spacing: 8) {
                                AudioPlayerView(resource: resource, textContent: textContent, ignoreContentTap: .constant(false), isExplore: true)
                            }
                            .padding(10)
                            .frame(width: 340, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.gray.opacity(0.12))
                            )
                            .padding(.vertical, 6)
                        } else {
                            Attachment(resource: resource)
                        }
                    }
                    if viewModel.imageUploading {
                        Color.clear
                            .scaledToFill()
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                ProgressView()
                            }
                    }
                }
                .padding([.leading, .trailing, .bottom])
            }
            .padding(.top, 8)
        }
    }
}

struct MemoInputResourceView_Previews: PreviewProvider {
    static var previews: some View {
        MemoInputResourceView(viewModel: MemoInputViewModel(), textContent: "示例原文：这是一次语音转写的示例。")
    }
}
