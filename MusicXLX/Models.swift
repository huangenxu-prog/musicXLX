import Foundation

/// The normalized handoff from the LX core to the MusicXLX player.
/// The LX core supplies the resolved URL and song metadata; MusicXLX does not
/// reinterpret or resolve provider URLs.
struct ResolvedTrack: Identifiable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let album: String?
    let source: String
    let quality: String

    init(
        url: URL,
        title: String,
        artist: String,
        album: String? = nil,
        source: String,
        quality: String
    ) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.source = source
        self.quality = quality
    }
}
