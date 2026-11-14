import Foundation

enum MusicXLXRuntimeError: LocalizedError {
    case sourceStoreUnavailable(String)
    case noEnabledSource(String)
    case malformedResult(String)
    case catalogUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .sourceStoreUnavailable(let message):
            return "音源存储初始化失败：\(message)"
        case .noEnabledSource(let platform):
            return "没有已启用且注册了 \(platform) 平台及 musicUrl 动作的音源脚本。"
        case .malformedResult(let message):
            return "音源返回数据格式错误：\(message)"
        case .catalogUnavailable(let message):
            return message
        }
    }
}

struct CachedLyrics: Codable {
    let original: String
    let translated: String?
}

@MainActor
protocol MusicXLXRuntimeServing: MusicCatalogServing {
    func resolvePlaybackURL(song: MusicSong, quality: MusicQuality, forceRefresh: Bool) async throws -> URL
    func artworkURL(for song: MusicSong) async throws -> URL?
    func lyrics(for song: MusicSong) async throws -> (original: String, translated: String?)?
    func importSource(script: String, metadata: LXSourceStore.Metadata) throws -> LXSourceStore.Entry
    func enableSource(id: String) async throws
    func disableSource(id: String) throws
    func removeSource(id: String) throws
    func installedSources() -> [LXSourceStore.Entry]
    func sourceCapabilities(id: String) -> [String: [String]]
}

/// The app-facing implementation of the LX source runtime.
/// JavaScript resolves source URLs; AVPlayer remains the only playback engine.
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
            NSLog("[MusicXLX:LX] source store initialization failed: %@", error.localizedDescription)
        }
    }

    func resolvePlaybackURL(song: MusicSong, quality: MusicQuality, forceRefresh: Bool = false) async throws -> URL {
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }

        await sourceManager.waitUntilRestored()
        let scriptIDs = sourceManager.enabledSourceIDs(for: song.source.rawValue)
        guard !scriptIDs.isEmpty else {
            throw MusicXLXRuntimeError.noEnabledSource(song.source.displayName)
        }

        var failures: [String] = []
        for scriptID in scriptIDs {
            guard let entry = sourceManager.sources().first(where: { $0.metadata.id == scriptID }),
                  let platform = sourceManager.registration(for: scriptID)?.sources[song.source.rawValue],
                  platform.actions.contains("musicUrl") else { continue }

            let resolvedQuality = Self.bestSupportedQuality(requested: quality, available: platform.qualitys)
            let cacheKey = "lx-url|\(scriptID)|\(entry.metadata.version)|\(song.source.rawValue)|\(song.sourceID)|\(resolvedQuality)"

            if forceRefresh {
                await MusicCache.shared.removeValue(for: cacheKey)
            } else if let cached: String = await MusicCache.shared.value(for: cacheKey),
                      let url = URL(string: cached), Self.isHTTPURL(url) {
                return url
            }

            do {
                let info = Self.musicInfo(for: song, quality: resolvedQuality)
                let result = try await invoke(
                    manager: sourceManager,
                    scriptID: scriptID,
                    platform: song.source.rawValue,
                    action: "musicUrl",
                    info: info
                )
                guard let data = result["data"] as? [String: Any],
                      let rawURL = data["url"] as? String,
                      let url = URL(string: rawURL),
                      Self.isHTTPURL(url) else {
                    throw MusicXLXRuntimeError.malformedResult("\(entry.metadata.name) 未返回有效的 HTTP 播放地址")
                }
                await MusicCache.shared.insert(url.absoluteString, for: cacheKey, ttl: 5 * 60)
                return url
            } catch {
                failures.append("\(entry.metadata.name)：\(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            throw MusicXLXRuntimeError.noEnabledSource(song.source.displayName)
        }
        throw MusicSourceError.noPlayableURL(
            source: song.source,
            details: failures.joined(separator: "；")
        )
    }

    func artworkURL(for song: MusicSong) async throws -> URL? {
        if let existing = song.artworkURL { return existing }
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }

        await sourceManager.waitUntilRestored()
        let info = Self.musicInfo(for: song, quality: MusicQuality.standard.rawValue)
        for scriptID in sourceManager.enabledSourceIDs(for: song.source.rawValue) {
            guard let entry = sourceManager.sources().first(where: { $0.metadata.id == scriptID }),
                  sourceManager.registration(for: scriptID)?.sources[song.source.rawValue]?.actions.contains("pic") == true else { continue }
            let cacheKey = "lx-pic|\(scriptID)|\(entry.metadata.version)|\(song.source.rawValue)|\(song.sourceID)"
            if let cached: String = await MusicCache.shared.value(for: cacheKey),
               let url = URL(string: cached), Self.isHTTPURL(url) { return url }
            do {
                let result = try await invoke(manager: sourceManager, scriptID: scriptID, platform: song.source.rawValue, action: "pic", info: info)
                guard let raw = result["data"] as? String,
                      let url = URL(string: raw), Self.isHTTPURL(url) else { continue }
                await MusicCache.shared.insert(url.absoluteString, for: cacheKey, ttl: 7 * 24 * 60 * 60)
                return url
            } catch {
                continue
            }
        }
        return nil
    }

    func lyrics(for song: MusicSong) async throws -> (original: String, translated: String?)? {
        guard let sourceManager else {
            throw MusicXLXRuntimeError.sourceStoreUnavailable(storeError ?? "未知错误")
        }

        await sourceManager.waitUntilRestored()
        let info = Self.musicInfo(for: song, quality: MusicQuality.standard.rawValue)
        for scriptID in sourceManager.enabledSourceIDs(for: song.source.rawValue) {
            guard let entry = sourceManager.sources().first(where: { $0.metadata.id == scriptID }),
                  sourceManager.registration(for: scriptID)?.sources[song.source.rawValue]?.actions.contains("lyric") == true else { continue }
            let cacheKey = "lx-lyric|\(scriptID)|\(entry.metadata.version)|\(song.source.rawValue)|\(song.sourceID)"
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
            } catch {
                continue
            }
        }
        return nil
    }

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

    func sourceCapabilities(id: String) -> [String: [String]] {
        guard let registration = sourceManager?.registration(for: id) else { return [:] }
        return registration.sources.mapValues { platform in
            platform.actions + platform.qualitys.map { "quality:\($0)" }
        }
    }

    // LX user-api scripts expose playback/metadata actions, not catalog search.
    // Keep catalog discovery explicitly unavailable until a separate provider
    // contract is implemented; never synthesize search or playlist results.
    func search(keyword: String, source: MusicSource, page: Int = 1, count: Int = 50, albumOnly: Bool = false) async throws -> [MusicSong] {
        throw MusicXLXRuntimeError.catalogUnavailable("当前洛雪音源协议不提供歌曲搜索接口，目录搜索模块尚未接入。")
    }

    func playlistTracks(keyword: String, count: Int) async throws -> [MusicSong] {
        throw MusicXLXRuntimeError.catalogUnavailable("当前洛雪音源协议不提供歌单曲目接口，目录服务尚未接入。")
    }

    func toplist(_ chartName: String, count: Int) async throws -> [MusicSong] {
        throw MusicXLXRuntimeError.catalogUnavailable("当前洛雪音源协议不提供排行榜接口，目录服务尚未接入。")
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

    private static func musicInfo(for song: MusicSong, quality: String) -> [String: Any] {
        var info: [String: Any] = [
            "id": song.sourceID,
            "name": song.title,
            "artist": song.artist,
            "type": quality
        ]
        info["hash"] = song.hash
        info["songmid"] = song.sourceID
        info["album"] = song.album
        info["albumId"] = song.albumID
        info["pictureId"] = song.pictureID
        info["lyricId"] = song.lyricID
        info["copyrightId"] = song.copyrightID
        info["pic"] = song.artworkURL?.absoluteString
        return ["musicInfo": info, "type": quality]
    }

    private static func bestSupportedQuality(requested: MusicQuality, available: [String]) -> String {
        guard !available.isEmpty else { return requested.rawValue }
        if available.contains(requested.rawValue) { return requested.rawValue }

        let fallbackOrder: [MusicQuality: [String]] = [
            .standard: ["128k", "192k", "320k", "flac"],
            .high: ["320k", "192k", "128k"],
            .lossless: ["flac", "flac24bit", "hires", "master"],
            .hires: ["flac24bit", "hires", "master", "atmos", "atmos_plus", "flac", "320k"]
        ]
        return fallbackOrder[requested]?.first(where: { available.contains($0) }) ?? available.first ?? requested.rawValue
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
