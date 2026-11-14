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
    func artworkURL(for song: MusicSong) async throws -> URL? {
        if let existing = song.artworkURL { return existing }
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }
        let info = Self.musicInfo(for: song, quality: .standard)
        for scriptID in sourceManager.enabledSourceIDs(for: song.source.rawValue) {
            guard let entry = sourceManager.sources().first(where: { $0.metadata.id == scriptID }) else { continue }
            let cacheKey = "lx-pic|\\(scriptID)|\\(entry.metadata.version)|\\(song.source.rawValue)|\\(song.sourceID)"
            if let cached: String = await MusicCache.shared.value(for: cacheKey),
               let url = URL(string: cached), Self.isHTTPURL(url) { return url }
            do {
                let result = try await invoke(manager: sourceManager, scriptID: scriptID, platform: song.source.rawValue, action: "pic", info: info)
                guard let raw = result["data"] as? String, let url = URL(string: raw), Self.isHTTPURL(url) else { continue }
                await MusicCache.shared.insert(url.absoluteString, for: cacheKey, ttl: 7 * 24 * 60 * 60)
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
            guard let entry = sourceManager.sources().first(where: { $0.metadata.id == scriptID }) else { continue }
            let cacheKey = "lx-lyric|\\(scriptID)|\\(entry.metadata.version)|\\(song.source.rawValue)|\\(song.sourceID)"
            if let cached: CachedLyrics = await MusicCache.shared.value(for: cacheKey) {
                return (cached.original, cached.translated)
            }
            do {
                let result = try await invoke(manager: sourceManager, scriptID: scriptID, platform: song.source.rawValue, action: "lyric", info: info)
                guard let data = result["data"] as? [String: Any],
                      let lyric = data["lyric"] as? String, !lyric.isEmpty else { continue }
                let translated = data["tlyric"] as? String
                await MusicCache.shared.insert(CachedLyrics(original: lyric, translated: translated), for: cacheKey, ttl: 24 * 60 * 60)
                return (lyric, translated)
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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

    func removeSource(id: String) throws {
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }
        try sourceManager.removeSource(id: id)
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
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
