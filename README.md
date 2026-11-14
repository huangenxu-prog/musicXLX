# MusicXLX

MusicXLX is a standalone iOS music player. Its UI and playback experience are migrated from the finalized MusicX design, while music-source parsing is being rebuilt around a generic LX JavaScript runtime.

## Current migration state

- Finalized MusicX home UI and discovery UI have been migrated.
- The 24 homepage artwork assets and six search-category vector assets have been copied into the new asset catalog.
- Original PlayerStore is the single native AVPlayer owner.
- Original disk cache and catalog snapshot stores are retained.
- Search, chart, playlist, metadata, and playback calls now target MusicXLXRuntimeServices.
- Legacy GDStudio search/metadata and native URL resolver calls are not used by the migrated UI.
- A JavaScriptCore LX runtime adapter now provides isolated per-script contexts, serialized execution, LX initialization handshake, HTTP request/cancel/response bridging, timer callbacks, and Base64/MD5/AES/RSA helpers.
- LX preload platform registration is dynamic but constrained to validated platform IDs, supported actions, and supported quality values; community IDs such as `qs` are not hardcoded out.
- LXSourceStore persists raw imported scripts separately from metadata and enabled state. LXSourceManager provides import, enable, disable, reload, update, remove, and provider-action routing. A source-management sheet in the Music Library imports `.js` files, reads the LX metadata header, and lets users enable, disable, or remove scripts.
- MusicXLXRuntimeServices now routes playback URL, lyric, and artwork requests through enabled LX scripts and retains the native AVPlayer as the only playback owner. Playback URL cache keys include script ID/version, platform, song ID, and quality. Provider-declared quality identifiers are preserved, including extensions such as `hires` and `master`.
- Search, playlist, and chart retrieval remain pending: the standard LX source contract provides `musicUrl`, `lyric`, and `pic`, not catalog search APIs.

## Architecture boundary

- SwiftUI owns presentation and interaction.
- MusicXLXRuntimeServices is the UI-facing contract for catalog, metadata, lyrics, and playback URL resolution.
- LX JavaScript source scripts resolve provider resources; they do not control AVPlayer.
- Imported script contents are stored unchanged; each enabled script receives its own JavaScriptCore context.
- PlayerStore owns native playback, lock-screen controls, audio-session lifecycle, and playback diagnostics.
- MusicCache and MusicCatalogStore own reusable cache and catalog snapshots.

## Build policy

This branch is under active migration. A successful source commit does not imply an IPA build or device verification.
