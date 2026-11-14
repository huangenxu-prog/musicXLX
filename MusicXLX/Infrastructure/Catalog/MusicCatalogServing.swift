import Foundation

/// Catalog/search boundary consumed by the finalized discovery UI.
/// Implementations are supplied by the active LX JavaScript source runtime;
/// the UI must not know about GDStudio or any individual music provider.
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
