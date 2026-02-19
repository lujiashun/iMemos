//
//  MemosV1Service.swift
//
//
//  Created by Mudkip on 2024/6/9.
//
//
//  MemosV1Service.swift
//
//
//  Created by Mudkip on 2024/6/9.
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import HTTPTypes
import Models
import ServiceUtils

@MainActor
public final class MemosV1Service: RemoteService {
    private let hostURL: URL
    private let urlSession: URLSession
    private let urlSessionDelegate: (any URLSessionDelegate)?
    private var client: Client
    private let username: String?
    private let password: String?
    private let userId: String?
    private let grpcSetCookieMiddleware = GRPCSetCookieMiddleware()
    private var accessToken: String?

    private func cookieHeaderValue(from setCookieHeaderValue: String) -> String {
        // Request header expects: "name=value" (not the full Set-Cookie attributes).
        return setCookieHeaderValue.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? setCookieHeaderValue
    }
    
    public nonisolated init(hostURL: URL, username: String?, password: String?, userId: String?, allowInsecureTLS: Bool = false) {
        self.hostURL = hostURL
        self.username = username
        self.password = password
        self.userId = userId

#if DEBUG
        let wantsInsecureTLS = allowInsecureTLS || UserDefaults.standard.bool(forKey: "allowInsecureTLS")
        if wantsInsecureTLS, let host = hostURL.host {
            let delegate = InsecureTLSURLSessionDelegate(allowedHosts: [host])
            urlSessionDelegate = delegate
            urlSession = URLSession(configuration: URLSessionConfiguration.default, delegate: delegate, delegateQueue: nil)
            print("[MemosV1Service] insecure TLS enabled for host:\(host)")
        } else {
            urlSessionDelegate = nil
            urlSession = URLSession(configuration: URLSessionConfiguration.default)
        }
#else
        urlSessionDelegate = nil
        urlSession = URLSession(configuration: URLSessionConfiguration.default)
#endif

        client = Client(
            serverURL: hostURL,
            transport: URLSessionTransport(configuration: .init(session: urlSession)),
            middlewares: [
                UsernamePasswordAuthenticationMiddleware(username: username, password: password),
                grpcSetCookieMiddleware
            ]
        )
    }

    /// 注册新用户
    public func signUp(username: String, password: String, email: String?) async throws {
        let signupURL = hostURL.appending(path: "api").appending(path: "v1").appending(path: "users")
        var req = URLRequest(url: signupURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "username": username,
            "password": password
        ]
        if let email = email, !email.isEmpty {
            payload["email"] = email
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        print("[MemosV1Service] signUp request url:\(signupURL.absoluteString) method:\(req.httpMethod ?? "") headers:\(req.allHTTPHeaderFields ?? [:])")
        if let body = req.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            print("[MemosV1Service] signUp request body:\(bodyString)")
        }

        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            print("[MemosV1Service] signUp HTTP \(http.statusCode) body:\(bodyString)")
            throw URLError(.badServerResponse)
        }
        print("[MemosV1Service] signUp response body:\(String(data: data, encoding: .utf8) ?? "")")
        print("[MemosV1Service] signUp success for username:\(username)")
    }

    private func signInIfNeeded() async throws {
        if accessToken != nil { return }
        guard let username = username, let password = password, !username.isEmpty, !password.isEmpty else { return }
        do {
            print("[MemosV1Service] signing in to \(hostURL) username:\(username)")
            let signinURL = hostURL.appending(path: "api").appending(path: "v1").appending(path: "auth").appending(path: "signin")
            var req = URLRequest(url: signinURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = ["passwordCredentials": ["username": username, "password": password]]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            print("[MemosV1Service] signIn request url:\(signinURL.absoluteString) method:\(req.httpMethod ?? "") headers:\(req.allHTTPHeaderFields ?? [:])")
            if let body = req.httpBody, let bodyString = String(data: body, encoding: .utf8) {
                print("[MemosV1Service] signIn request body:\(bodyString)")
            }
            let (data, response) = try await urlSession.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let bodyString = String(data: data, encoding: .utf8) ?? ""
                print("[MemosV1Service] signIn HTTP \(http.statusCode) body:\(bodyString)")
                throw URLError(.badServerResponse)
            }
            print("[MemosV1Service] signIn response body:\(String(data: data, encoding: .utf8) ?? "")")
            struct SignInResp: Decodable { let accessToken: String? }
            let decoder = JSONDecoder()
            let respObj = try decoder.decode(SignInResp.self, from: data)
            if let token = respObj.accessToken {
                accessToken = token
                print("[MemosV1Service] obtained access token, reinitializing client")
                client = Client(
                    serverURL: hostURL,
                    transport: URLSessionTransport(configuration: .init(session: urlSession)),
                    middlewares: [
                        AccessTokenAuthenticationMiddleware(accessToken: token),
                        grpcSetCookieMiddleware
                    ]
                )
            } else {
                let bodyString = String(data: data, encoding: .utf8) ?? ""
                print("[MemosV1Service] signIn response missing accessToken body:\(bodyString)")
            }
        } catch {
            print("[MemosV1Service] signIn failed: \(error)")
            throw error
        }
    }
    
    public func memoVisibilities() -> [MemoVisibility] {
        return [.private, .local, .public]
    }
    
    public func listMemos() async throws -> [Memo] {
        try await signInIfNeeded()
        guard let userId = userId else { throw MoeMemosError.notLogin }
        var memos = [Memo]()
        var nextPageToken: String? = nil
        
        repeat {
            let resp = try await client.MemoService_ListMemos(query: .init(pageSize: 200, pageToken: nextPageToken, state: .NORMAL, filter: "creator_id == \(userId)"))
            let data = try resp.ok.body.json
            memos += data.memos?.map { $0.toMemo(host: hostURL) } ?? []
            nextPageToken = data.nextPageToken
        } while (nextPageToken?.isEmpty == false)
        
        return memos
    }

    public func listMemos(filter: String?, orderBy: String?) async throws -> [Memo] {
        try await signInIfNeeded()
        guard let userId = userId else { throw MoeMemosError.notLogin }

        var memos = [Memo]()
        var nextPageToken: String? = nil

        let baseFilter = "creator_id == \(userId)"
        let fullFilter: String
        if let filter, !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullFilter = "\(baseFilter) && (\(filter))"
        } else {
            fullFilter = baseFilter
        }

        repeat {
            let resp = try await client.MemoService_ListMemos(query: .init(
                pageSize: 200,
                pageToken: nextPageToken,
                state: .NORMAL,
                orderBy: orderBy,
                filter: fullFilter
            ))
            let data = try resp.ok.body.json
            memos += data.memos?.map { $0.toMemo(host: hostURL) } ?? []
            nextPageToken = data.nextPageToken
        } while (nextPageToken?.isEmpty == false)

        return memos
    }
    
    public func listArchivedMemos() async throws -> [Memo] {
        try await signInIfNeeded()
        guard let userId = userId else { throw MoeMemosError.notLogin }
        var memos = [Memo]()
        var nextPageToken: String? = nil
        
        repeat {
            let resp = try await client.MemoService_ListMemos(query: .init(pageSize: 200, pageToken: nextPageToken, state: .ARCHIVED, filter: "creator_id == \(userId)"))
            let data = try resp.ok.body.json
            memos += data.memos?.map { $0.toMemo(host: hostURL) } ?? []
            nextPageToken = data.nextPageToken
        } while (nextPageToken?.isEmpty == false)
        
        return memos
    }
    
    public func listWorkspaceMemos(pageSize: Int, pageToken: String?) async throws -> (list: [Memo], nextPageToken: String?) {
        try await signInIfNeeded()
        let resp = try await client.MemoService_ListMemos(query: .init(pageSize: 200, pageToken: pageToken))
        let data = try resp.ok.body.json
        return (data.memos?.map { $0.toMemo(host: hostURL) } ?? [], data.nextPageToken)
    }

    public func getDailyReview(date: Date, timezone: TimeZone) async throws -> String {
        try await signInIfNeeded()

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"

        let req = Components.Schemas.GetDailyReviewRequest(
            date: formatter.string(from: date),
            timezone: timezone.identifier
        )
        let resp = try await client.MemoService_GetDailyReview(body: .json(req))
        switch resp {
        case .ok(let okResponse):
            let data = try okResponse.body.json
            return data.content ?? ""
        case .default(let statusCode, let defaultResponse):
            switch defaultResponse.body {
            case .json(let status):
                throw MoeMemosError.invalidStatusCode(statusCode, Self.formatStatusMessage(status, statusCode: statusCode))
            }
        }
    }

    public func getMemoInsight(filter: String?, prompt: String?) async throws -> String {
        try await signInIfNeeded()

        let req = Components.Schemas.GetMemoInsightRequest(
            filter: filter,
            prompt: prompt
        )
        let resp = try await client.MemoService_GetMemoInsight(body: .json(req))
        switch resp {
        case .ok(let okResponse):
            let data = try okResponse.body.json
            return data.content ?? ""
        case .default(let statusCode, let defaultResponse):
            switch defaultResponse.body {
            case .json(let status):
                throw MoeMemosError.invalidStatusCode(statusCode, Self.formatStatusMessage(status, statusCode: statusCode))
            }
        }
    }

    public func getTextRefine(filter: String?, prompt: String?) async throws -> String {
        try await signInIfNeeded()

        let req = Components.Schemas.TextRefineRequest(
            text: filter,
            prompt: prompt
        )
        let resp = try await client.MemoService_TextRefine(body: .json(req))
        switch resp {
        case .ok(let okResponse):
            let data = try okResponse.body.json
            return data.content ?? ""
        case .default(let statusCode, let defaultResponse):
            switch defaultResponse.body {
            case .json(let status):
                throw MoeMemosError.invalidStatusCode(statusCode, Self.formatStatusMessage(status, statusCode: statusCode))
            }
        }
    }

    private static func formatStatusMessage(_ status: Components.Schemas.Status, statusCode: Int) -> String? {
        var pieces: [String] = []
        if let message = status.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            pieces.append(message)
        }
        if let code = status.code {
            pieces.append("code: \(code)")
        }

        if pieces.isEmpty {
            return "Request failed (HTTP \(statusCode))."
        }
        return "\(pieces.joined(separator: " - ")) (HTTP \(statusCode))"
    }
    
    public func createMemo(content: String, visibility: MemoVisibility?, resources: [Resource], tags: [String]?) async throws -> Memo {
        try await signInIfNeeded()
        let resp = try await client.MemoService_CreateMemo(body: .json(MemosV1Memo(
            state: .NORMAL,
            content: content,
            visibility: visibility.map { MemosV1Visibility(memoVisibility: $0) } ?? .PRIVATE
        )))
        let memo = try resp.ok.body.json
        
        var result = memo.toMemo(host: hostURL)
        if resources.isEmpty {
            return result
        }
        
        guard let name = memo.name else { throw MoeMemosError.unsupportedVersion }
        let memosResources: [MemosV1Resource] = resources.compactMap {
            var resource: MemosV1Resource? = nil
            if let remoteId = $0.remoteId {
                resource = MemosV1Resource(name: getName(remoteId: remoteId), filename: $0.filename, _type: $0.mimeType)
            }
            return resource
        }
        let setResourceResp = try await client.MemoService_SetMemoAttachments(path: .init(memo: getId(remoteId: name)), body: .json(.init(name: name, attachments: memosResources)))
        _ = try setResourceResp.ok
        result.resources = resources
        return result
    }
    
    public func updateMemo(remoteId: String, content: String?, resources: [Resource]?, visibility: MemoVisibility?, tags: [String]?, pinned: Bool?) async throws -> Memo {
        try await signInIfNeeded()
        let resp = try await client.MemoService_UpdateMemo(path: .init(memo: getId(remoteId: remoteId)), body: .json(MemosV1Memo(
            state: .NORMAL,
            updateTime: .now,
            content: content ?? "",
            visibility: visibility.map { MemosV1Visibility(memoVisibility: $0) } ?? .PRIVATE,
            pinned: pinned
        )))
        let memo = try resp.ok.body.json
        var result = memo.toMemo(host: hostURL)
        
        guard let resources = resources, Set(resources.map { $0.remoteId }) != Set(result.resources.map { $0.remoteId }) else { return result }
        let memosResources: [MemosV1Resource] = resources.compactMap {
            var resource: MemosV1Resource? = nil
            if let remoteId = $0.remoteId {
                resource = MemosV1Resource(name: getName(remoteId: remoteId), filename: $0.filename, _type: $0.mimeType)
            }
            return resource
        }
        let setResourceResp = try await client.MemoService_SetMemoAttachments(path: .init(memo: getId(remoteId: remoteId)), body: .json(.init(name: getName(remoteId: remoteId), attachments: memosResources)))
        _ = try setResourceResp.ok
        result.resources = resources
        return result
    }
    
    public func deleteMemo(remoteId: String) async throws {
        try await signInIfNeeded()
        let resp = try await client.MemoService_DeleteMemo(path: .init(memo: getId(remoteId: remoteId)))
        _ = try resp.ok
    }
    
    public func archiveMemo(remoteId: String) async throws {
        try await signInIfNeeded()
        let resp = try await client.MemoService_UpdateMemo(path: .init(memo: getId(remoteId: remoteId)), body: .json(MemosV1Memo(state: .ARCHIVED, content: "", visibility: .PRIVATE)))
        _ = try resp.ok
    }
    
    public func restoreMemo(remoteId: String) async throws {
        try await signInIfNeeded()
        let resp = try await client.MemoService_UpdateMemo(path: .init(memo: getId(remoteId: remoteId)), body: .json(MemosV1Memo(state: .NORMAL, content: "", visibility: .PRIVATE)))
        _ = try resp.ok
    }
    
    public func listTags() async throws -> [Tag] {
        try await signInIfNeeded()
        guard let userId = userId else { throw MoeMemosError.notLogin }
        let resp = try await client.UserService_GetUserStats(path: .init(user: "\(userId)"))
        let data = try resp.ok.body.json
        
        var tags = [Tag]()
        if let tagCount = data.tagCount?.additionalProperties {
            for (tag, _) in tagCount {
                tags.append(.init(name: tag))
            }
        }
        return tags
    }
    
    public func listResources() async throws -> [Resource] {
        try await signInIfNeeded()
        let resp = try await client.AttachmentService_ListAttachments()
        let data = try resp.ok.body.json
        return data.attachments?.map { $0.toResource(host: hostURL) } ?? []
    }
    
    public func createResource(filename: String, data: Data, type: String, memoRemoteId: String?) async throws -> Resource {
        try await signInIfNeeded()
        let resp = try await client.AttachmentService_CreateAttachment(body: .json(.init(
            filename: filename,
            content: data.base64EncodedString(),
            _type: type,
            memo: memoRemoteId.map(getName(remoteId:))
        )))
        let data = try resp.ok.body.json
        return data.toResource(host: hostURL)
    }
    
    public func deleteResource(remoteId: String) async throws {
        try await signInIfNeeded()
        let resp = try await client.AttachmentService_DeleteAttachment(path: .init(attachment: getId(remoteId: remoteId)))
        _ = try resp.ok
    }
    
    public func getCurrentUser() async throws -> User {
        try await signInIfNeeded()
        let resp = try await client.AuthService_GetCurrentUser()

        let json = try resp.ok.body.json
        guard let userWrapper = json.user else {
            throw MoeMemosError.notLogin
        }

        let user = userWrapper.value1

        guard let name = user.name else { throw MoeMemosError.unsupportedVersion }
        let userSettingResp = try await client.UserService_GetUserSetting(path: .init(user: getId(remoteId: name), setting: "GENERAL"))

        let setting = try userSettingResp.ok.body.json
        return await toUser(user, setting: setting)
    }
    
    public func getWorkspaceProfile() async throws -> MemosV1Profile {
        try await signInIfNeeded()
        let resp = try await client.InstanceService_GetInstanceProfile()
        return try resp.ok.body.json
    }

    public func updateDisplayName(_ displayName: String) async throws -> User {
        try await signInIfNeeded()
        guard let userId = userId else { throw MoeMemosError.notLogin }

        let getResp = try await client.UserService_GetUser(path: .init(user: userId))
        var current = try getResp.ok.body.json
        current.displayName = displayName

        let updateResp = try await client.UserService_UpdateUser(
            path: .init(user: userId),
            query: .init(updateMask: "display_name"),
            body: .json(current)
        )
        let updated = try updateResp.ok.body.json

        let name = updated.name ?? "users/\(userId)"
        let userSettingResp = try await client.UserService_GetUserSetting(path: .init(user: getId(remoteId: name), setting: "GENERAL"))
        let setting = try userSettingResp.ok.body.json
        return await toUser(updated, setting: setting)
    }

    public func updatePassword(_ newPassword: String) async throws {
        try await signInIfNeeded()
        guard let userId = userId else { throw MoeMemosError.notLogin }

        let getResp = try await client.UserService_GetUser(path: .init(user: userId))
        var current = try getResp.ok.body.json
        current.password = newPassword

        let updateResp = try await client.UserService_UpdateUser(
            path: .init(user: userId),
            query: .init(updateMask: "password", allowMissing: true),
            body: .json(current)
        )
        _ = try updateResp.ok
    }
    
    public func download(url: URL, mimeType: String? = nil) async throws -> URL {
        try await signInIfNeeded()
        let token = accessToken
        let setCookieHeaderValue = await grpcSetCookieMiddleware.setCookieHeaderValue
        let cookie = setCookieHeaderValue.map(cookieHeaderValue(from:))
        return try await ServiceUtils.download(
            urlSession: urlSession,
            url: url,
            mimeType: mimeType,
            middleware: { request in
                var request = request
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
    
    func downloadData(url: URL) async throws -> Data {
        try await signInIfNeeded()
        let token = accessToken
        let setCookieHeaderValue = await grpcSetCookieMiddleware.setCookieHeaderValue
        let cookie = setCookieHeaderValue.map(cookieHeaderValue(from:))
        return try await ServiceUtils.downloadData(
            urlSession: urlSession,
            url: url,
            middleware: { request in
                var request = request
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
    
    private func getName(remoteId: String) -> String {
        return remoteId.split(separator: "|").first.map(String.init) ?? ""
    }
    
    private func getId(remoteId: String) -> String {
        return remoteId.split(separator: "|").first?.split(separator: "/").last.map(String.init) ?? ""
    }
    
    func toUser(_ memosUser: MemosV1User, setting: Components.Schemas.UserSetting? = nil) async -> User {
        let remoteId = getId(remoteId: memosUser.name ?? "0")
        let key = "memos:\(hostURL.absoluteString):\(remoteId)"
        let user = User(
            accountKey: key,
            nickname: memosUser.displayName ?? memosUser.username,
            creationDate: memosUser.createTime ?? .now,
            email: memosUser.email,
            remoteId: remoteId
        )
        if let avatarUrl = memosUser.avatarUrl, let url = URL(string: avatarUrl) {
            var url = url
            if url.host() == nil {
                url = hostURL.appending(path: avatarUrl)
            }
            user.avatarData = try? await downloadData(url: url)
        }
        if let visibilityString = setting?.generalSetting?.memoVisibility, let visibility = MemosV1Visibility(rawValue: visibilityString) {
            user.defaultVisibility = visibility.toMemoVisibility()
        }
        return user
    }
}
