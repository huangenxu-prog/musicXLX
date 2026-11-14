import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var statusText = "等待播放"
    @Published private(set) var currentTrack: ResolvedTrack?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemStatusObserver: NSKeyValueObservation?

    func play(url: URL) {
        let track = ResolvedTrack(
            url: url,
            title: url.lastPathComponent.isEmpty ? "测试音频" : url.lastPathComponent,
            artist: "",
            source: "manual-test",
            quality: "unknown"
        )
        play(track: track)
    }

    func play(track: ResolvedTrack) {
        let url = track.url
        guard url.scheme == "https" || url.scheme == "http" else {
            statusText = "播放地址必须是 HTTP 或 HTTPS"
            return
        }

        tearDownObservers()
        currentTrack = track
        let item = AVPlayerItem(url: url)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer

        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    self?.statusText = "已连接"
                case .failed:
                    self?.statusText = item.error?.localizedDescription ?? "播放失败"
                    self?.isPlaying = false
                case .unknown:
                    self?.statusText = "正在连接"
                @unknown default:
                    self?.statusText = "未知播放状态"
                }
            }
        }

        timeObserver = nextPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let duration = self?.player?.currentItem?.duration.seconds, duration.isFinite {
                    self?.duration = duration
                }
            }
        }

        nextPlayer.play()
        isPlaying = true
        statusText = "正在播放"
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            statusText = "已暂停"
        } else {
            player.play()
            isPlaying = true
            statusText = "正在播放"
        }
    }

    func seek(to seconds: TimeInterval) {
        guard seconds.isFinite, seconds >= 0 else { return }
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        tearDownObservers()
        isPlaying = false
        currentTime = 0
        duration = 0
        currentTrack = nil
        statusText = "已停止"
    }

    private func tearDownObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        itemStatusObserver = nil
    }
}
