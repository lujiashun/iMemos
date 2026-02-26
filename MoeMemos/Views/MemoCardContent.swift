//
//  MemoCardContent.swift
//  MoeMemos
//
//  Created by Mudkip on 2023/3/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
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
        
        // No debug prints in production; keep init lightweight
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Always show memo content.
            #if canImport(MarkdownUI)
            MarkdownView(memo.content)
                .markdownImageProvider(.lazyImage(aspectRatio: 4 / 3))
                .markdownCodeSyntaxHighlighter(colorScheme == .dark ? .dark() : .light())
                .onTapGesture {
                    if ignoreContentTap { return }
                }
            #else
            Text(memo.content)
                .onTapGesture {
                    if ignoreContentTap { return }
                }
            #endif
            
            ForEach(resources()) { content in
                if case let .images(urls) = content {
                    MemoCardImageView(images: urls)
                        .onTapGesture {
                            if ignoreContentTap { return }
                        }
                }
                if case let .attachment(resource) = content {
                    Attachment(resource: resource)
                        .onTapGesture {
                            if ignoreContentTap { return }
                        }
                }
                if case let .audio(resource) = content {
                    if isExplore {
                        VStack(alignment: .leading, spacing: 8) {
                            AudioPlayerView(resource: resource, textContent: memo.content, ignoreContentTap: $ignoreContentTap, isExplore: isExplore)
                        }
                        .padding(EdgeInsets(top: 8, leading: 10, bottom: 10, trailing: 10))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.gray.opacity(0.12))
                        )
                    } else {
                        AudioPlayerView(resource: resource, textContent: memo.content, ignoreContentTap: $ignoreContentTap, isExplore: isExplore)
                    }
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
    var onDelete: (() -> Void)? = nil
    
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
    // Raw/punctuated transcript states (for showing 原文)
    @State private var rawTranscript: String?
    @State private var punctuatedTranscript: String?
    @State private var isPunctuating = false
    @State private var punctuateError: Error?

    // Refined transcript (server-side) shown only for Explore mode
    @State private var refinedTranscript: String?
    @State private var isRefining: Bool = false
    @State private var refineError: Error?
    @State private var copied = false

    // Simple in-memory cache to avoid repeated transcription for same resource
    private static var transcriptCache: [String: String] = [:]
    // Cache for server-refined transcripts
    private static var refinedTranscriptCache: [String: String] = [:]
    
    // Local lightweight punctuator (kept here to avoid dependency on external helper at compile time)
    private static func localPunctuate(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }

        let punctSet = CharacterSet(charactersIn: "，。！？；,.!?；；")
        if s.rangeOfCharacter(from: punctSet) != nil {
            return s
        }

        s = s.replacingOccurrences(of: "\n", with: "。")
        let comps = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if comps.isEmpty { return s }
        if s.count <= 12 {
            if s.hasSuffix("。") || s.hasSuffix("?") || s.hasSuffix("!") {
                return s
            }
            return s + "。"
        }

        var pieces: [String] = []
        for (i, token) in comps.enumerated() {
            if i == comps.count - 1 {
                pieces.append(token)
            } else {
                pieces.append(token + "，")
            }
        }
        var result = pieces.joined(separator: " ")
        result = result.replacingOccurrences(of: " ，", with: "，")
        if !result.hasSuffix("。") && !result.hasSuffix("?") && !result.hasSuffix("!") {
            result += "。"
        }
        return result
    }
    
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
                        .padding(.trailing, 0)
                    }
                    .contentShape(Rectangle()) // Explicit hit-testing area
                    .highPriorityGesture(TapGesture().onEnded {
                        handledByHighPriority = true
                        performExpandTapped()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { handledByHighPriority = false }
                    })
                }
                .background(Color.clear)
                // (delete button moved below expanded transcript)
            }
            
            // Expanded Text Content
            // Precompute displayText here to avoid placing statements inside ViewBuilder.
            let displayText = isExplore ? (refinedTranscript ?? punctuatedTranscript ?? rawTranscript ?? textContent) : (punctuatedTranscript ?? rawTranscript ?? textContent)
            if isExpanded {
                if isPunctuating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("AI转写中…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                } else if isRefining {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("优化中…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                } else if displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("无文字内容")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                } else {
                    Group {
                        #if canImport(MarkdownUI)
                        MarkdownView(displayText)
                            .markdownImageProvider(.lazyImage(aspectRatio: 4 / 3))
                            .markdownCodeSyntaxHighlighter(colorScheme == .dark ? .dark() : .light())
                        #else
                        Text(displayText)
                        #endif
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Copy button: show only in Explore mode under the displayed transcript
                if isExplore && !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack {
                        Button(action: { copyTranscript() }) {
                            Image(systemName: copied ? "doc.on.doc.fill" : "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(copied ? Color.accentColor : Color.secondary)
                                .padding(8)
                                .background(copied ? Color.accentColor.opacity(0.12) : Color.clear)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.borderless)
                        .animation(.easeInOut(duration: 0.18), value: copied)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }

                // Delete button: show in editor (not Explore) under the expanded transcript.
                // Previously the button was hidden when there was no display text; keep it visible
                // so users can delete the audio even if the original text is empty or failed to load.
                if !isExplore && isExpanded {
                    HStack {
                        Button(action: {
                            onDelete?()
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(8)
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }

                if let err = punctuateError {
                    Text("（原文恢复失败，显示可用文字）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                if let err = refineError {
                    Text("（优化失败，显示原文）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
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
        handlePlayButton()
    }

    private func performExpandTapped() {
        ignoreContentTap.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ignoreContentTap.wrappedValue = false }
        withAnimation {
            isExpanded.toggle()
        }
        if isExpanded {
            // start async task to ensure we have a punctuated transcript
            Task { await ensurePunctuatedTranscript() }
        }
    }

    private func copyTranscript() {
        let text = refinedTranscript ?? punctuatedTranscript ?? rawTranscript ?? textContent
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = trimmed
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(trimmed, forType: .string)
        #endif
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }

    private func ensurePunctuatedTranscript() async {
        // If already have punctuated transcript, still ensure we perform server-side refine for Explore
        if punctuatedTranscript != nil {
            // If in Explore mode and refined not available, attempt refine (or use cache)
            if isExplore {
                let key = resource.remoteId ?? resource.url.absoluteString
                if let cachedRefined = Self.refinedTranscriptCache[key] {
                    DispatchQueue.main.async { self.refinedTranscript = cachedRefined }
                } else {
                    // Kick off refine in background without blocking
                    Task { @MainActor in
                        if refinedTranscript == nil {
                            if let service = accountManager.currentService {
                                self.isRefining = true
                                self.refineError = nil
                                do {
                                    let prompt = makeAudioTranscriptRefinePrompt(self.punctuatedTranscript ?? "")
                                    let refined = try await service.getTextRefine(filter: nil, prompt: prompt)
                                    if !refined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        self.refinedTranscript = refined
                                        Self.refinedTranscriptCache[key] = refined
                                    }
                                } catch {
                                    self.refineError = error
                                }
                                self.isRefining = false
                            }
                        }
                    }
                }
            }
            return
        }

        let key = resource.remoteId ?? resource.url.absoluteString
        if let cached = Self.transcriptCache[key] {
            DispatchQueue.main.async {
                self.punctuatedTranscript = cached
            }
            return
        }

        isPunctuating = true
        punctuateError = nil
        do {
            let localURL: URL
            if let service = accountManager.currentService {
                localURL = try await service.download(url: resource.url, mimeType: resource.mimeType)
            } else {
                localURL = resource.url
            }

            let transcript = try await SpeechTranscriber.transcribeAudioFile(at: localURL)
            
            DispatchQueue.main.async {
                self.rawTranscript = transcript
            }

            let punctuated = Self.localPunctuate(transcript)
            
            DispatchQueue.main.async {
                self.punctuatedTranscript = punctuated
                Self.transcriptCache[key] = punctuated
            }
            // If this view is rendered in Explore, attempt server-side refine asynchronously
            if isExplore {
                if let cachedRefined = Self.refinedTranscriptCache[key] {
                    DispatchQueue.main.async {
                        self.refinedTranscript = cachedRefined
                    }
                } else if let service = accountManager.currentService {
                    DispatchQueue.main.async {
                        self.isRefining = true
                        self.refineError = nil
                    }
                    do {
                        let prompt = makeAudioTranscriptRefinePrompt(punctuated)
                        let refined = try await service.getTextRefine(filter: nil, prompt: prompt)
                        if !refined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            DispatchQueue.main.async {
                                self.refinedTranscript = refined
                                Self.refinedTranscriptCache[key] = refined
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.refineError = error
                        }
                    }
                    DispatchQueue.main.async {
                        self.isRefining = false
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.punctuateError = error
            }
        }
        DispatchQueue.main.async {
            self.isPunctuating = false
        }
    }

    private func loadAndPlay() {
        // Cancel any existing task
        currentTask?.cancel()
        
        guard !isLoading else { return }
        isLoading = true
        
        
        
        currentTask = Task {
            do {
                // Set up audio session for playback (only if not already set)
                let audioSession = AVAudioSession.sharedInstance()
                if audioSession.category != .playback {
                    try audioSession.setCategory(.playback, mode: .default)
                    try audioSession.setActive(true)
                    
                }
                
                if let service = accountManager.currentService {
                    
                    let url = try await service.download(url: resource.url, mimeType: resource.mimeType)
                    
                    
                    // Check if task was cancelled
                    if Task.isCancelled { return }
                    
                    // Clean up existing player
                    if let existingPlayer = audioPlayer {
                        existingPlayer.pause()
                        // Don't replace the player if it already exists and is ready
                        if existingPlayer.currentItem?.status == .readyToPlay {
                        
                            existingPlayer.play()
                            self.isPlaying = true
                            isLoading = false
                            return
                        }
                    }
                    
                    // Initialize new player
                    
                    let playerItem = AVPlayerItem(url: url)
                    let player = AVPlayer(playerItem: playerItem)
                    self.audioPlayer = player
                    
                    // Get duration
                    if let asset = player.currentItem?.asset {
                        do {
                            let duration = try await asset.load(.duration)
                            self.duration = CMTimeGetSeconds(duration)
                            
                        } catch {
                        
                        }
                    }
                    
                    // Check if task was cancelled before starting playback
                    if Task.isCancelled { return }
                    
                    
                    player.play()
                    self.isPlaying = true
                } else {
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error
                }
            }
            if !Task.isCancelled {
                isLoading = false
            }
        }
    }
}
