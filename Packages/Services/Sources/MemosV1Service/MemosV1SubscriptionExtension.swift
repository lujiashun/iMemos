import Foundation
import ServiceUtils

extension MemosV1Service {
    public func authenticatedDataRequest(url: URL, method: String = "GET", body: Data? = nil) async throws -> Data {
        try await signInIfNeeded()
        
        let token = accessToken
        let setCookieHeaderValue = await grpcSetCookieMiddleware.setCookieHeaderValue
        let cookie = setCookieHeaderValue.map { value in
            value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? value
        }
        
        return try await ServiceUtils.downloadData(
            urlSession: urlSession,
            url: url,
            middleware: { request in
                var request = request
                request.httpMethod = method
                if let body = body {
                    request.httpBody = body
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                if request.url?.host == self.hostURL.host {
                    if let token, !token.isEmpty {
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    if let cookie, !cookie.isEmpty {
                        request.setValue(cookie, forHTTPHeaderField: "Cookie")
                    }
                }
                return request
            }
        )
    }
    
    public var subscriptionHostURL: URL {
        hostURL
    }
}
