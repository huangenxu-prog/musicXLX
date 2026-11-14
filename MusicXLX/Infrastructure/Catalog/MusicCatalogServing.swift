import Foundation

/// Search and catalog boundary used by the finalized MusicX interface.
/// Implementations are provided by the active LX JavaScript source runtime.
@MainActor
protocol MusicCatalogServing {
    func search(
        keyword: String,
        source: MusicSource,
        page: Int = 1,
        count: Int = 20,
        albumOnly: Bool = false
    ) async throws -> [MusicSong]

    func playlistTracks(keyword: String, count: Int = 50) async throws -> [MusicSong]

    func toplist(_ chartName: String, count: Int = 50) async throws -> [MusicSong]
}
