//
//  MemoCardContent.swift
//  MoeMemos
//
//  Created by Mudkip on 2023/3/26.
//

import SwiftUI
@preconcurrency import MarkdownUI
import Models
import AVKit
import Account
import AVFoundation

@MainActor
struct MemoCardContent: View {
    private enum MemoResource: Identifiable {
        case images([ImageInfo])
        case attachment(Resource)
        case audio(Resource)
        
        var id: String {
            switch self {
            case .images(let images):
                return images.map { $0.url.absoluteString }.joined()
            case .attachment(let resource):
                return resource.filename
            case .audio(let resource):
                return "\(resource.remoteId ?? "")"
            }
        }
    }

    let memo: Memo
    let toggleTaskItem: ((TaskListMarkerConfiguration) async -> Void)?
    var isExplore: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(AccountManager.self) private var memosManager: AccountManager
    
    init(memo: Memo, toggleTaskItem: ((TaskListMarkerConfiguration) async -> Void)?, isExplore: Bool = false) {
        self.memo = memo
        self.toggleTaskItem = toggleTaskItem
        self.isExplore = isExplore
        
        // 调试输出，打印资源信息
        #if DEBUG
        print("[调试] memo.content: \(memo.content)")
        print("[调试] memo.resources: \(memo.resources)")
        #endif
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if !isExplore {
                // Standard Mode: Show content first.
                MarkdownView(memo.content)
                    .markdownImageProvider(.lazyImage(aspectRatio: 4 / 3))
                    .markdownCodeSyntaxHighlighter(colorScheme == .dark ? .dark() : .light())
                    .markdownTaskListMarker(BlockStyle { configuration in
                        Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                            .symbolRenderingMode(.hierarchical)
                            .imageScale(.medium)
                            .relativeFrame(minWidth: .em(1), alignment: .leading)
                            .onTapGesture {
                                Task {
                                    await toggleTaskItem?(configuration)
                                }
                            }
                    })
            }
            
            ForEach(resources()) { content in
                if case let .images(urls) = content {
                    MemoCardImageView(images: urls)
                }
                if case let .attachment(resource) = content {
                    Attachment(resource: resource)
                }
                if case let .audio(resource) = content {
                    AudioPlayerView(resource: resource, textContent: isExplore ? memo.content : "")
                }
            }
        }
    }
    
    private func isAudioResource(_ resource: Resource) -> Bool {
        let audioMime = resource.mimeType.hasPrefix("audio/")
        let audioExt = resource.url.pathExtension.lowercased()
        let audioExts = ["m4a", "mp3", "wav", "aac", "ogg", "flac"]
        return audioMime || audioExts.contains(audioExt)
    }

    private func firstAudioResource() -> Resource? {
        return memo.resources.first(where: isAudioResource)
    }

    private func resources() -> [MemoResource] {
        var attachments = [MemoResource]()
        let resourceList = memo.resources

        let imageResources = resourceList.filter { $0.mimeType.hasPrefix("image/") }
        let audioResources = resourceList.filter { isAudioResource($0) }
        let otherResources = resourceList.filter { !$0.mimeType.hasPrefix("image/") && !isAudioResource($0) }

        if !imageResources.isEmpty {
            attachments.append(.images(imageResources.map { ImageInfo(url: $0.url, mimeType: $0.mimeType) }))
        }
        attachments += audioResources.map { .audio($0) }
        attachments += otherResources.map { .attachment($0) }
        return attachments
    }
}

@MainActor
struct AudioPlayerView: View {
    let resource: Resource
    let textContent: String
    
    @Environment(AccountManager.self) private var accountManager
    @Environment(\.colorScheme) var colorScheme
    
    @State private var audioPlayer: AVPlayer?
    @State private var isPlaying = false
    @State private var isExpanded = false
    @State private var isLoading = false
    @State private var duration: TimeInterval = 0
    @State private var error: Error?
    @State private var currentTask: Task<Void, Never>?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Player Control Bar
            HStack {
                Button {
                    handlePlayButton()
                } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16))
                        }
                        
                        Text(formattedDuration)
                            .font(.footnote)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.primary)
                }
                
                Spacer()
                
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起" : "展开")
                            .font(.subheadline)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
            
            // Expanded Text Content
            if isExpanded {
                if textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("无文字内容")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                } else {
                    MarkdownView(textContent)
                        .markdownImageProvider(.lazyImage(aspectRatio: 4 / 3))
                        .markdownCodeSyntaxHighlighter(colorScheme == .dark ? .dark() : .light())
                        .padding(.top, 12)
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .onDisappear {
            // Clean up when view disappears
            currentTask?.cancel()
            audioPlayer?.pause()
            audioPlayer = nil
            isPlaying = false
            isLoading = false
        }
    }
    
    private var formattedDuration: String {
        guard duration > 0 else { return "00:00" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func handlePlayButton() {
        if let player = audioPlayer {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
        } else {
            loadAndPlay()
        }
    }
    
    private func loadAndPlay() {
        // Cancel any existing task
        currentTask?.cancel()
        
        guard !isLoading else { return }
        isLoading = true
        
        print("AudioPlayerView: Starting to load audio for resource: \(resource.url), mimeType: \(resource.mimeType)")
        
        currentTask = Task {
            do {
                // Set up audio session for playback (only if not already set)
                let audioSession = AVAudioSession.sharedInstance()
                if audioSession.category != .playback {
                    try audioSession.setCategory(.playback, mode: .default)
                    try audioSession.setActive(true)
                    print("AudioPlayerView: Audio session set up")
                }
                
                if let service = accountManager.currentService {
                    print("AudioPlayerView: Downloading audio from service")
                    let url = try await service.download(url: resource.url, mimeType: resource.mimeType)
                    print("AudioPlayerView: Downloaded to local URL: \(url)")
                    
                    // Check if task was cancelled
                    if Task.isCancelled { return }
                    
                    // Clean up existing player
                    if let existingPlayer = audioPlayer {
                        existingPlayer.pause()
                        // Don't replace the player if it already exists and is ready
                        if existingPlayer.currentItem?.status == .readyToPlay {
                            print("AudioPlayerView: Reusing existing player")
                            existingPlayer.play()
                            self.isPlaying = true
                            isLoading = false
                            return
                        }
                    }
                    
                    // Initialize new player
                    print("AudioPlayerView: Initializing AVPlayer")
                    let playerItem = AVPlayerItem(url: url)
                    let player = AVPlayer(playerItem: playerItem)
                    self.audioPlayer = player
                    
                    // Get duration
                    if let asset = player.currentItem?.asset {
                        do {
                            let duration = try await asset.load(.duration)
                            self.duration = CMTimeGetSeconds(duration)
                            print("AudioPlayerView: Duration: \(self.duration)")
                        } catch {
                            print("AudioPlayerView: Failed to load duration: \(error)")
                        }
                    }
                    
                    // Check if task was cancelled before starting playback
                    if Task.isCancelled { return }
                    
                    print("AudioPlayerView: Starting playback")
                    player.play()
                    self.isPlaying = true
                } else {
                    print("AudioPlayerView: No current service available")
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error
                    print("AudioPlayerView: Audio playback error: \(error)")
                }
            }
            if !Task.isCancelled {
                isLoading = false
            }
        }
    }
}
