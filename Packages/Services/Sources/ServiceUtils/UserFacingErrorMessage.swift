import Foundation

public func userFacingErrorMessage(_ error: Error) -> String {
    let nsError = error as NSError

    if nsError.domain == NSURLErrorDomain {
        switch nsError.code {
        case NSURLErrorCannotFindHost:
            return "无法解析服务器域名。请检查域名是否正确、网络是否可用，或尝试更换 DNS 后重试。"
        case NSURLErrorCannotConnectToHost:
            return "无法连接到服务器。请检查服务器是否在线、端口是否开放、以及是否被防火墙/代理拦截。"
        case NSURLErrorTimedOut:
            return "连接服务器超时。请检查网络状况，或稍后重试。"
        case NSURLErrorSecureConnectionFailed:
            return "无法建立安全连接（TLS）。请检查服务器 HTTPS 配置后重试。"
        case NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            #if DEBUG
            return "服务器证书无效或不受信任。若你使用自签证书/mkcert，请在系统钥匙串中安装并信任根证书；或在设置里开启“允许不安全证书（仅调试）”。"
            #else
            return "服务器证书无效或不受信任。若你使用自签证书/mkcert，请在系统钥匙串中安装并信任根证书，或换用受信任证书。"
            #endif
        default:
            break
        }
    }

    if let urlError = error as? URLError {
        switch urlError.code {
        case .badServerResponse:
            return "服务器返回了异常响应。请稍后重试，或检查服务器日志。"
        case .notConnectedToInternet:
            return "当前网络不可用。请连接网络后重试。"
        default:
            break
        }
    }

    return error.localizedDescription
}
