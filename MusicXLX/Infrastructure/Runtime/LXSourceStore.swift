import Foundation

/// Persistent, provider-agnostic storage for user-imported LX JavaScript sources.
/// Script bytes are kept unchanged; metadata and enabled state live in a separate index.
final class LXSourceStore {
    struct Metadata: Codable, Equatable {
        let id: String
        var name: String
        var description: String
        var version: String
        var author: String
        var homepage: String
        var updatedAt: Date
    }

    struct Entry: Codable, Equatable, Identifiable {
        var id: String { metadata.id }
        var metadata: Metadata
        var isEnabled: Bool
        var scriptFile: String
    }

    enum StoreError: LocalizedError {
        case invalidIdentifier
        case emptyScript
        case sourceNotFound(String)
        case scriptMissing(String)

        var errorDescription: String? {
            switch self {
            case .invalidIdentifier: return "音源 ID 格式无效。"
            case .emptyScript: return "音源脚本内容为空。"
            case .sourceNotFound(let id): return "找不到音源：\(id)"
            case .scriptMissing(let id): return "音源脚本文件缺失：\(id)"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.huangenxu.musicxlx.lx-source-store")
    private let fileManager: FileManager
    private let rootURL: URL
    private let scriptsURL: URL
    private let indexURL: URL
    private let identifierPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
    private var entries: [String: Entry] = [:]

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        rootURL = support.appendingPathComponent("MusicXLX/LXSources", isDirectory: true)
        scriptsURL = rootURL.appendingPathComponent("Scripts", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("sources-index.json")
        try fileManager.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    func list() -> [Entry] {
        queue.sync { entries.values.sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending } }
    }

    @discardableResult
    func importScript(_ script: String, metadata: Metadata, enabled: Bool = false) throws -> Entry {
        try queue.sync {
            guard isValidIdentifier(metadata.id) else { throw StoreError.invalidIdentifier }
            guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.emptyScript }
            let fileName = metadata.id + ".js"
            let destination = scriptsURL.appendingPathComponent(fileName)
            // Atomic replacement ensures a failed import never leaves a partial script.
            try Data(script.utf8).write(to: destination, options: .atomic)
            let entry = Entry(metadata: metadata, isEnabled: enabled, scriptFile: fileName)
            entries[metadata.id] = entry
            try persistIndex()
            return entry
        }
    }

    func updateScript(id: String, script: String, metadata: Metadata? = nil) throws -> Entry {
        try queue.sync {
            guard var existing = entries[id] else { throw StoreError.sourceNotFound(id) }
            guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.emptyScript }
            if let metadata, metadata.id != id { throw StoreError.invalidIdentifier }
            let destination = scriptsURL.appendingPathComponent(existing.scriptFile)
            try Data(script.utf8).write(to: destination, options: .atomic)
            if let metadata { existing.metadata = metadata }
            existing.metadata.updatedAt = Date()
            entries[id] = existing
            try persistIndex()
            return existing
        }
    }

    func setEnabled(_ enabled: Bool, id: String) throws -> Entry {
        try queue.sync {
            guard var entry = entries[id] else { throw StoreError.sourceNotFound(id) }
            entry.isEnabled = enabled
            entries[id] = entry
            try persistIndex()
            return entry
        }
    }

    func script(for id: String) throws -> String {
        try queue.sync {
            guard let entry = entries[id] else { throw StoreError.sourceNotFound(id) }
            let url = scriptsURL.appendingPathComponent(entry.scriptFile)
            guard fileManager.fileExists(atPath: url.path) else { throw StoreError.scriptMissing(id) }
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func remove(id: String) throws {
        try queue.sync {
            guard let entry = entries.removeValue(forKey: id) else { throw StoreError.sourceNotFound(id) }
            let url = scriptsURL.appendingPathComponent(entry.scriptFile)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            try persistIndex()
        }
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return identifierPattern.firstMatch(in: value, range: range) != nil
    }

    private func persistIndex() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: indexURL, options: .atomic)
    }
}
