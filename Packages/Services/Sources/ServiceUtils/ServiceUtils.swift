//
//  File.swift
//  
//
//  Created by Mudkip on 2024/6/9.
//

import Foundation
import DataURI
import Models
import CryptoKit
import UniformTypeIdentifiers

#if DEBUG
private func debugDownloadLog(_ message: String) {
    print("[ServiceUtils][Download] \(message)")
}
#endif

private func parseRetryAfter(_ header: String?) -> TimeInterval? {
    guard let header = header?.trimmingCharacters(in: .whitespacesAndNewlines), !header.isEmpty else { return nil }
    // If it's an integer, interpret as seconds
    if let secs = Int(header) { return TimeInterval(secs) }
    // Try HTTP-date parsing
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
    if let date = formatter.date(from: header) {
        return max(0, date.timeIntervalSinceNow)
    }
    return nil
}

private func isRetriableStatusCode(_ statusCode: Int) -> Bool {
    statusCode == 429 || (500...599).contains(statusCode)
}

private func isTransientError(_ error: Error) -> Bool {
    if let urlErr = error as? URLError {
        switch urlErr.code {
        case .networkConnectionLost, .timedOut, .cannotFindHost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
    return false
}

private func resumeDataFromDownloadError(_ error: Error) -> Data? {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else { return nil }
    return nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
}

private func downloadTask(
    urlSession: URLSession,
    request: URLRequest,
    resumeData: Data?
) async throws -> (URL, URLResponse) {
    try await withCheckedThrowingContinuation { continuation in
        let task: URLSessionDownloadTask
        if let resumeData, !resumeData.isEmpty {
            task = urlSession.downloadTask(withResumeData: resumeData) { tmpURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tmpURL, let response else {
                    continuation.resume(throwing: MoeMemosError.unknown)
                    return
                }
                continuation.resume(returning: (tmpURL, response))
            }
        } else {
            task = urlSession.downloadTask(with: request) { tmpURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tmpURL, let response else {
                    continuation.resume(throwing: MoeMemosError.unknown)
                    return
                }
                continuation.resume(returning: (tmpURL, response))
            }
        }

        task.resume()
    }
}

public func downloadData(urlSession: URLSession, url: URL, middleware: (@Sendable (URLRequest) async throws -> URLRequest)? = nil) async throws -> Data {
    if url.scheme == "data" {
        let (data, _) = try url.absoluteString.dataURIDecoded()
        return data.convertToData()
    }

    let maxAttempts = 4
    var attempt = 0
    var baseDelay: TimeInterval = 1

    while true {
        attempt += 1
        do {
            var request = URLRequest(url: url)
            if let middleware = middleware {
                request = try await middleware(request)
            }
#if DEBUG
            debugDownloadLog("downloadData start attempt=\(attempt)/\(maxAttempts) url=\(url.absoluteString)")
#endif

            let (data, response) = try await urlSession.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw MoeMemosError.unknown
            }
#if DEBUG
            debugDownloadLog("downloadData response attempt=\(attempt) status=\(response.statusCode) bytes=\(data.count) url=\(url.absoluteString)")
#endif
            if isRetriableStatusCode(response.statusCode) {
                if attempt >= maxAttempts { throw MoeMemosError.invalidStatusCode(response.statusCode, url.absoluteString) }
                let retryAfter = response.statusCode == 429 ? (parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After")) ?? baseDelay) : baseDelay
                let jitter = Double.random(in: 0.5...1.5)
#if DEBUG
                debugDownloadLog("downloadData retry attempt=\(attempt) status=\(response.statusCode) delay=\(retryAfter * jitter)s url=\(url.absoluteString)")
#endif
                try await Task.sleep(nanoseconds: UInt64(retryAfter * jitter * 1_000_000_000))
                baseDelay *= 2
                continue
            }
            if response.statusCode < 200 || response.statusCode >= 300 {
                throw MoeMemosError.invalidStatusCode(response.statusCode, url.absoluteString)
            }
            return data
        } catch {
            if isTransientError(error) && attempt < maxAttempts {
                let jitter = Double.random(in: 0.5...1.5)
#if DEBUG
                let nsError = error as NSError
                debugDownloadLog("downloadData transientError attempt=\(attempt) domain=\(nsError.domain) code=\(nsError.code) delay=\(baseDelay * jitter)s url=\(url.absoluteString)")
#endif
                try await Task.sleep(nanoseconds: UInt64(baseDelay * jitter * 1_000_000_000))
                baseDelay *= 2
                continue
            }
#if DEBUG
            let nsError = error as NSError
            debugDownloadLog("downloadData failed attempt=\(attempt) domain=\(nsError.domain) code=\(nsError.code) url=\(url.absoluteString)")
#endif
            throw error
        }
    }
}

// 文件下载锁，防止并发下载同一文件
private actor DownloadLock {
    static let shared = DownloadLock()
    private var downloadingURLs: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    
    func acquireLock(for url: String) async {
        if downloadingURLs.contains(url) {
            await withCheckedContinuation { continuation in
                waiters[url, default: []].append(continuation)
            }
        } else {
            downloadingURLs.insert(url)
        }
    }
    
    func releaseLock(for url: String) {
        downloadingURLs.remove(url)
        if let waitersForURL = waiters.removeValue(forKey: url) {
            for waiter in waitersForURL {
                waiter.resume()
            }
        }
    }
}

public func download(urlSession: URLSession, url: URL, mimeType: String? = nil, middleware: (@Sendable (URLRequest) async throws -> URLRequest)? = nil) async throws -> URL {
    let hash = SHA256.hash(data: url.absoluteString.data(using: .utf8)!)
    let hex = hash.map { String(format: "%02X", $0) }.joined()

    var pathExtension = url.pathExtension
    if pathExtension.isEmpty, let mimeType = mimeType, let utType = UTType(mimeType: mimeType), let ext = utType.preferredFilenameExtension {
        pathExtension = ext
    }

    let baseCachesURL: URL
    if !AppInfo.groupContainerIdentifier.isEmpty, let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppInfo.groupContainerIdentifier) {
        baseCachesURL = containerURL.appendingPathComponent("Library/Caches")
    } else if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
        baseCachesURL = caches
    } else {
        throw MoeMemosError.unknown
    }

    let downloadDestination = baseCachesURL.appendingPathComponent(hex).appendingPathExtension(pathExtension)

    try FileManager.default.createDirectory(at: downloadDestination.deletingLastPathComponent(), withIntermediateDirectories: true)

    do {
        if try downloadDestination.checkResourceIsReachable() {
            return downloadDestination
        }
    } catch {}
    
    // 获取下载锁，防止并发下载同一文件
    await DownloadLock.shared.acquireLock(for: url.absoluteString)
    defer { Task { await DownloadLock.shared.releaseLock(for: url.absoluteString) } }
    
    // 再次检查文件是否已存在（另一个任务可能刚刚下载完成）
    do {
        if try downloadDestination.checkResourceIsReachable() {
            return downloadDestination
        }
    } catch {}
    
    // 小文件阈值：5MB，小于此值使用 dataTask，大于此值使用 downloadTask
    let smallFileThreshold: Int64 = 5 * 1024 * 1024
    let maxAttempts = 4
    var attempt = 0
    var baseDelay: TimeInterval = 1
    var pendingResumeData: Data?
    var useDataTask = true // 默认使用 dataTask，更安全

    while true {
        attempt += 1
        do {
            var request = URLRequest(url: url)
            if let middleware = middleware {
                request = try await middleware(request)
            }
#if DEBUG
            debugDownloadLog("download start attempt=\(attempt)/\(maxAttempts) useDataTask=\(useDataTask) url=\(url.absoluteString) cachedPath=\(downloadDestination.path)")
#endif

            if useDataTask {
                // 使用 dataTask：适合小文件，避免临时文件被清理的问题
                let (data, response) = try await urlSession.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    throw MoeMemosError.unknown
                }
#if DEBUG
                debugDownloadLog("download dataTask response attempt=\(attempt) status=\(response.statusCode) bytes=\(data.count) url=\(url.absoluteString)")
#endif
                if isRetriableStatusCode(response.statusCode) {
                    if attempt >= maxAttempts { throw MoeMemosError.invalidStatusCode(response.statusCode, url.absoluteString) }
                    let retryAfter = response.statusCode == 429 ? (parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After")) ?? baseDelay) : baseDelay
                    let jitter = Double.random(in: 0.5...1.5)
                    try await Task.sleep(nanoseconds: UInt64(retryAfter * jitter * 1_000_000_000))
                    baseDelay *= 2
                    continue
                }
                if response.statusCode < 200 || response.statusCode >= 300 {
                    throw MoeMemosError.invalidStatusCode(response.statusCode, url.absoluteString)
                }

                // 检查文件大小，如果超过阈值，下次使用 downloadTask
                if Int64(data.count) > smallFileThreshold {
#if DEBUG
                    debugDownloadLog("download file too large for dataTask, will use downloadTask next time: \(data.count) bytes")
#endif
                }

                // 直接将数据写入目标位置
                do {
                    if FileManager.default.fileExists(atPath: downloadDestination.path) {
                        try FileManager.default.removeItem(at: downloadDestination)
                    }
                    try data.write(to: downloadDestination)
#if DEBUG
                    debugDownloadLog("download dataTask write success attempt=\(attempt) destination=\(downloadDestination.path) bytes=\(data.count)")
#endif
                } catch {
#if DEBUG
                    let nsError = error as NSError
                    debugDownloadLog("download dataTask write failed attempt=\(attempt) domain=\(nsError.domain) code=\(nsError.code)")
#endif
                    throw error
                }
            } else {
                // 使用 downloadTask：适合大文件，支持断点续传
                let (tmpURL, response) = try await downloadTask(
                    urlSession: urlSession,
                    request: request,
                    resumeData: pendingResumeData
                )
                guard let response = response as? HTTPURLResponse else {
                    throw MoeMemosError.unknown
                }
#if DEBUG
                debugDownloadLog("download downloadTask response attempt=\(attempt) status=\(response.statusCode) url=\(url.absoluteString)")
#endif
                if isRetriableStatusCode(response.statusCode) {
                    if attempt >= maxAttempts { throw MoeMemosError.invalidStatusCode(response.statusCode, url.absoluteString) }
                    let retryAfter = response.statusCode == 429 ? (parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After")) ?? baseDelay) : baseDelay
                    let jitter = Double.random(in: 0.5...1.5)
                    try await Task.sleep(nanoseconds: UInt64(retryAfter * jitter * 1_000_000_000))
                    baseDelay *= 2
                    continue
                }
                if response.statusCode < 200 || response.statusCode >= 300 {
                    throw MoeMemosError.invalidStatusCode(response.statusCode, url.absoluteString)
                }

                // 立即复制临时文件，避免被系统清理
                do {
                    guard FileManager.default.fileExists(atPath: tmpURL.path) else {
                        throw MoeMemosError.unknown
                    }
                    if FileManager.default.fileExists(atPath: downloadDestination.path) {
                        try FileManager.default.removeItem(at: downloadDestination)
                    }
                    try FileManager.default.copyItem(at: tmpURL, to: downloadDestination)
#if DEBUG
                    debugDownloadLog("download downloadTask copy success attempt=\(attempt) destination=\(downloadDestination.path)")
#endif
                } catch {
                    let nsError = error as NSError
                    let isFileNotFound = nsError.domain == NSCocoaErrorDomain && (nsError.code == 4 || nsError.code == 260)
                    if isFileNotFound && attempt < maxAttempts {
#if DEBUG
                        debugDownloadLog("download downloadTask temp file missing, retrying attempt=\(attempt)")
#endif
                        try await Task.sleep(nanoseconds: UInt64(baseDelay * 1_000_000_000))
                        baseDelay *= 2
                        continue
                    }
                    throw error
                }
            }

            return downloadDestination
        } catch {
            // 处理断点续传
            if !useDataTask, let resumeData = resumeDataFromDownloadError(error), isTransientError(error), attempt < maxAttempts {
                pendingResumeData = resumeData
                let jitter = Double.random(in: 0.5...1.5)
#if DEBUG
                let nsError = error as NSError
                debugDownloadLog("download resume retry attempt=\(attempt) domain=\(nsError.domain) code=\(nsError.code) resumeBytes=\(resumeData.count)")
#endif
                try await Task.sleep(nanoseconds: UInt64(baseDelay * jitter * 1_000_000_000))
                baseDelay *= 2
                continue
            }

            if isTransientError(error) && attempt < maxAttempts {
                pendingResumeData = nil
                let jitter = Double.random(in: 0.5...1.5)
#if DEBUG
                let nsError = error as NSError
                debugDownloadLog("download transientError attempt=\(attempt) domain=\(nsError.domain) code=\(nsError.code) delay=\(baseDelay * jitter)s")
#endif
                try await Task.sleep(nanoseconds: UInt64(baseDelay * jitter * 1_000_000_000))
                baseDelay *= 2
                continue
            }
#if DEBUG
            let nsError = error as NSError
            debugDownloadLog("download failed attempt=\(attempt) domain=\(nsError.domain) code=\(nsError.code) url=\(url.absoluteString)")
#endif
            throw error
        }
    }
}
