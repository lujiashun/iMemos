import Foundation

#if DEBUG
/// A URLSession delegate that bypasses TLS certificate validation.
///
/// - Important: DEBUG-only. Use for local/self-signed certs during development.
/// - Safety: Only applies to hosts in `allowedHosts`.
public final class InsecureTLSURLSessionDelegate: NSObject, URLSessionDelegate {
    private let allowedHosts: Set<String>

    public init(allowedHosts: [String]) {
        self.allowedHosts = Set(allowedHosts)
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        guard allowedHosts.contains(host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
#endif
