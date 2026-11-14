import Foundation

enum MusicXLXRuntimeError: LocalizedError {
    case runtimeNotInstalled
    case sourceStoreUnavailable(String)
    case noEnabledSource(String)
    case malformedResult(String)

    var errorDescription: String? {
        switch self {
        case .runtimeNotInstalled:
            return "洛雪 JS Runtime 尚未接入，当前无法读取音源数据。"
        case .sourceStoreUnavailable(let message):
            return "音源存储初始化失败：\(message)"
        case .noEnabledSource(let platform):
            return "没有已启用且注册了 \(platform) 平台的音源脚本。"
        case .malformedResult(let message):
            return "音源返回数据格式错误：\(message)"
        }
    }
}

/// Unified UI-facing contract. Views do not call provider SDKs or URL resolvers.
@MainActor
protocol MusicXLXRuntimeServing: MusicCatalogServing {
    func resolvePlaybackURL(song: MusicSong, quality: MusicQuality, forceRefresh: Bool) async throws -> URL
    func artworkURL(for song: MusicSong) async throws -> URL?
    func lyrics(for song: MusicSong) async throws -> (original: String, translated: String?)?
}

@MainActor
final class MusicXLXRuntimeServices: MusicXLXRuntimeServing {
    static let shared = MusicXLXRuntimeServices()

    private let sourceManager: LXSourceManager?
    private let storeError: String?

    private init() {
        do {
            let store = try LXSourceStore()
            let manager = LXSourceManager(store: store)
            sourceManager = manager
            storeError = nil
            manager.restoreEnabledSources()
        } catch {
            sourceManager = nil
            storeError = error.localizedDescription
        }
    }

    /// Search, playlists and charts are not part of LX's standard musicUrl/lyric/pic
    /// contract. They remain explicitly unavailable until a separate catalog API is defined.
    func search(keyword: String, source: MusicSource, page: Int = 1, count: Int = 20, albumOnly: Bool = false) async throws -> [MusicSong] {
        throw MusicXLXRuntimeError.runtimeNotInstalled
    }

    func playlistTracks(keyword: String, count: Int = 50) async throws -> [MusicSong] {
        throw MusicXLXRuntimeError.runtimeNotInstalled
    }

    func toplist(_ chartName: String, count: Int = 50) async throws -> [MusicSong] {
        throw MusicXLXRuntimeError.runtimeNotInstalled
    }

    func resolvePlaybackURL(song: MusicSong, quality: MusicQuality, forceRefresh: Bool) async throws -> URL {
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }
        let platform = song.source.rawValue
        let candidates = sourceManager.enabledSourceIDs(for: platform)
        guard !candidates.isEmpty else {
            throw MusicXLXRuntimeError.noEnabledSource(platform)
        }

        var lastError: Error?
        for scriptID in candidates {
            guard let entry = sourceManager.sources().first(where: { $0.metadata.id == scriptID }),
                  let registration = sourceManager.registration(for: scriptID)?.sources[platform] else { continue }

            let selectedQuality = Self.bestSupportedQuality(requested: quality, available: registration.qualitys)
            let cacheKey = "lx-play-url|\(scriptID)|\(entry.metadata.version)|\(platform)|\(song.sourceID)|\(selectedQuality)"
            if !forceRefresh, let cached: String = await MusicCache.shared.value(for: cacheKey),
               let url = URL(string: cached), Self.isHTTPURL(url) {
                return url
            }

            do {
                let result = try await invoke(
                    manager: sourceManager,
                    scriptID: scriptID,
                    platform: platform,
                    action: "musicUrl",
                    info: Self.musicInfo(for: song, quality: selectedQuality)
                )
                guard let data = result["data"] as? [String: Any],
                      let rawURL = data["url"] as? String,
                      let url = URL(string: rawURL),
                      Self.isHTTPURL(url) else {
                    throw MusicXLXRuntimeError.malformedResult("musicUrl 缺少有效的 HTTP(S) data.url")
                }
                await MusicCache.shared.insert(url.absoluteString, for: cacheKey, ttl: 5 * 60)
                return url
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? MusicXLXRuntimeError.noEnabledSource(platform)
    }

    func artworkURL(for song: MusicSong) async throws -> URL? {
        if let existing = song.artworkURL { return existing }
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }
        let info = Self.musicInfo(for: song, quality: .standard)
        for scriptID in sourceManager.enabledSourceIDs(for: song.source.rawValue) {
            do {
                let result = try await invoke(manager: sourceManager, scriptID: scriptID, platform: song.source.rawValue, action: "pic", info: info)
                guard let raw = result["data"] as? String, let url = URL(string: raw), Self.isHTTPURL(url) else { continue }
                return url
            } catch { continue }
        }
        return nil
    }

    func lyrics(for song: MusicSong) async throws -> (original: String, translated: String?)? {
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }
        let info = Self.musicInfo(for: song, quality: .standard)
        for scriptID in sourceManager.enabledSourceIDs(for: song.source.rawValue) {
            do {
                let result = try await invoke(manager: sourceManager, scriptID: scriptID, platform: song.source.rawValue, action: "lyric", info: info)
                guard let data = result["data"] as? [String: Any],
                      let lyric = data["lyric"] as? String, !lyric.isEmpty else { continue }
                return (lyric, data["tlyric"] as? String)
            } catch { continue }
        }
        return nil
    }

    // Exposed to the future source-management screen; scripts are imported disabled by default.
    func importSource(script: String, metadata: LXSourceStore.Metadata) throws -> LXSourceStore.Entry {
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }
        return try sourceManager.importSource(script: script, metadata: metadata)
    }

    func enableSource(id: String) async throws {
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }
        try await withCheckedThrowingContinuation { continuation in
            sourceManager.enableSource(id: id) { result in
                continuation.resume(with: result.map { _ in () })
            }
        }
    }

    func disableSource(id: String) throws {
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }
        try sourceManager.disableSource(id: id)
    }

    func installedSources() -> [LXSourceStore.Entry] {
        sourceManager?.sources() ?? []
    }

    private func invoke(
        manager: LXSourceManager,
        scriptID: String,
        platform: String,
        action: String,
        info: [String: Any]
    ) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            manager.performAction(sourceID: scriptID, platform: platform, action: action, info: info) { result in
                continuation.resume(with: result)
            }
        }
    }

    private static func musicInfo(for song: MusicSong, quality: MusicQuality) -> [String: Any] {
        var info: [String: Any] = [
            "id": song.sourceID,
            "name": song.title,
            "artist": song.artist,
            "type": quality.rawValue
        ]
        info["hash"] = song.hash
        info["songmid"] = song.sourceID
        info["album"] = song.album
        info["albumId"] = song.albumID
        info["pictureId"] = song.pictureID
        info["lyricId"] = song.lyricID
        info["copyrightId"] = song.copyrightID
        info["pic"] = song.artworkURL?.absoluteString
        return [
            "musicInfo": info,
            "type": quality.rawValue
        ]
    }

    private static func bestSupportedQuality(requested: MusicQuality, available: [String]) -> String {
        guard !available.isEmpty else { return requested.rawValue }
        if available.contains(requested.rawValue) { return requested.rawValue }

        // LX providers may expose additional quality IDs (for example "hires",
        // "master", or "192k"). Preserve those declared values rather than
        // forcing every provider into the four UI labels.
        let fallbackOrder: [MusicQuality: [String]] = [
            .standard: ["128k", "192k", "320k", "flac"],
            .high: ["320k", "192k", "128k"],
            .lossless: ["flac", "flac24bit", "hires", "master"],
            .hires: ["flac24bit", "hires", "master", "atmos", "atmos_plus", "flac", "320k"]
        ]
        if let candidate = fallbackOrder[requested]?.first(where: { available.contains($0) }) {
            return candidate
        }
        return available.first ?? requested.rawValue
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
