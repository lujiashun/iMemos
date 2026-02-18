//
//  MemosList.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/4.
//

import SwiftUI
import Account
import Models
import Env
import DesignSystem
import ServiceUtils


#if DEBUG
import OSLog

fileprivate let audioMemoLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MoeMemos",
    category: "AudioMemo"
)
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

struct MemosList: View {
    let tag: Tag?

    @State private var searchString = ""
    @State private var isSearchPresented = false
    @Environment(AppPath.self) private var appPath
    @Environment(AccountManager.self) private var accountManager: AccountManager
    @Environment(AccountViewModel.self) var userState: AccountViewModel
    @Environment(MemosViewModel.self) private var memosViewModel: MemosViewModel
    @State private var filteredMemoList: [Memo] = []

    @State private var audioRecorder = AudioMemoRecorder()
    @State private var isRecordingAudio = false
    @State private var isProcessingAudio = false
    @State private var audioActionError: Error?
    @State private var showingAudioErrorToast = false
    
    var body: some View {
        @Bindable var appPath = appPath
        let defaultMemoVisibility = userState.currentUser?.defaultVisibility ?? .private
        let selectedDay = appPath.selectedMemoDay
        
        ZStack(alignment: .bottom) {
            List(filteredMemoList, id: \.remoteId) { memo in
                Section {
                    MemoCard(memo, defaultMemoVisibility: defaultMemoVisibility)
                }
            }
            .listStyle(InsetGroupedListStyle())
            
            if #unavailable(iOS 26.0) {
                addMemoButton(style: .floatingCircle)
                .padding(.bottom, 20)
            }

            if isRecordingAudio {
                recordingHUD
                    .padding(.bottom, 100)
            } else if isProcessingAudio {
                processingHUD
                    .padding(.bottom, 100)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    isSearchPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }

                if selectedDay != nil {
                    Button {
                        appPath.selectedMemoDay = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .accessibilityLabel(Text("Clear date filter"))
                }
            }

            if #available(iOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    addMemoButton(style: .bottomBar)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
            }
        }
        .overlay(content: {
            if memosViewModel.loading && !memosViewModel.inited {
                ProgressView()
            }
        })
        .searchable(text: $searchString, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("搜索"))
        .navigationTitle(tag?.name ?? NSLocalizedString("memo.memos", comment: "Memos"))
        .onAppear {
            filteredMemoList = filterMemoList(memosViewModel.memoList, tag: tag, searchString: searchString, day: selectedDay)
        }
        .refreshable {
            do {
                try await memosViewModel.loadMemos()
            } catch {
                print(error)
            }
        }
        .onChange(of: memosViewModel.memoList) { _, newValue in
            filteredMemoList = filterMemoList(newValue, tag: tag, searchString: searchString, day: selectedDay)
        }
        .onChange(of: tag) { _, newValue in
            filteredMemoList = filterMemoList(memosViewModel.memoList, tag: newValue, searchString: searchString, day: selectedDay)
        }
        .onChange(of: searchString) { _, newValue in
            filteredMemoList = filterMemoList(memosViewModel.memoList, tag: tag, searchString: newValue, day: selectedDay)
        }
        .onChange(of: selectedDay) { _, newValue in
            filteredMemoList = filterMemoList(memosViewModel.memoList, tag: tag, searchString: searchString, day: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                if memosViewModel.inited {
                    try await memosViewModel.loadMemos()
                }
            }
        }
        .toast(isPresenting: $showingAudioErrorToast, duration: 2, alertType: .systemImage("xmark.circle", audioActionError.map(userFacingErrorMessage)))
    }

    private enum AddMemoButtonStyle {
        case floatingCircle
        case bottomBar
    }

    @ViewBuilder
    private func addMemoButton(style: AddMemoButtonStyle) -> some View {
        let tapAction = {
            appPath.newMemoPrefillContent = nil
            appPath.newMemoPrefillResources = []
            appPath.presentedSheet = .newMemo
        }

        let longPress = LongPressGesture(minimumDuration: 0.35, maximumDistance: 12)
            .onEnded { _ in
                startAudioRecording()
            }

        let releaseDetector = DragGesture(minimumDistance: 0)
            .onEnded { _ in
                if isRecordingAudio {
                    stopAudioRecordingAndPrepareMemo()
                }
            }

        Group {
            switch style {
            case .floatingCircle:
                ZStack {
                    Circle()
                        .shadow(radius: 1)

                    Image(systemName: "plus")
                        .resizable()
                        .frame(width: 25, height: 25)
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60)
            case .bottomBar:
                Label("input.save", systemImage: "plus")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRecordingAudio && !isProcessingAudio else { return }
            tapAction()
        }
        .highPriorityGesture(longPress)
        .simultaneousGesture(releaseDetector)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var recordingHUD: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
            Text("录音中…松开结束")
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var processingHUD: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在处理音频…")
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private func startAudioRecording() {
        guard !isRecordingAudio && !isProcessingAudio else { return }

        Task { @MainActor in
            do {
                try await audioRecorder.start()
                isRecordingAudio = true
                audioActionError = nil
            } catch {
                audioActionError = error
                showingAudioErrorToast = true
            }
        }
    }

    private func stopAudioRecordingAndPrepareMemo() {
        guard isRecordingAudio && !isProcessingAudio else { return }

        isRecordingAudio = false
        isProcessingAudio = true

    #if DEBUG
        let processingStartedAt = CFAbsoluteTimeGetCurrent()
    #endif

        // Capture actor-isolated values up-front on the MainActor.
        let fileURL: URL
        let service: RemoteService
        do {
            fileURL = try audioRecorder.stop()
            service = try accountManager.mustCurrentService
        } catch {
#if DEBUG
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - processingStartedAt) * 1000
            audioMemoLogger.error("Audio memo: failed before background work (\(elapsedMs, privacy: .public)ms): \(String(describing: error), privacy: .public)")
#endif
            audioActionError = error
            showingAudioErrorToast = true
            isProcessingAudio = false
            return
        }

        Task.detached(priority: .userInitiated) {
            do {
#if DEBUG
                let ioStartedAt = CFAbsoluteTimeGetCurrent()
#endif
                // Synchronous file IO can be expensive; keep it off the main thread.
                let audioData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])

#if DEBUG
                let ioMs = (CFAbsoluteTimeGetCurrent() - ioStartedAt) * 1000
                audioMemoLogger.debug("Audio memo: read \(audioData.count, privacy: .public) bytes in \(ioMs, privacy: .public)ms")
#endif

                async let createdResource: Resource = service.createResource(
                    filename: fileURL.lastPathComponent,
                    data: audioData,
                    type: "audio/mp4",
                    memoRemoteId: nil
                )

                async let transcript: String? = {
                    do {
                        return try await SpeechTranscriber.transcribeAudioFile(at: fileURL)
                    } catch {
                        return nil
                    }
                }()

                let resource = try await createdResource
                let text = await transcript

                await MainActor.run {
                    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let existing = appPath.newMemoPrefillContent ?? ""
                        appPath.newMemoPrefillContent = existing.isEmpty ? text : (existing + "\n" + text)
                    }

                    appPath.newMemoPrefillResources.append(resource)
                    appPath.presentedSheet = .newMemo
                    isProcessingAudio = false

#if DEBUG
                    let totalMs = (CFAbsoluteTimeGetCurrent() - processingStartedAt) * 1000
                    audioMemoLogger.debug("Audio memo: succeeded in \(totalMs, privacy: .public)ms")
#endif
                }
            } catch {
                await MainActor.run {
#if DEBUG
                    let totalMs = (CFAbsoluteTimeGetCurrent() - processingStartedAt) * 1000
                    audioMemoLogger.error("Audio memo: failed in \(totalMs, privacy: .public)ms: \(String(describing: error), privacy: .public)")
#endif
                    audioActionError = error
                    showingAudioErrorToast = true
                    isProcessingAudio = false
                }
            }
        }
    }
    
    private func filterMemoList(_ memoList: [Memo], tag: Tag?, searchString: String, day: Date?) -> [Memo] {
        let pinned = memoList.filter { $0.pinned == true }
        let nonPinned = memoList.filter { $0.pinned != true }
        var fullList = pinned + nonPinned

        if let day {
            fullList = fullList.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }
        }
        
        if let tag = tag {
            fullList = fullList.filter({ memo in
                memo.content.contains("#\(tag.name) ") || memo.content.contains("#\(tag.name)/")
                || memo.content.contains("#\(tag.name)\n")
                || memo.content.hasSuffix("#\(tag.name)")
            })
        }
        
        if !searchString.isEmpty {
            fullList = fullList.filter({ memo in
                memo.content.localizedCaseInsensitiveContains(searchString)
            })
        }
        
        return fullList
    }
}

