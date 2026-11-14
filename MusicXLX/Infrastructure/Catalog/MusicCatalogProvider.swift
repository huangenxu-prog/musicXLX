import Foundation

/// Normalized catalog boundary. Catalog providers own discovery and metadata;
/// LX source scripts remain responsible only for playback URL / artwork / lyrics.
@MainActor
protocol MusicCatalogProvider: AnyObject {
    var providerID: String { get }
    var supportedSources: Set<MusicSource> { get }
    var capabilities: MusicCatalogCapabilities { get }

    func searchSongs(keyword: String, source: MusicSource, page: Int, count: Int) async throws -> [MusicSong]
    func searchPlaylists(keyword: String, source: MusicSource, page: Int, count: Int) async throws -> [MusicPlaylist]
    func recommendedPlaylists(source: MusicSource, page: Int, count: Int) async throws -> [MusicPlaylist]
    func playlistTracks(_ playlist: MusicPlaylist, page: Int, count: Int) async throws -> [MusicSong]
    func toplist(_ chart: MusicChart, page: Int, count: Int) async throws -> [MusicSong]
    func albumTracks(source: MusicSource, albumID: String, page: Int, count: Int) async throws -> [MusicSong]
}

struct MusicCatalogCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let songSearch = Self(rawValue: 1 << 0)
    static let playlistSearch = Self(rawValue: 1 << 1)
    static let recommendations = Self(rawValue: 1 << 2)
    static let playlistDetail = Self(rawValue: 1 << 3)
    static let charts = Self(rawValue: 1 << 4)
    static let albumDetail = Self(rawValue: 1 << 5)
}

struct MusicChart: Identifiable, Hashable, Sendable {
    let id: String
    let source: MusicSource
    let name: String
    let description: String?
    let artworkURL: URL?
}

/// Keeps provider selection explicit and deterministic. A provider must declare
/// the source it can query; playback resolver registration is not consulted here.
@MainActor
final class MusicCatalogRegistry {
    static let shared = MusicCatalogRegistry()

    private var providers: [String: MusicCatalogProvider] = [:]

    private init() {}

    func register(_ provider: MusicCatalogProvider) {
        providers[provider.providerID] = provider
    }

    func unregister(providerID: String) {
        providers.removeValue(forKey: providerID)
    }

    func provider(for source: MusicSource, requiring capability: MusicCatalogCapabilities) -> MusicCatalogProvider? {
        providers.values
            .filter { $0.supportedSources.contains(source) && $0.capabilities.isSuperset(of: capability) }
            .sorted { $0.providerID < $1.providerID }
            .first
    }

    func registeredProviders() -> [(id: String, sources: [MusicSource], capabilities: MusicCatalogCapabilities)] {
        providers.values
            .sorted { $0.providerID < $1.providerID }
            .map { ($0.providerID, $0.supportedSources.sorted { $0.rawValue < $1.rawValue }, $0.capabilities) }
    }
}
