//
//  AudioMemoRecorder.swift
//  MoeMemos
//
//  Created by Copilot on 2026/2/12.
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
final class AudioMemoRecorder {
    enum RecorderError: LocalizedError {
        case unsupportedPlatform
        case microphonePermissionDenied
        case recorderNotPrepared
        case failedToStartRecording

        var errorDescription: String? {
            switch self {
            case .unsupportedPlatform:
                return "当前平台不支持录音。"
            case .microphonePermissionDenied:
                return "未获得麦克风权限，无法录音。"
            case .recorderNotPrepared:
                return "录音器未就绪。"
            case .failedToStartRecording:
                return "开始录音失败。"
            }
        }
    }

#if os(iOS) || targetEnvironment(macCatalyst)
    private var recorder: AVAudioRecorder?
#endif
    private(set) var currentFileURL: URL?

    var isRecording: Bool {
#if os(iOS) || targetEnvironment(macCatalyst)
        recorder?.isRecording == true
#else
        false
#endif
    }

    func start() async throws {
#if os(iOS) || targetEnvironment(macCatalyst)
        let allowed = await requestMicrophonePermission()
        guard allowed else { throw RecorderError.microphonePermissionDenied }

        try configureAudioSession()
        let fileURL = try makeRecordingFileURL()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        self.recorder = recorder
        self.currentFileURL = fileURL

        guard recorder.record() else {
            self.recorder = nil
            self.currentFileURL = nil
            throw RecorderError.failedToStartRecording
        }
#else
        throw RecorderError.unsupportedPlatform
#endif
    }

    func stop() throws -> URL {
#if os(iOS) || targetEnvironment(macCatalyst)
        guard let recorder, let url = currentFileURL else {
            throw RecorderError.recorderNotPrepared
        }

        recorder.stop()
        self.recorder = nil
        self.currentFileURL = nil

        return url
#else
        throw RecorderError.unsupportedPlatform
#endif
    }

#if os(iOS) || targetEnvironment(macCatalyst)
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission(completionHandler: { allowed in
                    continuation.resume(returning: allowed)
                })
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: [])
    }
#endif

    private func makeRecordingFileURL() throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "memo-audio-\(formatter.string(from: .now)).m4a"

        return dir.appendingPathComponent(name)
    }
}
