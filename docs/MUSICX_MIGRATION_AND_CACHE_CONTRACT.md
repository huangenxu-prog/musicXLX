# MusicXLX — MusicX Experience and Cache Migration

## Source of truth

- UI reference: `huangenxu-prog/MusicX`, branch `home/final-design-asset-pass`.
- Playback, queue, resolver and cache reference: `huangenxu-prog/MusicX`, branch `architecture/three-layer-resource-engine`.
- Target: this repository, branch `integration/musicx-experience-cache`.
- The original MusicX repository is read-only for this migration. No changes are made there.

## Ported in this iteration

The following files were copied byte-for-byte from the MusicX architecture branch:

- `MusicX/MusicSources/MusicCache.swift` → `MusicXLX/Infrastructure/Cache/MusicCache.swift`
- `MusicX/MusicSources/MusicCatalogStore.swift` → `MusicXLX/Infrastructure/Cache/MusicCatalogStore.swift`

No cache behavior or TTL was intentionally changed. `MusicCache` remains an actor-backed disk cache with SHA-256 keys, atomic writes, expiry pruning and a 120 MiB ceiling. `MusicCatalogStore` remains a durable snapshot store under Application Support.

## Playback cache contract to preserve

- Playback resource cache key: `playback-resource|<source>|<sourceID>|<quality>`.
- Playback URL TTL: 5 minutes.
- Artwork data TTL: 7 days.
- Catalog snapshots retain their per-entry refresh interval.
- A failed/expired playback URL is invalidated and freshly resolved; unrelated metadata and catalog caches are not flushed.
- Prefetching the next two queue entries resolves their playback resources in the background. This is URL pre-resolution, not audio-byte prebuffering.

## LX script cache namespace

When custom JS sources are connected, their playback cache namespace must include:

`scriptID|scriptVersion|platform|songID|quality`

This prevents two scripts implementing the same platform from sharing potentially incompatible signed/temporary URLs. Native MusicX cache keys remain unchanged.

## UI migration map

Use `home/final-design-asset-pass` as the visual source of truth for the home/search/library/player presentation. Use `architecture/three-layer-resource-engine` for queue behavior, playback recovery, URL resolution and diagnostics. Port UI and player orchestration only after their model/service dependencies have been mapped; do not copy old native supplier parsing into the new LX runtime.

## Not yet implemented

- Full MusicX UI migration.
- MusicX queue and playback recovery migration.
- Audio-byte prebuffering (current prefetch resolves URLs only).
- LX Runtime integration with the cache resolver.
- Full iOS build and device verification.

No IPA build is triggered by this branch.
