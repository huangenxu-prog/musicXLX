import SwiftUI
import UniformTypeIdentifiers

struct LXSourceManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LXSourceStore.Entry] = []
    @State private var isImporterPresented = false
    @State private var statusMessage: String?
    @State private var isErrorPresented = false
    @State private var isWorking = false

    private let services = MusicXLXRuntimeServices.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.025, green: 0.04, blue: 0.085).ignoresSafeArea()
                if entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "puzzlepiece")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("尚未导入音源")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("导入洛雪音乐源 JavaScript 文件后，启用即可参与播放解析。")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        importButton
                            .padding(.top, 8)
                    }
                } else {
                    List {
                        ForEach(entries) { entry in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.metadata.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text("v\(entry.metadata.version) · \(entry.metadata.author.isEmpty ? "未知作者" : entry.metadata.author)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.52))
                                    if !entry.metadata.description.isEmpty {
                                        Text(entry.metadata.description)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.62))
                                            .lineLimit(2)
                                    }
                                    Text(entry.isEnabled ? "已启用" : "已停用")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(entry.isEnabled ? Color.green.opacity(0.9) : .white.opacity(0.4))
                                    let capabilities = services.sourceCapabilities(id: entry.metadata.id)
                                    if !capabilities.isEmpty {
                                        Text("平台：" + capabilities.keys.sorted().map(platformName).joined(separator: "、"))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.55))
                                    }
                                }
                                Spacer(minLength: 8)
                                if isWorking {
                                    ProgressView().tint(.white)
                                } else {
                                    Toggle("", isOn: Binding(
                                        get: { entry.isEnabled },
                                        set: { setEnabled($0, for: entry) }
                                    ))
                                    .labelsHidden()
                                    .tint(Color(red: 0.28, green: 0.52, blue: 0.98))
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.055))
                            .swipeActions {
                                Button(role: .destructive) { remove(entry) } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("音源管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isImporterPresented = true } label: {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .disabled(isWorking)
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                importFile(result)
            }
            .alert("音源管理", isPresented: $isErrorPresented) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(statusMessage ?? "")
            }
            .onAppear(perform: refresh)
        }
        .preferredColorScheme(.dark)
    }

    private var importButton: some View {
        Button { isImporterPresented = true } label: {
            Label("导入 JS 音源", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(red: 0.22, green: 0.43, blue: 0.88), in: Capsule())
        }
        .disabled(isWorking)
    }

    private func refresh() {
        entries = services.installedSources()
    }

    private func platformName(_ platform: String) -> String {
        switch platform {
        case "wy": "网易云"
        case "tx": "QQ"
        case "kw": "酷我"
        case "kg": "酷狗"
        case "mg": "咪咕"
        case "qs": "汽水"
        case "ytm": "YouTube Music"
        case "yt": "YouTube"
        case "sp": "Spotify"
        default: platform
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let script = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "LXSourceImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件不是有效的 UTF-8 JavaScript 文本。"])
            }
            let metadata = LXSourceScriptMetadataParser.parse(script, fileName: url.lastPathComponent)
            _ = try services.importSource(script: script, metadata: metadata)
            statusMessage = "已导入「\(metadata.name)」，默认处于停用状态。"
            isErrorPresented = true
            refresh()
        } catch {
            statusMessage = error.localizedDescription
            isErrorPresented = true
        }
    }

    private func setEnabled(_ enabled: Bool, for entry: LXSourceStore.Entry) {
        isWorking = true
        Task {
            do {
                if enabled {
                    try await services.enableSource(id: entry.metadata.id)
                } else {
                    try services.disableSource(id: entry.metadata.id)
                }
                refresh()
            } catch {
                statusMessage = error.localizedDescription
                isErrorPresented = true
                refresh()
            }
            isWorking = false
        }
    }

    private func remove(_ entry: LXSourceStore.Entry) {
        do {
            try services.disableSource(id: entry.metadata.id)
            // The manager's store owns deletion; use its public service surface.
            try services.removeSource(id: entry.metadata.id)
            refresh()
        } catch {
            statusMessage = error.localizedDescription
            isErrorPresented = true
        }
    }
}
