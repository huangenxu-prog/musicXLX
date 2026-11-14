import Foundation

enum LXSourceScriptMetadataParser {
    static func parse(_ script: String, fileName: String) -> LXSourceStore.Metadata {
        let header = String(script.prefix(6000))
        let name = match(#"(?im)^\s*\*?\s*@name\s+(.+?)\s*$"#, in: header)
            ?? match(#"(?m)^\s*const\s+SCRIPT_NAME\s*=\s*['"]([^'"]+)['"]"#, in: header)
            ?? URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let description = match(#"(?im)^\s*\*?\s*@description\s+(.+?)\s*$"#, in: header) ?? ""
        let version = match(#"(?im)^\s*\*?\s*@version\s+(.+?)\s*$"#, in: header)
            ?? match(#"(?m)^\s*const\s+SCRIPT_VERSION\s*=\s*['"]([^'"]+)['"]"#, in: header)
            ?? "1.0.0"
        let author = match(#"(?im)^\s*\*?\s*@author\s+(.+?)\s*$"#, in: header) ?? ""
        let homepage = match(#"(?im)^\s*\*?\s*@homepage\s+(https?://\S+)"#, in: header) ?? ""

        let fileStem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let rawID = match(#"(?m)^\s*const\s+SCRIPT_NAME\s*=\s*['"]([^'"]+)['"]"#, in: header) ?? fileStem
        let id = sanitizedIdentifier(rawID.isEmpty ? fileStem : rawID)

        return LXSourceStore.Metadata(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            version: version.trimmingCharacters(in: .whitespacesAndNewlines),
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            homepage: homepage.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: Date()
        )
    }

    private static func match(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func sanitizedIdentifier(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let filtered = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        let result = filtered.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return String((result.isEmpty ? "LXSource-\\(UUID().uuidString)" : result).prefix(64))
    }
}
