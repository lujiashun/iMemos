import Foundation

#if canImport(Speech)
@preconcurrency import Speech
#endif

enum SpeechTranscriber {
#if canImport(Speech)
    private final class LockedOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var didRun = false

        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !didRun else { return }
            didRun = true
            body()
        }
    }

    private final class SpeechTaskBox: @unchecked Sendable {
        let task: SFSpeechRecognitionTask
        init(_ task: SFSpeechRecognitionTask) {
            self.task = task
        }
    }
#endif

    enum TranscriptionError: LocalizedError {
        case unsupportedPlatform
        case speechPermissionDenied
        case recognizerUnavailable
        case noResult
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .unsupportedPlatform:
                return "当前平台不支持语音识别。"
            case .speechPermissionDenied:
                return "未获得语音识别权限，无法转写。"
            case .recognizerUnavailable:
                return "当前设备/语言不可用语音识别。"
            case .noResult:
                return "未识别到有效文字。"
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }

    static func transcribeAudioFile(at url: URL, locale: Locale = .current) async throws -> String {
#if canImport(Speech)
        let allowed = await requestSpeechPermission()
        guard allowed else { throw TranscriptionError.speechPermissionDenied }

        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            let once = LockedOnce()

            let taskBox = SpeechTaskBox(recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    once.run {
                        continuation.resume(throwing: TranscriptionError.underlying(error))
                    }
                    return
                }

                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    once.run {
                        if text.isEmpty {
                            continuation.resume(throwing: TranscriptionError.noResult)
                        } else {
                            continuation.resume(returning: text)
                        }
                    }
                }
            })

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 30) {
                once.run {
                    taskBox.task.cancel()
                    continuation.resume(throwing: TranscriptionError.noResult)
                }
            }
        }

#else
        throw TranscriptionError.unsupportedPlatform
#endif
    }

    private static func requestSpeechPermission() async -> Bool {
#if canImport(Speech)
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
#else
        false
#endif
    }
}
