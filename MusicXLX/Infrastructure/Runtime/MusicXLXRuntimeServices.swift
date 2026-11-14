import Foundation

enum MusicXLXRuntimeError: LocalizedError {
    case runtimeNotInstalled

    var errorDescription: String? {
        switch self {
        case .runtimeNotInstalled:
            return "洛雪 JS Runtime 尚未接入，当前无法读取音源数据。"
        }
    }
}

/// Unified UI-facing contract. The view layer never calls a provider SDK,
/// GDStudio endpoint, or legacy URL resolver directly.
@MainActor
protocol MusicXLXRuntimeServing: MusicCatalogServing {
    func resolvePlaybackURL(song: MusicSong, quality: MusicQuality, forceRefresh: Bool) async throws -> URL
    func artworkURL(for song: MusicSong) async throws -> URL?
    func lyrics(for song: MusicSong) async throws -> (original: String, translated: String?)?
}

/// Explicit integration seam for the LX runtime. Methods fail visibly until
/// the JavaScriptCore runtime adapter is installed; no legacy provider fallback.
@MainActor
final class MusicXLXRuntimeServices: MusicXLXRuntimeServing {
    static let shared = MusicXLXRuntimeServices()
    private init() {}

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
        throw MusicXLXRuntimeError.runtimeNotInstalled
    }

    func artworkURL(for song: MusicSong) async throws -> URL? {
        song.artworkURL
    }

    func lyrics(for song: MusicSong) async throws -> (original: String, translated: String?)? {
        throw MusicXLXRuntimeError.runtimeNotInstalled
    }
}
