# LX Music 1.9.2 Catalog Extraction Inventory

Source baseline: `lx-music-mobile-1.9.2`, supplied by the project owner.
Target: MusicXLX branch `integration/musicx-experience-cache`.

This inventory records the existing LX Music catalog modules to be reused. It is not a claim that these modules are already executable in MusicXLX.

## Reusable catalog capabilities found in LX 1.9.2

| Provider | Search | Charts | Playlist taxonomy/list/detail | Album detail |
|---|---|---|---|---|
| NetEase (`wy`) | `musicSearch.search` | `leaderboard.getBoardsData/getList` | `songList.getTags/getList/getListDetail/search` | no standalone album module; playlist detail may hydrate missing tracks through `musicDetail.getList` |
| QQ Music (`tx`) | `musicSearch.search` | `leaderboard.getBoardsData/getList` | `songList.getTags/getList/getListDetail/search` | no album-detail module/method exposed by the provider |
| Kuwo (`kw`) | `musicSearch.search` | `leaderboard.getBoardsData/getList` | `songList.getTags/getList/getListDetail/search` | `songList.getListDetail` delegates album IDs to `album.getAlbumListDetail` |
| Kugou (`kg`) | `musicSearch.search` | `leaderboard.getBoardsData` | `songList.getTags/getList/getListInfo/getSongListRecommend/search` | separate `album.js` has `getAlbumInfo/getAlbumDetail`, not wired by default provider index |
| Migu (`mg`) | `musicSearch.search` | `leaderboard.getBoardsData/getList` | `songList.getTags/getList/getListDetail/search` | separate `album.js` has `getAlbumInfo/getAlbumDetail`, not wired by default provider index |

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

- `src/utils/request.js`: `httpFetch` returns `{ promise, cancelHttp }`; resolved response shape includes `body`, `statusCode`, `statusMessage`, `url`, `ok`, and headers. JSON parsing is attempted but non-JSON text is preserved. POST `form` is URL-encoded. Binary responses are converted from Blob to Buffer.
- The request helper's special `bHh` header transformation is conditional: it runs only when a caller passes that obfuscated header key. The inspected five-provider catalog modules do not import `musicSdk/options.js`'s `headers` constant, so this transformation is not currently evidenced as a requirement for their catalog calls. Keep it out of the initial shim unless a selected source module is found to pass that key.
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

## Crypto compatibility details verified against LX 1.9.2 Android implementation

The provider crypto imports are not generic asynchronous-only APIs. The original crypto.ts exposes synchronous AES and RSA methods used directly while constructing catalog request parameters:

- aesEncryptSync(text, key, iv, mode) and aesDecryptSync(...) accept Base64-encoded text/key/IV and return the encrypted Base64 string or decrypted UTF-8 string.
- AES modes used by the SDK are AES/CBC/PKCS7Padding and AES. The Android implementation passes the mode string directly to Java Cipher.getInstance; on Android's default provider, the bare AES transformation resolves to ECB with PKCS5 padding (not ECB/NoPadding). The source enum calls this ECB_128_NoPadding, but that enum label does not match the actual Java provider default and must not be trusted as the runtime behavior.
- rsaEncryptSync(text, publicKey, padding) accepts Base64 plaintext and a Base64 DER public key, returning Base64 ciphertext. NetEase uses RSA/ECB/NoPadding.
- hashSHA1(text) is asynchronous and returns a lowercase hexadecimal SHA-1 digest; QQ's zzcSign awaits it before building the request signature.
- NetEase imports btoa from react-native-quick-base64; MD5 is provided by the provider's toMD5 helper, which depends on react-native-quick-md5.

The supplied LX source archive includes the Android implementation in android/app/src/main/java/cn/toside/music/mobile/crypto/{CryptoModule,AES,RSA}.java. AES takes Base64-encoded input/key/IV, truncates or zero-pads the IV to 16 bytes for the IV-taking overload, and emits unwrapped Base64 ciphertext; decryption emits UTF-8. The Java implementation catches cipher exceptions and returns an empty string. RSA takes Base64 plaintext and X.509 SubjectPublicKeyInfo public-key DER, then emits unwrapped Base64 ciphertext. These semantics are the compatibility reference; do not substitute WebCrypto defaults without matching input/output encoding, padding, and RSA behavior. The current MusicXLX JavaScriptCore bridge still has no crypto exports, so NetEase and QQ signed catalog requests cannot yet be considered runnable.

## MusicXLX native crypto adapter implementation

Added `MusicXLX/Infrastructure/Catalog/LXCatalogCryptoBridge.swift` and installed it when the JavaScriptCore context is created. It currently exposes `LXNativeCrypto.aesEncryptSync`, `aesDecryptSync`, `rsaEncryptSync`, `sha1`, and `md5`. The JS import adapters are `Resources/LXRuntime/lx-native-crypto-shim.js` (alias target for `@/utils/nativeModules/crypto`) and `lx-quick-md5-shim.js` (alias target for `react-native-quick-md5`).

Implementation details:
- AES uses CommonCrypto and matches the Android source's Base64 input/output contract. The literal mode `AES` is treated as ECB + PKCS7 padding, equivalent to Android's default AES/ECB/PKCS5Padding for AES's 16-byte block size. CBC IV bytes are zero-padded/truncated to 16 bytes as in the Android source.
- RSA public-key input is X.509 SubjectPublicKeyInfo DER; the adapter extracts the embedded PKCS#1 key before importing it through Security. It maps `RSA/ECB/NoPadding` to the platform raw RSA algorithm and OAEP-SHA1 to the platform OAEP-SHA1 algorithm.
- SHA-1 and MD5 return lowercase hexadecimal digests over UTF-8 bytes. MD5 is needed by NetEase eAPI and other provider signatures.
- The JavaScript shim exposes only catalog-used synchronous methods; unsupported key-generation/decryption/async variants fail explicitly rather than returning placeholder values.

Status: source and bridge wiring are committed, but no Xcode compile or cryptographic test vectors have been run yet. In particular, raw RSA interoperability, Security key import, CommonCrypto mode parity, and the React Native MD5/Base64 edge cases remain unverified on iOS. Do not yet mark NetEase/QQ/Kuwo provider requests as live-tested.

### Buffer call-site audit against the supplied v1.9.2 source

The selected provider source uses the following concrete Buffer operations: `from`, `alloc`, `concat`, `isBuffer`, `slice`, `subarray`, `toString` (`utf8`, `base64`, `hex`), `reverse`, `indexOf`, and indexed byte mutation. `reverse`, `indexOf`, and indexed mutation are inherited from `Uint8Array`; `subarray` must share the original backing storage because Kuwo's lyric decoder mutates bytes returned by `subarray`. The shim preserves the view semantics of both `subarray()` and Node `Buffer.slice()` (both share the backing store), while `Buffer.from(existingBuffer)` remains a copy. The Base64 decoder also keeps its accumulator bounded across long inputs. A Node regression test file now covers these semantics and common encodings, but it has been added—not executed—so this remains an unverified source-level correction until the test is run against the checked-out repository and the full provider corpus.

## Buffer compatibility scope

The supplied LX 1.9.2 source uses the Node Buffer surface in several provider helpers, including Base64/hex decoding, UTF-8 conversion, byte-array construction, slicing, reversing, concatenation, and fixed-size allocation. The first MusicXLX shim is intentionally limited to the operations observed in the selected catalog dependency graph; it is not a complete Node Buffer replacement. It is loaded as an app resource before the provider bundle. The `buffer` package import still needs to be aliased to this global in the reproducible bundle step.

Observed call sites include Kugou's `util.js` and `lyric.js`, Kuwo's lyric decoder, QQ's QRC decoder and crypto helper, Migu's MRC utility, and NetEase's crypto helper. Do not mark a provider's entire feature set supported solely because the shim loads: verify each selected module's actual Buffer calls and pako requirements.

pako remains a separate dependency. The LX source uses `inflate` and `constants` in QQ lyric decoding, `inflate` in Kuwo lyric decoding, and `inflate` in Kugou utility code. It must be bundled from the pinned LX 1.9.2 dependency (`pako` 2.1.x), not replaced with a no-op or a platform-specific guess.

## Transport compatibility contract

The original `httpFetch(url, options)` returns an object with:
- `promise`: resolves to a response object containing `headers`, `body`, `statusCode`, `statusMessage`, `url`, and `ok`.
- `cancelHttp()`: aborts the underlying request.

Request behavior includes GET/POST/HEAD, URL-encoded `form`, JSON bodies, custom headers, timeouts, optional binary response, and response parsing that attempts JSON but preserves non-JSON text. The adapter must preserve these semantics for each original module. A JSON-only request wrapper is insufficient.

## MusicXLX native transport foundation

Added `MusicXLX/Infrastructure/Catalog/LXCatalogHTTPTransport.swift`.

It provides:
- URLSession-backed GET/POST/HEAD-compatible request construction.
- URL-encoded form bodies and caller-supplied raw body bytes.
- Request headers, timeout, and cache policy.
- Raw response bytes plus UTF-8 text and optional JSON decoding.
- HTTP status, response headers, final URL, and task cancellation.

This is a native transport foundation only. It does not yet expose LX's JavaScript `httpFetch(url, options) -> { promise, cancelHttp }` shape to JavaScriptCore, and no original provider module has been bundled or invoked yet. The next integration step is the JSCore async callback bridge, then loading the original catalog modules against this transport.

## JavaScriptCore asynchronous bridge foundation

Added `MusicXLX/Infrastructure/Catalog/LXCatalogJavaScriptRuntime.swift`.

- Keeps each JavaScriptCore context on a dedicated serial queue.
- Exposes a native async HTTP function to JavaScript and resumes Promise callbacks on the JS queue.
- Exposes cancellation for individual requests.
- Adds a Promise-aware export invocation mechanism so async provider methods can return resolved JSON results to Swift.
- Exposes the original request helper name `httpFetch` as an alias for the transport shim, with the same outer shape `{ promise, cancelHttp }`.

Important current limitations:
- The actual LX provider source modules are not bundled into the app yet.
- This first shim does not yet implement the full original `request.js` preprocessing behavior (notably multipart `formData` and binary Blob-to-Buffer conversion). The special `bHh` transformation is conditional and is not currently used by the inspected catalog modules.
- Crypto/native modules, Buffer, pako, React Native timer APIs, and the shared LX utility aliases are not yet fully adapted.
- Therefore the runtime foundation is not yet sufficient to claim any LX catalog provider is runnable. The next work is to close these compatibility gaps and produce a reproducible bundle from the supplied 1.9.2 source.

## Integration rules

1. Preserve LX provider IDs: `wy`, `tx`, `kw`, `kg`, `mg`.
2. Preserve original provider request/parse logic wherever possible.
3. Replace only platform-specific runtime facilities (HTTP transport, crypto/native modules, app settings) with narrow adapters.
4. Normalize the original provider results into MusicXLX models at the boundary; do not alter the source endpoint logic to fit the UI.
5. Keep精选 and每日推荐 outside this first extraction.
6. Do not trigger a build as part of source extraction.
