import Foundation

/// Search and catalog boundary used by the finalized MusicX interface.
/// Implementations are provided by the active LX JavaScript source runtime.
@MainActor
protocol MusicCatalogServing {
    func search(
        keyword: String,
        source: MusicSource,
        page: Int,
        count: Int,
        albumOnly: Bool
    ) async throws -> [MusicSong]

    func playlistTracks(keyword: String, count: Int) async throws -> [MusicSong]

    func toplist(_ chartName: String, count: Int) async throws -> [MusicSong]
}
