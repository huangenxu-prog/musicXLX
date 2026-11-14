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

## Exact provider method inventory verified in source

The actual method names below were checked in the LX 1.9.2 source files. They are not inferred from filenames.

| Provider | Song search | Charts | Playlist categories/list/detail | Album detail |
|---|---|---|---|---|
| `wy` | `musicSearch.search` | `leaderboard.getBoardsData`, `getList` | `songList.getTags`, `getList`, `getListDetail`, `search` | no separate album module; playlist detail can use `wy/musicDetail.getList` to hydrate missing track data |
| `tx` | `musicSearch.search` | `leaderboard.getBoardsData`, `getList` | `songList.getTags`, `getList`, `getListDetail`, `search` | no album-detail module/method exposed by the `tx` provider |
| `kw` | `musicSearch.search` | `leaderboard.getBoardsData`, `getList` | `songList.getTags`, `getList`, `getListDetail`, `search` | `songList.getListDetail` recognizes `digest-13` and delegates to `album.getAlbumListDetail` |
| `kg` | `musicSearch.search` | `leaderboard.getBoardsData` | `songList.getTags`, `getList`, `getListInfo`, `getSongListRecommend`, `search` | `kg/album.js` contains `getAlbumInfo/getAlbumDetail`, but this module is not imported/exposed by `kg/index.js` in the default provider object |
| `mg` | `musicSearch.search` | `leaderboard.getBoardsData`, `getList` | `songList.getTags`, `getList`, `getListDetail`, `search` | `mg/album.js` contains `getAlbumInfo/getAlbumDetail`, but this module is not imported/exposed by `mg/index.js` in the default provider object |

Notes:
- The leaderboard method is `getBoardsData()`, not `getBoards()`.
- Kugou's default `songList` module uses `getListInfo` and a detail implementation; do not invent a `getListDetail` method for it.
- QQ's `getRecommendList` was not found in the inspected v1.9.2 `tx/songList.js`; do not treat that method as confirmed.
- The album modules for Kugou and Migu exist as source files but are not wired into the default provider exports. They can be reused by explicitly importing them in the extracted bridge, while clearly preserving this distinction.
- NetEase's `songList.getListDetail` can call `musicDetailApi.getList` to hydrate track data when playlist metadata is incomplete.

## Required runtime compatibility layer

The catalog dependency graph uses these facilities from the original app:

- `src/utils/request.js`: `httpFetch` returns `{ promise, cancelHttp }`; resolved response shape includes `body`, `statusCode`, `url`, and headers. JSON parsing is attempted but non-JSON text is preserved. POST `form` is URL-encoded. Some endpoints require raw/binary response handling.
- `src/utils/musicSdk/api-source.js`: playback API lookup is driven by the app setting `common.apiSource` and `global.lx.apis`. This is relevant to playback resolution, not the catalog search/list/chart modules listed above.
- `src/utils/musicSdk/utils.js` and `src/index.js`: shared singer formatting, string decoding, play-time/date/count/size formatting.
- Provider-local crypto/signature modules: notably NetEase `weapi/linuxapi/eapi`, QQ request signing, Kugou signature/compression helpers, Kuwo crypto helpers, and Migu signature helpers.
- Provider modules sometimes import `pako`, Buffer, native crypto functions, and app settings. These must be supplied or replaced by a narrow compatibility adapter; they cannot be assumed to exist in JavaScriptCore.

The catalog bridge must preserve the original `httpFetch` response contract and cancellation behavior. A generic `fetch(url)` wrapper returning only decoded JSON would not be compatible.

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

## Dependency-closure findings from the supplied source archive

A static local-import traversal starting at the five provider `index.js` files found 68 local source files in the default provider dependency graph. This count excludes separate album modules that are not imported by the default provider roots (Kugou and Migu album files), and excludes legacy/temp modules.

The closure reaches these non-relative dependencies:

- `@/store/setting/state`: pulled in through `musicSdk/api-source.js`. Catalog calls should import the individual catalog modules directly rather than provider root indexes where possible; the root index also wires playback API settings, which catalog-only execution does not need.
- `@/utils/nativeModules/crypto`: used by provider crypto helpers. A JavaScriptCore-compatible implementation/bridge is required.
- `@/utils/request`: used by QQ crypto helper; must be mapped to the catalog transport adapter.
- `@/utils/simplify-chinese-main`: reached from shared string decoding.
- `buffer`: used by Kugou utility code.
- `he`: used by shared string decoding.
- `pako`: deflate/inflate support used by request/signature helpers.
- `react-native-background-timer`: used by the original request and Kuwo helper layers.
- `react-native-quick-base64` and `react-native-quick-md5`: native base64/MD5 dependencies.
- `needle` and `request-progress`: imported in the request file but not needed by the active fetch-based catalog path; verify they remain unused in the selected runtime path.
  
This makes the extraction strategy clearer: do not bundle the five provider root indexes wholesale. Bundle the original catalog submodules (search, leaderboard, playlist, and the explicitly needed album/detail modules), their local data-normalization dependencies, and supply narrow runtime shims for request, crypto, Buffer, pako, MD5/base64, and string decoding.

## Transport compatibility contract

The original `httpFetch(url, options)` returns an object with:
- `promise`: resolves to a response object containing `headers`, `body`, `statusCode`, `statusMessage`, `url`, and `ok`.
- `cancelHttp()`: aborts the underlying request.

Request behavior includes GET/POST/HEAD, URL-encoded `form`, JSON bodies, custom headers, timeouts, optional binary response, and response parsing that attempts JSON but preserves non-JSON text. The adapter must preserve these semantics for each original module. A JSON-only request wrapper is insufficient.

## Integration rules

1. Preserve LX provider IDs: `wy`, `tx`, `kw`, `kg`, `mg`.
2. Preserve original provider request/parse logic wherever possible.
3. Replace only platform-specific runtime facilities (HTTP transport, crypto/native modules, app settings) with narrow adapters.
4. Normalize the original provider results into MusicXLX models at the boundary; do not alter the source endpoint logic to fit the UI.
5. Keep精选 and每日推荐 outside this first extraction.
6. Do not trigger a build as part of source extraction.
