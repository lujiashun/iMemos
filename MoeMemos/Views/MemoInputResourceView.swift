//
//  MemoInputResourceView.swift
//  MoeMemos
//
//  Created by Mudkip on 2023/1/24.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MemoInputResourceView: View {
    var viewModel: MemoInputViewModel
    var textContent: String

    private let maxImageCount = 9
    private let imageGridSpacing: CGFloat = 12

    private var imageItemSide: CGFloat {
#if canImport(UIKit)
        UIScreen.main.bounds.width / 4
#else
        90
#endif
    }

    private var imageGridWidth: CGFloat {
        imageItemSide * 3 + imageGridSpacing * 2
    }

    private var imageGridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(imageItemSide), spacing: imageGridSpacing, alignment: .center), count: 3)
    }
    
    var body: some View {
        if !viewModel.resourceList.isEmpty || viewModel.imageUploading {
            let imageResources = Array(viewModel.resourceList.filter { $0.mimeType.hasPrefix("image/") }.prefix(maxImageCount))
            let nonImageResources = viewModel.resourceList.filter { !$0.mimeType.hasPrefix("image/") }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !imageResources.isEmpty {
                        HStack {
                            Spacer()
                            LazyVGrid(columns: imageGridColumns, alignment: .center, spacing: imageGridSpacing) {
                                ForEach(imageResources, id: \.id) { resource in
                                    ResourceCard(resource: resource, resourceManager: viewModel, showDeleteButton: true)
                                        .frame(width: imageItemSide, height: imageItemSide)
                                }
                            }
                            .frame(width: imageGridWidth, alignment: .center)
                            Spacer()
                        }
                    }

                    ForEach(nonImageResources, id: \.id) { resource in
                        if resource.mimeType.hasPrefix("audio/") {
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
