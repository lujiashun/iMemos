//
//  AudioRecordingPanel.swift
//  MoeMemos
//
//  Created by Copilot on 2026/2/25.
//

import SwiftUI

struct AudioRecordingPanel: View {
    let isPaused: Bool
    let duration: TimeInterval
    let maxDuration: TimeInterval
    let samples: [CGFloat]
    let onPauseResume: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(isPaused ? "录音已暂停" : "录音中")
                    .font(.headline)
                Spacer()
                Text("\(format(duration))/\(format(maxDuration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            AudioWaveformView(samples: samples)
                .frame(height: 48)

            HStack(spacing: 32) {
                Button(action: onPauseResume) {
                    VStack(spacing: 6) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text(isPaused ? "继续" : "暂停")
                            .font(.caption)
                    }
                    .foregroundStyle(.primary)
                }

                Button(action: onStop) {
                    VStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.red)
                        Text("停止")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 8)
    }

    private func format(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct AudioWaveformView: View {
    let samples: [CGFloat]

    var body: some View {
        GeometryReader { proxy in
            let height = max(1, proxy.size.height)
            HStack(alignment: .center, spacing: 4) {
                ForEach(samples.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: max(2, height * samples[index]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

#Preview {
    AudioRecordingPanel(
        isPaused: false,
        duration: 21,
        maxDuration: 180,
        samples: Array(repeating: 0.4, count: 24),
        onPauseResume: {},
        onStop: {}
    )
    .padding()
}
