import SwiftUI

struct ContentView: View {
    @StateObject private var player = AudioPlayer()
    @State private var testURL = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MusicXLX")
                        .font(.largeTitle.bold())
                    Text("洛雪核心负责解析，MusicXLX 负责播放")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("播放器连通性测试")
                        .font(.headline)
                    TextField("粘贴 HTTP / HTTPS 音频地址", text: $testURL, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    HStack {
                        Button("播放测试地址") {
                            guard let url = URL(string: testURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                            player.play(url: url)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(testURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(player.isPlaying ? "暂停" : "继续播放") {
                            player.togglePlayback()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(player.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if player.duration > 0 {
                        Slider(
                            value: Binding(
                                get: { min(player.currentTime, player.duration) },
                                set: { player.seek(to: $0) }
                            ),
                            in: 0...player.duration
                        )
                        HStack {
                            Text(player.currentTime.formatted(.number.precision(.fractionLength(0))))
                            Spacer()
                            Text(player.duration.formatted(.number.precision(.fractionLength(0))))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                Text("当前阶段：建立独立 iOS 工程与 AVPlayer 基础。下一阶段接入洛雪 1.9.2 核心运行环境。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
