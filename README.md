# MusicXLX

MusicXLX is a standalone iOS music player. Its UI and playback experience are migrated from the finalized MusicX design, while music-source parsing is being rebuilt around a generic LX JavaScript runtime.

## Current migration state

- Finalized MusicX home UI and discovery UI have been migrated.
- The 24 homepage artwork assets and six search-category vector assets have been copied into the new asset catalog.
- Original PlayerStore is the single native AVPlayer owner.
- Original disk cache and catalog snapshot stores are retained.
- Search, chart, playlist, metadata, and playback calls now target MusicXLXRuntimeServices.
- Legacy GDStudio search/metadata and native URL resolver calls are not used by the migrated UI.
- The LX JavaScriptCore runtime adapter and source-management UI are still pending; the current service facade intentionally reports that the runtime is not installed.

## Architecture boundary

- SwiftUI owns presentation and interaction.
- MusicXLXRuntimeServices is the UI-facing contract for catalog, metadata, lyrics, and playback URL resolution.
- LX JavaScript source scripts resolve provider resources; they do not control AVPlayer.
- PlayerStore owns native playback, lock-screen controls, audio-session lifecycle, and playback diagnostics.
- MusicCache and MusicCatalogStore own reusable cache and catalog snapshots.

## Build policy

This branch is under active migration. A successful source commit does not imply an IPA build or device verification.
