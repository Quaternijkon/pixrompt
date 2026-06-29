# Pixrompt Standalone Package Notes

This directory is a clean, portable copy of the Flutter app only.

Included:

- Flutter project sources: `lib`, `test`, `android`, `ios`, `macos`, `web`.
- Dependency manifests: `pubspec.yaml`, `pubspec.lock`.
- Flutter metadata and analysis config.
- Optional sync backend sources in `server/` and deployment notes in `deploy/`
  when this repository is moved as a full project.

Excluded:

- `build/`, `.dart_tool/`, `.idea/`, `.gradle/`, `.kotlin/`, `Pods/`, and other generated caches.
- `.flutter-plugins`, `.flutter-plugins-dependencies`.
- `android/local.properties`, because it contains machine-local Android SDK and Flutter SDK paths.
- Internal planning docs that referenced the original local workspace path.

After moving this package:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The app dependencies are declared in `pubspec.yaml` and are resolved from the
Flutter SDK or pub.dev. There are no local filesystem dependencies,
Git-sourced package dependencies, or references to the original workspace
required for normal builds.

The app defaults to the Pixrompt Sync API at:

```text
https://pixrompt.quaternijkon.online/v1
```

The backend is optional for local-only use. When enabling sync, deploy the
backend separately, configure secrets in `/etc/pixrompt/env`, and keep the
plaintext password out of the repository. Do not build Flutter artifacts on the
server-only backend host unless that host also has the proper Flutter and native
toolchains installed.
