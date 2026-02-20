//
//  MemoCardContent.swift
//  MoeMemos
//
//  Created by Mudkip on 2023/3/26.
//

import SwiftUI
#if canImport(MarkdownUI)
@preconcurrency import MarkdownUI
#endif
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
    @State private var ignoreContentTap = false
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
                #if canImport(MarkdownUI)
                MarkdownView(memo.content)
                    .markdownImageProvider(.lazyImage(aspectRatio: 4 / 3))
                    .markdownCodeSyntaxHighlighter(colorScheme == .dark ? .dark() : .light())
                    .onTapGesture {
                        if ignoreContentTap { print("[MemoCardContent] content tap ignored (Markdown) memoRemoteId=\(memo.remoteId ?? "<nil>")"); return }
                        print("[MemoCardContent] content tapped (Markdown) memoRemoteId=\(memo.remoteId ?? "<nil>")")
                    }
#else
                Text(memo.content)
                    .onTapGesture {
                        if ignoreContentTap { print("[MemoCardContent] content tap ignored (Text) memoRemoteId=\(memo.remoteId ?? "<nil>")"); return }
                        print("[MemoCardContent] content tapped (Text) memoRemoteId=\(memo.remoteId ?? "<nil>")")
                    }
#endif
            }
            
            ForEach(resources()) { content in
                if case let .images(urls) = content {
                    MemoCardImageView(images: urls)
                        .onTapGesture {
                            print("[MemoCardContent] image tapped memoRemoteId=\(memo.remoteId ?? "<nil>")")
                        }
                }
                if case let .attachment(resource) = content {
                    Attachment(resource: resource)
                        .onTapGesture {
                            print("[MemoCardContent] attachment tapped resource=\(resource.filename) memoRemoteId=\(memo.remoteId ?? "<nil>")")
                        }
                }
                if case let .audio(resource) = content {
                    AudioPlayerView(resource: resource, textContent: memo.content, ignoreContentTap: $ignoreContentTap, isExplore: isExplore)
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
            @State private var currentTime: TimeInterval = 0
            @State private var timeObserverToken: Any?
        @State private var endObserver: NSObjectProtocol?
    let resource: Resource
    let textContent: String
    var ignoreContentTap: Binding<Bool> = .constant(false)
    var isExplore: Bool = false
    
    @Environment(AccountManager.self) private var accountManager
    @Environment(\.colorScheme) var colorScheme
    
    @State private var audioPlayer: AVPlayer?
    @State private var isPlaying = false
    @State private var isExpanded = false
    @State private var isLoading = false
    @State private var duration: TimeInterval = 0
    @State private var error: Error?
    @State private var currentTask: Task<Void, Never>?
    @State private var handledByHighPriority = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Player Control Bar
            HStack(alignment: .center, spacing: 0) {
                ZStack {
                    Button(action: {
                        if handledByHighPriority {
                            handledByHighPriority = false
                            return
                        }
                        performPlayTapped()
                    }) {
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
                        .padding(.vertical, 8)
                        .padding(.leading, 4)
                        .padding(.trailing, 12)
                    }
                    .contentShape(Rectangle()) // Explicit hit-testing area
                    .highPriorityGesture(TapGesture().onEnded {
                        handledByHighPriority = true
                        performPlayTapped()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { handledByHighPriority = false }
                    })
                }
                .background(Color.clear)
                Spacer(minLength: 0)
                ZStack {
                    Button(action: {
                        if handledByHighPriority {
                            handledByHighPriority = false
                            return
                        }
                        performExpandTapped()
                    }) {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "收起" : (isExplore ? "原文" : "原文"))
                                .font(.subheadline)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.trailing, 8)
                    }
                    .contentShape(Rectangle()) // Explicit hit-testing area
                    .highPriorityGesture(TapGesture().onEnded {
                        handledByHighPriority = true
                        performExpandTapped()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { handledByHighPriority = false }
                    })
                }
                .background(Color.clear)
            }
            
            // Expanded Text Content
            if isExpanded {
                if textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("无文字内容")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                } else {
                    Group {
                        #if canImport(MarkdownUI)
                        MarkdownView(textContent)
                            .markdownImageProvider(.lazyImage(aspectRatio: 4 / 3))
                            .markdownCodeSyntaxHighlighter(colorScheme == .dark ? .dark() : .light())
                        #else
                        Text(textContent)
                        #endif
                    }
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
            if let endObserver = endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            if let token = timeObserverToken, let player = audioPlayer {
                player.removeTimeObserver(token)
                timeObserverToken = nil
            }
        }
        .onChange(of: audioPlayer) { _, newPlayer in
            // 移除旧监听
            if let endObserver = endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            // 添加新监听
                if let player = newPlayer, let item = player.currentItem {
                self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                    DispatchQueue.main.async {
                        isPlaying = false
                        player.seek(to: .zero)
                        currentTime = 0
                    }
                }
                // 添加播放进度监听
                let interval = CMTime(seconds: 0.2, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                    DispatchQueue.main.async {
                        currentTime = CMTimeGetSeconds(time)
                    }
                }
                timeObserverToken = token
            }
            // 移除旧的 timeObserver
            if newPlayer == nil, let token = timeObserverToken, let player = audioPlayer {
                player.removeTimeObserver(token)
                timeObserverToken = nil
            }
        }
    }
    
    private var formattedDuration: String {
        guard duration > 0 else { return "00:00" }
        let remaining = max(duration - currentTime, 0)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
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
    
    // Centralized handlers to avoid duplicate logic and prints
    private func performPlayTapped() {
        ignoreContentTap.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ignoreContentTap.wrappedValue = false }
        print("[AudioPlayerView] play button tapped for resource=\(resource.url)")
        handlePlayButton()
    }

    private func performExpandTapped() {
        ignoreContentTap.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ignoreContentTap.wrappedValue = false }
        print("[AudioPlayerView] expand button tapped for resource=\(resource.url) beforeExpanded=\(isExpanded)")
        withAnimation {
            isExpanded.toggle()
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
