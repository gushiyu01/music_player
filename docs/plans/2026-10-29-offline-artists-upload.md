# Singer folders, offline music and upload implementation plan

> Execute in this session using the existing clean workspace. User has authorized implementation, publishing and a final WeCom notification.

**Goal:** Browse singer directories, stream or download songs, play offline, and upload phone audio into the selected Baidu folder.

**Architecture:** Flutter talks directly to Baidu HTTPS APIs. A configurable music root opens its real child directories as singer cards; nested album directories remain navigable. App-private persistent files and a local manifest provide offline playback without a token. A serial transfer queue reports progress, cancellation and errors; partial downloads are never playable. Upload uses precreate, sequential 4 MiB parts with MD5 verification, and create with rtype=0 so existing files are not overwritten.

**Tech Stack:** Existing Flutter/audio_service/just_audio/http; file_picker and path_provider; crypto for file identifiers and upload MD5. Source inspection found that file_selector_android reads all bytes before returning a selection; file_picker's cached-file XFile is used instead to keep large audio reads bounded.

## 1. Protocol and local storage

- Extend `lib/data/baidu_client.dart` with cancellable POST form calls, folder creation and uploads. Check file names, block indexes, hashes, response shape, authorization generation and cancellation before final create. Upload errors must not expose token URLs. Use rtype=0 in both precreate and create.
- Add `lib/data/transfer_control.dart` for request abortion and cooperative cancellation.
- Add `lib/data/offline_library.dart` with a manifest containing metadata and byte counts, derived safe file names, incomplete-file cleanup, verification on restart, and local lookup. Store no absolute paths or credentials in the manifest.
- Add `lib/data/transfer_manager.dart` with a serial queue, progress, explicit retry and cancel. Persist completed downloads only. Downloads of bundled demo audio exercise the same disk path without account credentials.
- Test exact upload bodies, sequential slices, MD5 mismatch, collisions, cancellation before create, failed downloads, persistence and cleanup in `test/transfer_test.dart` and `test/offline_library_test.dart`.

## 2. Player and controller

- Resolve verified local files in `lib/playback/music_handler.dart` before network sources; expose explicit online override per queue. Keep offline queue restoration when disconnected.
- Initialize the library and transfer manager in `lib/main.dart`, inject them into `lib/app_controller.dart` and the player.
- Remember music root separately from last visited folder. Stop transfers when disconnecting; retain downloaded songs and their local metadata.

## 3. Screens

- Update `lib/ui/home_screen.dart`: singer folder cards, remembered root, folder navigation, local downloads tab, per-song download/online/remove actions, upload to current directory and create singer folder. Preserve mini-player and search/favorites.
- Add `lib/ui/transfers_screen.dart`: pending/active/completed/failed transfers, progress, cancel and retry. Explain that this MVP requires keeping the app running for transfers.
- Upload uses the OS file chooser with multiple audio selection; show the destination before selection. Root setting and new-folder dialogs need input validation, not additional approval prompts.

## 4. Verify and publish

- Run pinned Flutter `pub get`, Dart format, Flutter analyze and tests locally. Version 0.2.0.
- Extend `tools/android_smoke.py` to download demo audio, restart the app, disable network and play the local file, then verify existing background/system controls and queue.
- Push to main, wait for GitHub Actions quality, Android APK, Android smoke and iOS unsigned build. Fix actual failures until green.
- Update README, release notes and validation evidence; publish v0.2.0 from the verified run and notify through the authorized WeCom skill.

## Limits to report

Real Baidu directory permissions, quota, speed and upload success require the user's own authorization and are not established by mocked protocol tests. Downloads are app-managed and removed on uninstall. Transfer resumption after process termination and public Downloads export are outside this increment; incomplete transfers can be retried. iOS has no installation signing credentials.

## Primary references

- Baidu SDK upload: https://github.com/baidu-netdisk/baidu-drive-sdk-go/tree/main/baidudriver/api
- File picker: https://pub.dev/packages/file_picker
- Flutter application data paths: https://pub.dev/packages/path_provider
