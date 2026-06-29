# Pixrompt Flutter

Cross-platform Pixrompt client for Web, Android, iOS, and macOS.

Pixrompt is an offline-first prompt image gallery. Imported images, prompts,
taxonomy, backups, sync state, and original image bytes are stored locally in
the app-owned store. A self-hosted optional sync backend can be used for
single-user login and gallery synchronization across devices.

## Implemented Scope

- Responsive gallery-first shell with Material 3 navigation rail on wide
  screens and bottom navigation on compact screens.
- Local image import with prompt, category, optional tags, favorite, and private
  flags.
- Search, category/tag filters, favorite filter, and sort modes.
- Archive create, select, copy, merge, and delete.
- Category/tag add, rename, merge-by-rename, category merge, category reorder
  in domain/controller, and safe tag deletion.
- Private library visibility policy with hidden, blurred, and visible tile
  states.
- Detail view with zoom/pan, prompt copy, favorite, edit, delete, same-prompt
  related images, and prompt-edit branches.
- Prompt edit lineage with child images and generation prompt chain support.
- JSON backup export/import with image payloads.
- Local storage cleanup for orphaned image bytes.
- Optional Pixrompt Sync API login and manual sync for prompt records plus
  original image blobs.

## Sync Backend

The default API base URL used by the app is:

```text
https://pixrompt.quaternijkon.online/v1
```

The backend lives under `server/` and provides:

- Single-user email/password login with password hash verification on the
  backend.
- Bearer-token sessions with server-side token hashes.
- SQLite metadata storage for users, sessions, image records, blobs, and sync
  events.
- Filesystem blob storage for original image bytes, addressed by SHA-256.
- Last-write-wins push/pull sync with server event cursors.

Production secrets are not stored in the repository. Configure them in
`/etc/pixrompt/env` on the backend host. Use
`server/scripts/hash_password.py` to generate the password hash from the real
password and keep only the hash in the environment file.

Backend verification:

```bash
python3 -m pytest server/tests -q
```

Deployment notes and the systemd example are in:

```text
deploy/pixrompt-nginx-proxy-manager.md
deploy/pixrompt-api.service.example
```

## Architecture

- `lib/domain`: pure Dart models and business rules.
- `lib/data`: repository interfaces, Hive storage, memory test store, and
  license backend client.
- `lib/app`: `PixromptController` and immutable-ish UI state.
- `lib/ui`: adaptive Flutter UI.
- `lib/platform`: file picking, backup saving, and URL launch adapters.

The app deliberately keeps core behavior out of platform-specific Android code.
Most product decisions are unit-tested without a device or browser.

## Standalone Usage

This package is intended to be moved as an independent Flutter project. It does
not require the original parent workspace or its bundled local Flutter SDK
directory.

Install Flutter on the target machine, make sure `flutter` is on `PATH`, then
run commands from this directory.

## Verify

Run from this directory:

```powershell
flutter pub get
flutter test
flutter analyze
flutter build web
```

Android debug build is available on hosts with Android tooling:

```powershell
flutter build apk --debug
```

iOS and macOS project files are present. Native iOS/macOS compilation requires
Apple tooling.

This repository can be updated and the backend can be deployed on the server
without building Flutter artifacts there. Build Android, web, iOS, or macOS on
a separate machine with the relevant Flutter/native toolchains installed.
