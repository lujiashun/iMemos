//
//  MemoInput.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/5.
//

import SwiftUI
import PhotosUI
import Models
import Account
import Env
 

@MainActor
struct MemoInput: View {
    let memo: Memo?
    @Environment(MemosViewModel.self) private var memosViewModel: MemosViewModel
    @Environment(AccountViewModel.self) var userState: AccountViewModel
    @Environment(AppPath.self) private var appPath
    @State private var viewModel = MemoInputViewModel()

    @State private var text = ""
    @State private var selection: Range<String.Index>? = nil
    @AppStorage("draft") private var draft = ""
    
    @FocusState private var focused: Bool
    @Environment(\.dismiss) var dismiss
    
    @State private var showingPhotoPicker = false
    @State private var showingImagePicker = false

    // Voice input state
    @State private var isRecordingAudio = false
    @State private var isProcessingAudio = false
    @State private var isRecordingPanelPresented = false
    @State private var isRecordingPaused = false
    @State private var recordingElapsed: TimeInterval = 0
    @State private var waveformSamples: [CGFloat] = Array(repeating: 0.12, count: 24)
    @State private var audioActionError: Error?
    @State private var showingAudioErrorToast = false
    @State private var audioRecorder = AudioMemoRecorder()
    @State private var submitError: Error?
    @State private var showingErrorToast = false

    private let maxRecordingDuration: TimeInterval = 180
    private let meterTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let maxImageCount = 9

    private var hasImageResource: Bool {
        viewModel.resourceList.contains(where: { $0.mimeType.hasPrefix("image/") })
    }

    private var hasAudioResource: Bool {
        viewModel.resourceList.contains(where: isAudioResource)
    }

    private var shouldShowImageActions: Bool {
        !hasAudioResource
    }

    private var shouldShowAudioAction: Bool {
        !hasAudioResource && !hasImageResource
    }

    private func isAudioResource(_ resource: Resource) -> Bool {
        if resource.mimeType.hasPrefix("audio/") {
            return true
        }
        let ext = resource.url.pathExtension.lowercased()
        return ["m4a", "mp3", "wav", "aac", "ogg", "flac"].contains(ext)
    }

    private var currentImageCount: Int {
        viewModel.resourceList.filter { $0.mimeType.hasPrefix("image/") }.count
    }

    private var remainingImageSlots: Int {
        max(0, maxImageCount - currentImageCount)
    }

    private func showImageLimitToast(addedCount: Int?) {
        let message: String
        if let addedCount {
            message = "最多可添加\(maxImageCount)张图片，已添加前\(addedCount)张。"
        } else {
            message = "最多可添加\(maxImageCount)张图片。"
        }
        submitError = NSError(domain: "MemoInput", code: 1001, userInfo: [NSLocalizedDescriptionKey: message])
        showingErrorToast = true
    }
    
    @ViewBuilder
    private func toolbar() -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center) {
                if !memosViewModel.tags.isEmpty {
                    ZStack {
                        Menu {
                            ForEach(memosViewModel.tags) { tag in
                                Button(tag.name) {
                                    insert(tag: tag)
                                }
                            }
                        } label: {
                            Color.clear.frame(width: 15)
                        }
                        Button {
                            // Do nothing, pass through to the menu
                        } label: {
                            Image(systemName: "number")
                        }
                        .allowsHitTesting(false)
                    }
                } else {
                    Button {
                        insert(tag: nil)
                    } label: {
                        Image(systemName: "number")
                    }
                }
                Button {
                    toggleTodoItem()
                } label: {
                    Image(systemName: "checkmark.square")
                }
                if shouldShowImageActions {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                    }
                    Button {
                        showingImagePicker = true
                    } label: {
                        Image(systemName: "camera")
                    }
                }
                if shouldShowAudioAction {
                    // --- Voice button ---
                    Button {
                        startAudioRecording()
                    } label: {
                        Image(systemName: "mic.circle")
                            .foregroundColor(isRecordingAudio ? .red : .accentColor)
                    }
                    .accessibilityLabel("Start Voice Input")
                }
                Spacer()
            }
            .frame(height: 20)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private func startAudioRecording() {
        guard !isRecordingAudio && !isProcessingAudio else { return }
        Task { @MainActor in
            do {
                try await audioRecorder.start()
                isRecordingAudio = true
                isRecordingPaused = false
                isRecordingPanelPresented = true
                recordingElapsed = 0
                waveformSamples = Array(repeating: 0.12, count: waveformSamples.count)
                audioActionError = nil
            } catch {
                audioActionError = error
                showingAudioErrorToast = true
            }
        }
    }

    private func togglePauseResume() {
        guard isRecordingAudio && !isProcessingAudio else { return }

        do {
            if isRecordingPaused {
                try audioRecorder.resume()
                isRecordingPaused = false
            } else {
                try audioRecorder.pause()
                isRecordingPaused = true
            }
        } catch {
            audioActionError = error
            showingAudioErrorToast = true
        }
    }

    private func updateRecordingMeters() {
        guard isRecordingAudio else { return }
        let elapsed = audioRecorder.currentTime()
        if !isRecordingPaused {
            let level = audioRecorder.currentPowerLevel()
            waveformSamples.append(max(0.05, CGFloat(level)))
            if waveformSamples.count > 24 {
                waveformSamples.removeFirst(waveformSamples.count - 24)
            }
        }
        recordingElapsed = elapsed
        if recordingElapsed >= maxRecordingDuration {
            stopAudioRecordingAndProcess()
        }
    }

    private func stopAudioRecordingAndProcess() {
        guard isRecordingAudio && !isProcessingAudio else { return }
        isRecordingAudio = false
        isRecordingPaused = false
        isRecordingPanelPresented = false
        isProcessingAudio = true
        let fileURL: URL
        do {
            fileURL = try audioRecorder.stop()
        } catch {
            audioActionError = error
            showingAudioErrorToast = true
            isProcessingAudio = false
            return
        }
        Task { @MainActor in
            defer { isProcessingAudio = false }
            do {
                // 1. Transcribe
                let transcript = try await SpeechTranscriber.transcribeAudioFile(at: fileURL)
                // 2. Refine with local guardrails
                var insight = transcript
                if !shouldSkipAudioTranscriptRefine(transcript) {
                    let prompt = makeAudioTranscriptRefinePrompt(transcript)
                    let refined = try await viewModel.service.getTextRefine(filter: nil, prompt: prompt)
                    if shouldUseRefinedAudioTranscript(original: transcript, refined: refined) {
                        insight = refined
                    }
                }
                // 3. Insert into editor
                if text.isEmpty {
                    text = insight
                } else {
                    text += "\n\n" + insight
                }
                        // 4. Upload audio as a resource and attach to memo
                        do {
                            let audioData = try Data(contentsOf: fileURL)
                            let resource = try await viewModel.uploadResource(filename: fileURL.lastPathComponent, data: audioData, type: "audio/m4a", memoRemoteId: nil)
                            viewModel.resourceList.append(resource)
                        } catch {
                            audioActionError = error
                            showingAudioErrorToast = true
                        }
            } catch {
                audioActionError = error
                showingAudioErrorToast = true
            }
        }
    }
    
    @ViewBuilder
    private func editor() -> some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading) {
                TextView(text: $text, selection: $selection, shouldChangeText: shouldChangeText(in:replacementText:))
                    .focused($focused)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("input.placeholder")
                                .foregroundColor(.secondary)
                                .padding(EdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5))
                        }
                    }
                    .padding(.horizontal)
                MemoInputResourceView(viewModel: viewModel, textContent: text)
            }
            .padding(.bottom, 40)
            toolbar()

            if isRecordingPanelPresented {
                GeometryReader { proxy in
                    VStack {
                        Spacer()
                        AudioRecordingPanel(
                            isPaused: isRecordingPaused,
                            duration: recordingElapsed,
                            maxDuration: maxRecordingDuration,
                            samples: waveformSamples,
                            onPauseResume: togglePauseResume,
                            onStop: stopAudioRecordingAndProcess
                        )
                        .frame(height: max(1, proxy.size.height / 3))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        
        .onAppear {
            if let memo = memo {
                text = memo.content
                viewModel.visibility = memo.visibility
            } else {
                if let prefill = appPath.newMemoPrefillContent {
                    text = prefill
                    draft = ""
                    appPath.newMemoPrefillContent = nil
                } else {
                    text = draft
                }
                viewModel.visibility = userState.currentUser?.defaultVisibility ?? .private
            }
            if let resourceList = memo?.resources {
                viewModel.resourceList = resourceList
            } else if !appPath.newMemoPrefillResources.isEmpty {
                viewModel.resourceList = appPath.newMemoPrefillResources
                appPath.newMemoPrefillResources = []
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                focused = true
            }
        }
        .task {
            do {
                try await memosViewModel.loadTags()
            } catch {
                print(error)
            }
        }
        .onDisappear {
            if memo == nil {
                draft = text
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if memo == nil {
                draft = text
            }
        }
        .onReceive(meterTimer) { _ in
            updateRecordingMeters()
        }
        .safeToast(isPresenting: $showingErrorToast, message: submitError?.localizedDescription, systemImage: "xmark.circle")
        .safeToast(isPresenting: $showingAudioErrorToast, message: audioActionError?.localizedDescription, systemImage: "xmark.circle")
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(memo == nil ? NSLocalizedString("input.compose", comment: "Compose") : NSLocalizedString("input.edit", comment: "Edit"))
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Text("input.close")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        try await saveMemo()
                    }
                } label: {
                    Label("input.save", systemImage: "paperplane")
                }
                .disabled((text.isEmpty && viewModel.resourceList.isEmpty) || viewModel.imageUploading || viewModel.saving || isProcessingAudio)
            }
        }
        .overlay(alignment: .center) {
            if isProcessingAudio {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                    Text("Processing audio…")
                        .font(.caption)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
                .shadow(radius: 6)
            }
        }
        .fullScreenCover(isPresented: $showingImagePicker, content: {
            ImagePicker { image in
                Task {
                    try await upload(images: [image])
                }
            }
            .edgesIgnoringSafeArea(.all)
        })
        .interactiveDismissDisabled()
    }

    var body: some View {
        NavigationStack {
            editor()
                .photosPicker(isPresented: $showingPhotoPicker, selection: $viewModel.photos)
                .onChange(of: viewModel.photos) { _, newValue in
                    Task {
                        if !newValue.isEmpty {
                            try await upload(images: newValue)
                            viewModel.photos = []
                        }
                    }
                }
        }
    }
    
    private func upload(images: [PhotosPickerItem]) async throws {
        do {
            let remainingSlots = remainingImageSlots
            guard remainingSlots > 0 else {
                showImageLimitToast(addedCount: nil)
                return
            }

            let acceptedItems = Array(images.prefix(remainingSlots))
            viewModel.imageUploading = true
            for item in acceptedItems {
                let imageData = try await item.loadTransferable(type: Data.self)
                if let imageData = imageData, let image = UIImage(data: imageData) {
                    try await viewModel.upload(image: image)
                }
            }
            if images.count > acceptedItems.count {
                showImageLimitToast(addedCount: acceptedItems.count)
            } else {
                submitError = nil
            }
        } catch {
            submitError = error
            showingErrorToast = true
        }
        viewModel.imageUploading = false
    }
    
    private func upload(images: [UIImage]) async throws {
        do {
            let remainingSlots = remainingImageSlots
            guard remainingSlots > 0 else {
                showImageLimitToast(addedCount: nil)
                return
            }

            let acceptedImages = Array(images.prefix(remainingSlots))
            viewModel.imageUploading = true
            for image in acceptedImages {
                try await viewModel.upload(image: image)
            }
            if images.count > acceptedImages.count {
                showImageLimitToast(addedCount: acceptedImages.count)
            } else {
                submitError = nil
            }
        } catch {
            submitError = error
            showingErrorToast = true
        }
        viewModel.imageUploading = false
    }
    
    private func saveMemo() async throws {
        viewModel.saving = true
        let tags = viewModel.extractCustomTags(from: text)
        
        do {
            if let memo = memo, let remoteId = memo.remoteId {
                try await memosViewModel.editMemo(remoteId: remoteId, content: text, visibility: viewModel.visibility, resources: viewModel.resourceList, tags: tags)
            } else {
                try await memosViewModel.createMemo(content: text, visibility: viewModel.visibility, resources: viewModel.resourceList, tags: tags)
                draft = ""
            }
            text = ""
            dismiss()
            submitError = nil
        } catch {
            submitError = error
            showingErrorToast = true
        }
        viewModel.saving = false
    }
    
    private func insert(tag: Tag?) {
        let tagText = "#\(tag?.name ?? "") "
        guard let selection = selection else {
            text += tagText
            return
        }
        
        text = text.replacingCharacters(in: selection, with: tagText)
        let index = text.index(selection.lowerBound, offsetBy: tagText.count)
        self.selection = index..<text.index(selection.lowerBound, offsetBy: tagText.count)
    }
    
    private func toggleTodoItem() {
        let currentText = text
        guard let currentSelection = selection else { return }
        
        let contentBefore = currentText[currentText.startIndex..<currentSelection.lowerBound]
        let lastLineBreak = contentBefore.lastIndex(of: "\n")
        let nextLineBreak = currentText[currentSelection.lowerBound...].firstIndex(of: "\n") ?? currentText.endIndex
        let currentLine: Substring
        if let lastLineBreak = lastLineBreak {
            currentLine = currentText[currentText.index(after: lastLineBreak)..<nextLineBreak]
        } else {
            currentLine = currentText[currentText.startIndex..<nextLineBreak]
        }
    
        let contentBeforeCurrentLine = currentText[currentText.startIndex..<currentLine.startIndex]
        let contentAfterCurrentLine = currentText[nextLineBreak..<currentText.endIndex]
        
        for prefixStr in listItemSymbolList {
            if (!currentLine.hasPrefix(prefixStr)) {
                continue
            }
            
            if prefixStr == "- [ ] " {
                text = contentBeforeCurrentLine + "- [x] " + currentLine[currentLine.index(currentLine.startIndex, offsetBy: prefixStr.count)..<currentLine.endIndex] + contentAfterCurrentLine
                return
            }
            
            let offset = "- [ ] ".count - prefixStr.count
            text = contentBeforeCurrentLine + "- [ ] " + currentLine[currentLine.index(currentLine.startIndex, offsetBy: prefixStr.count)..<currentLine.endIndex] + contentAfterCurrentLine
            selection = text.index(currentSelection.lowerBound, offsetBy: offset)..<text.index(currentSelection.upperBound, offsetBy: offset)
            return
        }
        
        text = contentBeforeCurrentLine + "- [ ] " + currentLine + contentAfterCurrentLine
        selection = text.index(currentSelection.lowerBound, offsetBy: "- [ ] ".count)..<text.index(currentSelection.upperBound, offsetBy: "- [ ] ".count)
    }
    
    private func shouldChangeText(in range: Range<String.Index>, replacementText text: String) -> Bool {
        if text != "\n" || range.upperBound != range.lowerBound {
            return true
        }
        
        let currentText = self.text
        let contentBefore = currentText[currentText.startIndex..<range.lowerBound]
        let lastLineBreak = contentBefore.lastIndex(of: "\n")
        let nextLineBreak = currentText[range.lowerBound...].firstIndex(of: "\n") ?? currentText.endIndex
        let currentLine: Substring
        if let lastLineBreak = lastLineBreak {
            currentLine = currentText[currentText.index(after: lastLineBreak)..<nextLineBreak]
        } else {
            currentLine = currentText[currentText.startIndex..<nextLineBreak]
        }
        
        for prefixStr in listItemSymbolList {
            if (!currentLine.hasPrefix(prefixStr)) {
                continue
            }
            
            if currentLine.count <= prefixStr.count || currentText.index(currentLine.startIndex, offsetBy: prefixStr.count) >= range.lowerBound {
                break
            }
            
            self.text = currentText[currentText.startIndex..<range.lowerBound] + "\n" + prefixStr + currentText[range.upperBound..<currentText.endIndex]
            selection = self.text.index(range.lowerBound, offsetBy: prefixStr.count + 1)..<self.text.index(range.upperBound, offsetBy: prefixStr.count + 1)
            return false
        }

        return true
    }
}
