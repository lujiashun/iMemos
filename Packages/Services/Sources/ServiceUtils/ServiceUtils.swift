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

            let (data, response) = try await urlSession.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw MoeMemosError.unknown
            }
            if response.statusCode == 429 {
                if attempt >= maxAttempts { throw MoeMemosError.invalidStatusCode(response.statusCode, url.absoluteString) }
                let retryAfter = parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After")) ?? baseDelay
                let jitter = Double.random(in: 0.5...1.5)
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
                try await Task.sleep(nanoseconds: UInt64(baseDelay * jitter * 1_000_000_000))
                baseDelay *= 2
                continue
            }
            throw error
        }
    }
}

public func download(urlSession: URLSession, url: URL, mimeType: String? = nil, middleware: (@Sendable (URLRequest) async throws -> URLRequest)? = nil) async throws -> URL {
    let hash = SHA256.hash(data: url.absoluteString.data(using: .utf8)!)
    let hex = hash.map { String(format: "%02X", $0) }[0...10].joined()

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

            let (tmpURL, response) = try await urlSession.download(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw MoeMemosError.unknown
            }
            if response.statusCode == 429 {
                if attempt >= maxAttempts { throw MoeMemosError.invalidStatusCode(response.statusCode, url.absoluteString) }
                let retryAfter = parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After")) ?? baseDelay
                let jitter = Double.random(in: 0.5...1.5)
                try await Task.sleep(nanoseconds: UInt64(retryAfter * jitter * 1_000_000_000))
                baseDelay *= 2
                continue
            }
            if response.statusCode < 200 || response.statusCode >= 300 {
                throw MoeMemosError.invalidStatusCode(response.statusCode, url.absoluteString)
            }

            // Move temp file to destination, handle existing file by replacing
            do {
                if FileManager.default.fileExists(atPath: downloadDestination.path) {
                    try FileManager.default.removeItem(at: downloadDestination)
                }
                try FileManager.default.moveItem(at: tmpURL, to: downloadDestination)
            } catch {
                // If move failed and it's transient, retry a few times
                if isTransientError(error) && attempt < maxAttempts {
                    let jitter = Double.random(in: 0.5...1.5)
                    try await Task.sleep(nanoseconds: UInt64(baseDelay * jitter * 1_000_000_000))
                    baseDelay *= 2
                    continue
                }
                throw error
            }

            return downloadDestination
        } catch {
            if isTransientError(error) && attempt < maxAttempts {
                let jitter = Double.random(in: 0.5...1.5)
                try await Task.sleep(nanoseconds: UInt64(baseDelay * jitter * 1_000_000_000))
                baseDelay *= 2
                continue
            }
            throw error
        }
    }
}
