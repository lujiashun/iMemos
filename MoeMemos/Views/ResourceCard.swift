//
//  ResourceCard.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/11.
//

import SwiftUI
import Models
import Account

@MainActor
struct ResourceCard: View {
    let resource: Resource
    let resourceManager: ResourceManager
    
    init(resource: Resource, resourceManager: ResourceManager) {
        self.resource = resource
        self.resourceManager = resourceManager
    }
    
    @Environment(MemosViewModel.self) private var memosViewModel: MemosViewModel
    @Environment(AccountManager.self) private var memosManager: AccountManager
    @State private var imagePreviewURL: URL?
    @State private var downloadedURL: URL?
    @State private var isDownloading = false
    @State private var downloadFailed = false
    
    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let downloadedURL = downloadedURL {
                    AsyncImage(url: downloadedURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .onTapGesture {
                        imagePreviewURL = downloadedURL
                    }
                } else if isDownloading {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay { ProgressView() }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay {
                            Image(systemName: downloadFailed ? "exclamationmark.triangle" : "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contextMenu {
                menu(for: resource)
            }
            .task {
                do {
                    if downloadedURL == nil, let memos = memosManager.currentService {
                        isDownloading = true
                        downloadFailed = false
                        downloadedURL = try await memos.download(url: resource.url, mimeType: resource.mimeType)
                    }
                } catch {
                    downloadFailed = true
                }
                isDownloading = false
            }
            .fullScreenCover(item: $imagePreviewURL) { url in
                QuickLookPreview(selectedURL: url, urls: [url])
                    .edgesIgnoringSafeArea(.bottom)
                    .background(TransparentBackground())
            }
    }
    
    @ViewBuilder
    func menu(for resource: Resource) -> some View {
        Button(role: .destructive, action: {
            Task {
                guard let remoteId = resource.remoteId else { return }
                try await resourceManager.deleteResource(remoteId: remoteId)
            }
        }, label: {
            Label("Delete", systemImage: "trash")
        })
    }
}
