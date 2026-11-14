# MusicXLX

MusicXLX is an independent iOS player built around one strict responsibility boundary:

- **LX Music 1.9.2 core**: load and execute source scripts, perform source resolution, and produce the resolved playback result.
- **MusicXLX iOS layer**: provide the compatible runtime boundary, receive the resolved result, and play it with native AVPlayer.

MusicXLX does not reimplement source-provider parsing logic and does not reuse the old MusicX project.

## Current stage

- [x] Create an isolated iOS project scaffold.
- [x] Add an AVPlayer foundation for HTTP(S) audio URLs.
- [ ] Implement the LX custom-source JavaScript runtime compatibility layer.
- [ ] Integrate the required LX 1.9.2 core modules.
- [ ] Pass resolved playback URLs and metadata to AVPlayer.
- [ ] Verify the complete import → execute → resolve → play chain.

## Build

The Xcode project is generated from `project.yml` using XcodeGen. The GitHub Actions workflow is manual and creates an unsigned IPA artifact.
