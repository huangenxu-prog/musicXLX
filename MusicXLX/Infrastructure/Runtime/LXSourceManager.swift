import Foundation

/// Coordinates persisted source scripts and their isolated JavaScript runtimes.
/// Import is inert by default; enabling a source creates and initializes its runtime.
@MainActor
final class LXSourceManager {
    enum ManagerError: LocalizedError {
        case preloadResourceMissing

        var errorDescription: String? {
            switch self {
            case .preloadResourceMissing: return "应用包中找不到洛雪 preload 资源。"
            }
        }
    }

    private let store: LXSourceStore
    private let bundle: Bundle
    private var runtimes: [String: LXJavaScriptRuntime] = [:]
    private var registrations: [String: LXJavaScriptRuntime.RegisteredSource] = [:]

    init(store: LXSourceStore, bundle: Bundle = .main) {
        self.store = store
        self.bundle = bundle
    }

    func sources() -> [LXSourceStore.Entry] {
        store.list()
    }

    @discardableResult
    func importSource(script: String, metadata: LXSourceStore.Metadata) throws -> LXSourceStore.Entry {
        // Re-importing the same script ID replaces the old runtime as well as its stored bytes.
        runtimes.removeValue(forKey: metadata.id)?.destroy()
        registrations.removeValue(forKey: metadata.id)
        return try store.importScript(script, metadata: metadata, enabled: false)
    }

    func enableSource(id: String, completion: @escaping (Result<LXJavaScriptRuntime.RegisteredSource, Error>) -> Void) {
        do {
            let entry = try store.setEnabled(true, id: id)
            try load(entry: entry) { result in
                if case .failure = result {
                    _ = try? self.store.setEnabled(false, id: id)
                }
                completion(result)
            }
        } catch {
            completion(.failure(error))
        }
    }

    func disableSource(id: String) throws {
        runtimes.removeValue(forKey: id)?.destroy()
        registrations.removeValue(forKey: id)
        _ = try store.setEnabled(false, id: id)
    }

    func reloadSource(id: String, completion: @escaping (Result<LXJavaScriptRuntime.RegisteredSource, Error>) -> Void) {
        do {
            guard let entry = store.list().first(where: { $0.metadata.id == id }) else {
                throw LXSourceStore.StoreError.sourceNotFound(id)
            }
            try load(entry: entry, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    func updateSource(id: String, script: String, metadata: LXSourceStore.Metadata? = nil, completion: ((Result<LXJavaScriptRuntime.RegisteredSource, Error>) -> Void)? = nil) throws {
        let entry = try store.updateScript(id: id, script: script, metadata: metadata)
        guard entry.isEnabled else { return }
        try load(entry: entry) { result in completion?(result) }
    }

    func removeSource(id: String) throws {
        runtimes.removeValue(forKey: id)?.destroy()
        registrations.removeValue(forKey: id)
        try store.remove(id: id)
    }

    func registration(for id: String) -> LXJavaScriptRuntime.RegisteredSource? {
        registrations[id]
    }

    func enabledSourceIDs(for platform: String) -> [String] {
        store.list()
            .filter { $0.isEnabled && registrations[$0.metadata.id]?.sources[platform] != nil }
            .map { $0.metadata.id }
    }

    func restoreEnabledSources() {
        for entry in store.list() where entry.isEnabled {
            do {
                try load(entry: entry) { result in
                    if case .failure(let error) = result {
                        _ = try? self.store.setEnabled(false, id: entry.metadata.id)
                        NSLog("[MusicXLX:LX] restore failed (%@): %@", entry.metadata.id, error.localizedDescription)
                    }
                }
            } catch {
                NSLog("[MusicXLX:LX] restore failed (%@): %@", entry.metadata.id, error.localizedDescription)
            }
        }
    }

    func performAction(sourceID: String, platform: String, action: String, info: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let runtime = runtimes[sourceID] else {
            completion(.failure(LXSourceStore.StoreError.sourceNotFound(sourceID)))
            return
        }
        guard registrations[sourceID]?.sources[platform] != nil else {
            completion(.failure(LXJavaScriptRuntime.RuntimeError.javascript("当前脚本未注册平台：\(platform)")))
            return
        }
        runtime.performSourceAction(source: platform, action: action, info: info, completion: completion)
    }

    private func load(entry: LXSourceStore.Entry, completion: @escaping (Result<LXJavaScriptRuntime.RegisteredSource, Error>) -> Void) throws {
        guard let preloadURL = bundle.url(forResource: "user-api-preload", withExtension: "js", subdirectory: "LXRuntime")
                ?? bundle.url(forResource: "user-api-preload", withExtension: "js") else {
            throw ManagerError.preloadResourceMissing
        }
        let preload = try String(contentsOf: preloadURL, encoding: .utf8)
        let script = try store.script(for: entry.metadata.id)
        runtimes.removeValue(forKey: entry.metadata.id)?.destroy()
        registrations.removeValue(forKey: entry.metadata.id)

        let runtime = LXJavaScriptRuntime()
        runtimes[entry.metadata.id] = runtime
        let metadata = entry.metadata
        let runtimeMetadata = LXJavaScriptRuntime.ScriptMetadata(
            id: metadata.id,
            name: metadata.name,
            description: metadata.description,
            version: metadata.version,
            author: metadata.author,
            homepage: metadata.homepage
        )
        runtime.load(script: script, metadata: runtimeMetadata, preload: preload) { [weak self, weak runtime] result in
            DispatchQueue.main.async {
                guard let self, let runtime, self.runtimes[entry.metadata.id] === runtime else { return }
                switch result {
                case .success(let registered):
                    self.registrations[entry.metadata.id] = registered
                    completion(.success(registered))
                case .failure(let error):
                    self.runtimes.removeValue(forKey: entry.metadata.id)?.destroy()
                    self.registrations.removeValue(forKey: entry.metadata.id)
                    completion(.failure(error))
                }
            }
        }
    }
}
