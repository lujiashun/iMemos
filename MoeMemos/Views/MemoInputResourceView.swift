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
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.resourceList, id: \.id) { resource in
                        if resource.mimeType.hasPrefix("image/") == true {
                            ResourceCard(resource: resource, resourceManager: viewModel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if resource.mimeType.hasPrefix("audio/") {
                            VStack(alignment: .leading, spacing: 8) {
                                    AudioPlayerView(resource: resource, textContent: textContent, ignoreContentTap: .constant(false), isExplore: false, onDelete: {
                                        Task {
                                            if let remoteId = resource.remoteId {
                                                try? await viewModel.deleteResource(remoteId: remoteId)
                                            }
                                        }
                                    })
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.gray.opacity(0.12))
                            )
                            .padding(.vertical, 6)
                        } else {
                            Attachment(resource: resource)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if viewModel.imageUploading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.gray.opacity(0.08))
                        )
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
