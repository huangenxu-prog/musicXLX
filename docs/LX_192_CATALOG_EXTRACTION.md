# LX Music 1.9.2 Catalog Extraction Inventory

Source baseline: `lx-music-mobile-1.9.2`, supplied by the project owner.
Target: MusicXLX branch `integration/musicx-experience-cache`.

This inventory records the existing LX Music catalog modules to be reused. It is not a claim that these modules are already executable in MusicXLX.

## Reusable catalog capabilities found in LX 1.9.2

| Provider | Search | Charts | Playlist taxonomy/list/detail | Album detail |
|---|---|---|---|---|
| NetEase (`wy`) | `musicSearch.search` | `leaderboard.getBoards/getList` | `songList.getTags/getList/getListDetail/search` | no standalone album-detail provider method found in the provider entry point; verify before exposing |
| QQ Music (`tx`) | `musicSearch.search` | `leaderboard.getBoards/getList` | `songList.getTags/getList/getListDetail/search`; `getRecommendList` is playlist-square data | no standalone album-detail provider method found |
| Kuwo (`kw`) | `musicSearch.search` | `leaderboard.getBoards/getList` | `songList.getTags/getList/getListDetail/search` | `album.getAlbumListDetail` |
| Kugou (`kg`) | `musicSearch.search` | `leaderboard.getBoards/getList` | `songList.getTags/getList/getListDetail/search`; `getSongListRecommend` | `album.getAlbumInfo/getAlbumDetail` |
| Migu (`mg`) | `musicSearch.search` | `leaderboard.getBoards/getList` | `songList.getTags/getList/getListDetail/search` | `album.getAlbumDetail/getAlbumInfo` |

The app-level registration in `src/utils/musicSdk/index.js` includes `kw`, `kg`, `tx`, `wy`, and `mg`. The Baidu provider is commented out in the registry and is not part of the initial extraction. `xm` is an additional source module, not one of the five catalog providers above.

## Explicit exclusions for the first pass

- Curated/精选 home feed.
- Daily recommended songs.

These are not to be fabricated from playlist-square or chart results. They remain separate product features to be adapted later.

## Reuse boundary

The source modules contain the platform request, signing/encryption, response parsing, and normalization logic. MusicXLX should reuse those original modules rather than reimplementing platform endpoints.

The source modules are not standalone JavaScript files. Their dependency closure includes the LX `httpFetch` request layer, shared SDK helpers, crypto/base64/MD5 adapters, and in some providers React Native-specific imports. MusicXLX currently has a separate JavaScriptCore custom-source runtime; it does not automatically load LX's internal `musicSdk` module graph. A catalog runtime/adapter must therefore provide compatible dependencies before the original provider modules can execute.

## Source entry points inspected

- `src/utils/musicSdk/index.js`
- `src/utils/musicSdk/{wy,tx,kw,kg,mg}/index.js`
- Each provider's `leaderboard.js`, `songList.js`, `musicSearch.js`
- `kw/album.js`, `kg/album.js`, `mg/album.js`
- `src/utils/request.js`
- `src/utils/musicSdk/api-source.js`

## Integration rules

1. Preserve LX provider IDs: `wy`, `tx`, `kw`, `kg`, `mg`.
2. Preserve original provider request/parse logic wherever possible.
3. Replace only platform-specific runtime facilities (HTTP transport, crypto/native modules, app settings) with narrow adapters.
4. Normalize the original provider results into MusicXLX models at the boundary; do not alter the source endpoint logic to fit the UI.
5. Keep精选 and每日推荐 outside this first extraction.
6. Do not trigger a build as part of source extraction.
