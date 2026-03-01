//
//  ResourceCard.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/11.
//

import SwiftUI
import Models
import Account

#if DEBUG
import OSLog
private let resourceCardLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MoeMemos", category: "ResourceCard")
#endif

@MainActor
struct ResourceCard: View {
    let resource: Resource
    let resourceManager: ResourceManager
    let showDeleteButton: Bool

    init(resource: Resource, resourceManager: ResourceManager, showDeleteButton: Bool = false) {
        self.resource = resource
        self.resourceManager = resourceManager
        self.showDeleteButton = showDeleteButton
    }

    @Environment(AccountManager.self) private var memosManager: AccountManager
    @State private var imagePreviewURL: URL?
    @State private var downloadedURL: URL?
    @State private var isDownloading = false
    @State private var downloadFailed = false
    @State private var retryCount = 0
    private let maxRetries = 3

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let downloadedURL = downloadedURL {
                    AsyncImage(url: downloadedURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        @unknown default:
                            EmptyView()
                        }
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
                        .onTapGesture {
                            guard downloadFailed else { return }
                            downloadFailed = false
                            retryCount = 0
                            Task { await downloadResource() }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if showDeleteButton {
                    Button(role: .destructive) {
                        Task { await deleteCurrentResource() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white, .black.opacity(0.75))
                            .padding(6)
                    }
                }
            }
            .contextMenu {
                if !showDeleteButton {
                    menu(for: resource)
                }
            }
            .task(id: resource.id) { await downloadResource() }
            .fullScreenCover(item: $imagePreviewURL) { url in
                QuickLookPreview(selectedURL: url, urls: [url])
                    .edgesIgnoringSafeArea(.bottom)
                    .background(TransparentBackground())
            }
    }
    
    @ViewBuilder
    func menu(for resource: Resource) -> some View {
        Button(role: .destructive, action: {
            Task { await deleteCurrentResource() }
        }, label: {
            Label("Delete", systemImage: "trash")
        })
    }

    private func deleteCurrentResource() async {
        guard let remoteId = resource.remoteId else { return }
        try? await resourceManager.deleteResource(remoteId: remoteId)
    }

    private func downloadResource() async {
        guard downloadedURL == nil, !isDownloading, let memos = memosManager.currentService else { return }

        // 防止重试过多
        guard retryCount < maxRetries else {
            downloadFailed = true
            return
        }

        isDownloading = true
        downloadFailed = false
        retryCount += 1

#if DEBUG
        resourceCardLogger.debug("start download image: \(resource.url.absoluteString, privacy: .public) attempt: \(self.retryCount)")
#endif
        defer { isDownloading = false }

        do {
            // 添加超时机制
            downloadedURL = try await withTimeout(seconds: 30) {
                try await ImageDownloadCoordinator.shared.withPermit {
                    try await memos.download(url: resource.url, mimeType: resource.mimeType)
                }
            }
#if DEBUG
            resourceCardLogger.debug("download success image: \(resource.url.absoluteString, privacy: .public)")
#endif
        } catch {
            if isCancellationError(error) {
#if DEBUG
                resourceCardLogger.debug("download cancelled image: \(resource.url.absoluteString, privacy: .public)")
#endif
                return
            }

            // 网络错误时自动重试
            if isNetworkError(error) && retryCount < maxRetries {
#if DEBUG
                resourceCardLogger.warning("download failed, will retry: \(resource.url.absoluteString, privacy: .public) attempt: \(self.retryCount)")
#endif
                // 延迟后重试
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                Task { await downloadResource() }
                return
            }

            downloadFailed = true
#if DEBUG
            let nsError = error as NSError
            resourceCardLogger.error("download failed image: \(resource.url.absoluteString, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
#endif
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        return false
    }
}

// 超时辅助函数
func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @Sendable @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw URLError(.timedOut)
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
