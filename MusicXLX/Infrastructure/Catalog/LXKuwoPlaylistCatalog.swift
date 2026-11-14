import Foundation

/// Native adaptation of LX Music 1.9.2's Kuwo songList module.
/// The endpoint paths, default sort, digest IDs and detail resolution follow
/// src/utils/musicSdk/kw/songList.js. This does not build or modify LX itself.
struct LXKuwoPlaylistCatalog {
    enum CatalogError: LocalizedError {
        case invalidResponse
        case requestFailed(Int)
        case unsupportedDigest(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "酷我歌单返回的数据格式不正确。"
            case .requestFailed(let code): return "酷我歌单请求失败（HTTP \(code)）。"
            case .unsupportedDigest(let digest): return "暂不支持酷我歌单类型：\(digest)"
            }
        }
    }

    private let session: URLSession
    private let listLimit = 36
    private let songLimit = 1000

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// LX default page: source=kw, empty tag, sort=new, page=1.
    func recommendedPlaylists(count: Int = 6) async throws -> [MusicPlaylist] {
        var components = URLComponents(string: "https://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList")!
        components.queryItems = [
            URLQueryItem(name: "loginUid", value: "0"),
            URLQueryItem(name: "loginSid", value: "0"),
            URLQueryItem(name: "appUid", value: "76039576"),
            URLQueryItem(name: "pn", value: "1"),
            URLQueryItem(name: "rn", value: String(listLimit)),
            URLQueryItem(name: "order", value: "new")
        ]
        let object = try await getJSON(components.url!)
        guard let root = object as? [String: Any],
              let data = root["data"] as? [String: Any],
              let rows = data["data"] as? [[String: Any]] else {
            throw CatalogError.invalidResponse
        }

        return rows.prefix(max(0, count)).compactMap { item in
            guard let rawID = Self.string(item["id"]),
                  let digest = Self.string(item["digest"]),
                  let name = Self.string(item["name"]) else { return nil }
            let sourceID = "digest-\(digest)__\(rawID)"
            return MusicPlaylist(
                source: .kuwo,
                sourceID: sourceID,
                name: Self.decode(name),
                creator: Self.string(item["uname"]).map(Self.decode),
                description: Self.string(item["desc"]).map(Self.decode),
                artworkURL: Self.string(item["img"]).flatMap(URL.init(string:)),
                trackCount: Self.integer(item["total"]),
                provenance: .platformRecommended
            )
        }
    }

    /// LX getListDetail() behavior for the default Kuwo playlist IDs.
    /// Digest 8 is a normal playlist; digest 5 first resolves its source playlist ID.
    func playlistTracks(_ playlist: MusicPlaylist, count: Int = 50) async throws -> [MusicSong] {
        guard playlist.source == .kuwo else {
            throw MusicSourceError.unsupportedSource(playlist.source)
        }
        let parts = playlist.sourceID.split(separator: "__", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].hasPrefix("digest-") else {
            throw CatalogError.invalidResponse
        }
        let digest = String(parts[0].dropFirst("digest-".count))
        var playlistID = parts[1]
        if digest == "5" {
            playlistID = try await resolveDigest5PlaylistID(playlistID)
        } else if digest != "8" {
            throw CatalogError.unsupportedDigest(digest)
        }

        var components = URLComponents(string: "https://nplserver.kuwo.cn/pl.svc")!
        components.queryItems = [
            URLQueryItem(name: "op", value: "getlistinfo"),
            URLQueryItem(name: "pid", value: playlistID),
            URLQueryItem(name: "pn", value: "0"),
            URLQueryItem(name: "rn", value: String(songLimit)),
            URLQueryItem(name: "encode", value: "utf8"),
            URLQueryItem(name: "keyset", value: "pl2012"),
            URLQueryItem(name: "identity", value: "kuwo"),
            URLQueryItem(name: "pcmp4", value: "1"),
            URLQueryItem(name: "vipver", value: "MUSIC_9.0.5.0_W1"),
            URLQueryItem(name: "newver", value: "1")
        ]
        let object = try await getJSON(components.url!)
        guard let root = object as? [String: Any],
              Self.string(root["result"]) == "ok",
              let rows = root["musiclist"] as? [[String: Any]] else {
            throw CatalogError.invalidResponse
        }

        var seen = Set<String>()
        return rows.compactMap { item in
            guard let rawID = Self.string(item["id"]),
                  let rawName = Self.string(item["name"]) else { return nil }
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            let title = Self.decode(rawName)
            let artist = Self.decode(Self.string(item["artist"]) ?? "")
            let album = Self.string(item["album"]).map(Self.decode)
            let duration = Double(Self.string(item["duration"]) ?? "")
            return MusicSong(
                source: .kuwo,
                sourceID: id,
                title: title,
                artist: artist,
                album: album,
                artworkURL: nil,
                duration: duration
            )
        }.prefix(max(0, count)).map { $0 }
    }

    private func resolveDigest5PlaylistID(_ id: String) async throws -> String {
        var components = URLComponents(string: "https://qukudata.kuwo.cn/q.k")!
        components.queryItems = [
            URLQueryItem(name: "op", value: "query"),
            URLQueryItem(name: "cont", value: "ninfo"),
            URLQueryItem(name: "node", value: id),
            URLQueryItem(name: "pn", value: "0"),
            URLQueryItem(name: "rn", value: "1"),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "src", value: "mbox"),
            URLQueryItem(name: "level", value: "2")
        ]
        let object = try await getJSON(components.url!)
        guard let root = object as? [String: Any],
              let children = root["child"] as? [[String: Any]],
              let first = children.first,
              let sourceID = Self.string(first["sourceid"]) else {
            throw CatalogError.invalidResponse
        }
        return sourceID
    }

    private func getJSON(_ url: URL) async throws -> Any {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw CatalogError.requestFailed(http.statusCode) }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func decode(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }
}
