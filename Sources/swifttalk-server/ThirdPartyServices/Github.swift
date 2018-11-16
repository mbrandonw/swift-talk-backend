//
//  Github.swift
//  Bits
//
//  Created by Chris Eidhof on 13.08.18.
//

import Foundation

struct GithubProfile: Codable {
    let login: String
    let id: Int
    let avatar_url: String
    let email: String?
    let name: String?
    // todo we get more than this, but should be enough info
}

struct GithubRepository: Codable {
    var name: String
    var `private`: Bool
}


struct Github {
    // todo initialize? We could also have an "AuthenticatedGithub" struct which requires the access token.
    static var clientId: String { return env["GITHUB_CLIENT_ID"] }
    static var clientSecret: String { return env["GITHUB_CLIENT_SECRET"] }
    static var token: String { return env["GITHUB_ACCESS_TOKEN"] }
    static var transcriptsRepo = "episode-transcripts"
    static var staticDataRepo = "swift-talk-static-data"
    
    struct File: Codable {
        var url: URL
    }

    struct AccessTokenResponse: Codable, Equatable {
        var access_token: String
        var token_type: String
        var scope: String
    }
    
    let accessToken: String
    init(_ accessToken: String) {
        self.accessToken = accessToken
    }
    
    static func getAccessToken(_ code: String) -> RemoteEndpoint<AccessTokenResponse> {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        let query = [
            "client_id": Github.clientId,
            "client_secret": Github.clientSecret,
            "code": code,
            "accept": "json"
        ]
        return RemoteEndpoint(postJSON: url, query: query)
    }
    
    var profile: RemoteEndpoint<GithubProfile> {
        let url = URL(string: "https://api.github.com/user")!
        let query = ["access_token": accessToken]
        return RemoteEndpoint(getJSON: url, query: query)
    }
    
    static func profile(username: String) -> RemoteEndpoint<GithubProfile> {
        let url = URL(string: "https://api.github.com/users/\(username)")!
        let query = ["access_token": token]
        return RemoteEndpoint(getJSON: url, query: query)
    }
    
    static func changeVisibility(`private`: Bool, of repository: String) -> RemoteEndpoint<Bool> {
        let url = URL(string: "https://api.github.com/objcio/\(repository)")!
        let query = ["access_token": token]
        let data = GithubRepository(name: repository, private: `private`)
        return RemoteEndpoint<GithubRepository>(patchJSON: url, body: data, query: query).map { $0.`private` == `private` }
    }
    
    static var transcripts: RemoteEndpoint<[Github.File]> {
        let url = URL(string: "https://api.github.com/repos/objcio/\(transcriptsRepo)/contents/")!
        let query = ["access_token": token, "ref": "master"]
        return RemoteEndpoint<[Github.File]>(getJSON: url, query: query).map { files in
            return files.filter { $0.name.hasPrefix("episode") }
        }
    }
    
    static func staticData<A: StaticLoadable>() -> RemoteEndpoint<[A]> {
        let url = URL(string: "https://api.github.com/repos/objcio/\(staticDataRepo)/contents/\(A.jsonName)")!
        let headers = ["Authorization": "token \(token)", "Accept": "application/vnd.github.v3.raw"]
        return RemoteEndpoint(getJSON: url, headers: headers)
    }
    
    static var loadTranscripts: Promise<[(file: Github.File, contents: String?)]> {
        return URLSession.shared.load(transcripts).flatMap { transcripts in
            let files = transcripts ?? []
            let promises = files
                .map { (file: $0, endpoint: Github.contents($0.url)) }
                .map { (file: $0.file, promise: URLSession.shared.load($0.endpoint)) }
                .map { t in t.promise.map { (file: t.file, contents: $0) } }
            return sequentially(promises)
        }
    }

    static func contents(_ url: URL) -> RemoteEndpoint<String> {
        let headers = ["Authorization": "token \(token)", "Accept": "application/vnd.github.v3.raw"]
        return RemoteEndpoint(get: url, headers: headers, query: [:]) { String(data: $0, encoding: .utf8) }
    }
}


extension Github.File {
    var repository: String {
        return url.pathComponents[3]
    }
    
    var path: String {
        return url.pathComponents[5...].joined(separator: "/")
    }
    
    var name: String {
        return url.lastPathComponent
    }
}
