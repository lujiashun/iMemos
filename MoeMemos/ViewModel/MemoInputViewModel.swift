//
//  MemoInputViewModel.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/11/1.
//

import Foundation
import UIKit
import PhotosUI
import SwiftUI
import Markdown
import Account
import Models
import Factory

@MainActor
@Observable class MemoInputViewModel: ResourceManager {
    @ObservationIgnored
    @Injected(\.accountManager) private var accountManager
    @ObservationIgnored
    var service: RemoteService { get throws { try accountManager.mustCurrentService } }
    
    var resourceList = [Resource]()
    var imageUploading = false
    var saving = false
    var visibility: MemoVisibility = .private
    var photos: [PhotosPickerItem] = []

    func upload(image: UIImage) async throws {
        // 智能压缩图片
        let compressionResult = await ImageCompressor.compressAsync(image: image)
        
        let data: Data
        switch compressionResult {
        case .success(let compressedData, let quality, let originalSize, let compressedSize):
            data = compressedData
#if DEBUG
            print("[ImageUpload] 图片已压缩: \(ByteCountFormatter.string(fromByteCount: Int64(originalSize), countStyle: .file)) -> \(ByteCountFormatter.string(fromByteCount: Int64(compressedSize), countStyle: .file)), 质量: \(Int(quality * 100))%")
#endif
        case .noNeed(let originalData, let originalSize):
            data = originalData
#if DEBUG
            print("[ImageUpload] 图片无需压缩: \(ByteCountFormatter.string(fromByteCount: Int64(originalSize), countStyle: .file))")
#endif
        case .failure(let error):
            throw error
        }
        
        let response = try await uploadResource(filename: "\(UUID().uuidString).jpg", data: data, type: "image/jpeg", memoRemoteId: nil)
        resourceList.append(response)
    }

    func uploadResource(filename: String, data: Data, type: String, memoRemoteId: String?) async throws -> Resource {
        let maxAttempts = 4
        var attempt = 0
        var baseDelay: TimeInterval = 1

        while true {
            attempt += 1
            do {
                let response = try await service.createResource(filename: filename, data: data, type: type, memoRemoteId: memoRemoteId)
                return response
            } catch {
                // Retry on transient networking errors
                if let urlErr = error as? URLError {
                    switch urlErr.code {
                    case .networkConnectionLost, .timedOut, .cannotFindHost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed:
                        if attempt < maxAttempts {
                            let jitter = Double.random(in: 0.5...1.5)
                            try await Task.sleep(nanoseconds: UInt64(baseDelay * jitter * 1_000_000_000))
                            baseDelay *= 2
                            continue
                        }
                    default:
                        break
                    }
                }
                throw error
            }
        }
    }
    
    func deleteResource(remoteId: String) async throws {
        _ = try await service.deleteResource(remoteId: remoteId)
        resourceList = resourceList.filter({ resource in
            resource.remoteId != remoteId
        })
    }
    
    func extractCustomTags(from markdownText: String) -> [String] {
        let document = Document(parsing: markdownText)
        var tagVisitor = TagVisitor()
        document.accept(&tagVisitor)
        return tagVisitor.tags
    }
}
