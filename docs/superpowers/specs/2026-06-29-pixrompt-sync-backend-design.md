# Pixrompt Sync Backend Design

## Status

Approved by the user on 2026-06-29.

## Goal

Add a self-hosted Pixrompt backend on this machine so Flutter clients built on
other machines, including Android builds, can log in over HTTPS and sync the
complete personal gallery through `https://pixrompt.quaternijkon.online/v1`.
The Flutter app must remain offline-first, must not require local data
recreation after upgrades, and must not be built on this machine.

## Non-Goals

- Do not add multi-user registration in this iteration.
- Do not commit plaintext passwords, password hashes, tokens, or production
  environment files.
- Do not replace the existing Hive storage boxes or require destructive local
  migrations.
- Do not build Flutter artifacts on this machine.
- Do not make sync depend on a Flutter Web deployment.

## Selected Approach

Use FastAPI, SQLite, and filesystem blob storage.

The backend lives under `server/` in this repository, runs locally through a
systemd service, and is exposed through the existing HAProxy and Nginx Proxy
Manager public HTTPS path. SQLite stores users, auth/session metadata,
sync envelopes, deletion tombstones, and blob indexes. Image bytes are stored as
deduplicated files under a server data directory.

This approach is intentionally small for a single personal account while still
leaving a migration path to PostgreSQL later.

## Public Endpoint

- API base URL: `https://pixrompt.quaternijkon.online/v1`
- Public health checks:
  - `https://pixrompt.quaternijkon.online/health`
  - `https://pixrompt.quaternijkon.online/v1/health`
- Local service health check: `http://127.0.0.1:<port>/health`

Nginx Proxy Manager should forward the full host to the backend. The backend
handles `/v1/*` itself instead of requiring path rewriting in the reverse proxy.

## Authentication

The first release is single-user only.

Configuration is environment-driven:

- `PIXROMPT_USER_EMAIL`: allowed login email.
- `PIXROMPT_PASSWORD_HASH`: password hash generated at deploy time.
- `PIXROMPT_TOKEN_SECRET`: random secret for signed bearer tokens.
- `PIXROMPT_TOKEN_TTL_SECONDS`: token lifetime.
- `PIXROMPT_DATABASE_PATH`: SQLite database path.
- `PIXROMPT_BLOB_DIR`: blob storage directory.

The repository may include `.env.example`, but it must not include the real
email if avoidable, the plaintext password, the generated password hash, token
secrets, or production environment files.

Auth endpoints:

- `POST /v1/auth/login`
  - Input: `{ "email": "...", "password": "...", "deviceId": "..." }`
  - Output: bearer token, expiration, normalized account email.
- `POST /v1/auth/logout`
  - Invalidates the current token when possible.
- `GET /v1/auth/session`
  - Confirms the current token and account identity.

All sync and blob endpoints require `Authorization: Bearer <token>`.

## Current Local Data Compatibility

The current Flutter app stores:

- `pixrompt_records`: JSON for image records and settings.
- `pixrompt_image_bytes`: image bytes keyed by `imageKey`.

These boxes must stay in place.

`PromptImageItem.uid` remains the stable cross-device image identifier. The
existing `createdAt` and `updatedAt` millisecond timestamps remain the local
maintenance timestamps.

The image model may gain optional maintenance fields:

- `originalFileName`
- `contentSha256`
- `mimeType`
- `importedAt`
- `lastSyncedAt`

All added fields must be optional and backward-compatible. Older local records
that lack these fields must still load through `PromptImageItem.fromJson`.

If future payloads contain an `id` field, the client may map it to `uid`, but
the internal model should continue to use `uid` to avoid splitting identity.

## Server Data Model

The server stores a sync envelope around the existing client record JSON.
Server-specific sync state is not forced into the Flutter domain model.

Core tables:

- `users`
  - `id`
  - `email`
  - `created_at`
- `sessions`
  - `id`
  - `user_id`
  - `token_hash`
  - `device_id`
  - `expires_at`
  - `revoked_at`
  - `created_at`
- `images`
  - `user_id`
  - `image_uid`
  - `record_json`
  - `image_key`
  - `content_sha256`
  - `server_version`
  - `deleted_at`
  - `created_at`
  - `updated_at`
  - `server_updated_at`
- `blobs`
  - `sha256`
  - `size_bytes`
  - `mime_type`
  - `storage_path`
  - `created_at`
- `sync_events`
  - `id`
  - `user_id`
  - `entity_type`
  - `entity_id`
  - `server_version`
  - `event_json`
  - `created_at`

The `sync_events.id` value acts as a monotonically increasing cursor for
incremental pull.

## Sync API

### `POST /v1/sync/pull`

Input:

```json
{
  "deviceId": "device-id",
  "cursor": 0,
  "knownBlobSha256": ["..."]
}
```

Output:

```json
{
  "cursor": 12,
  "serverTime": 1782748800000,
  "changes": [
    {
      "type": "upsert",
      "imageUid": "image-uid",
      "serverVersion": 3,
      "updatedAt": 1782748800000,
      "record": {},
      "blob": {
        "sha256": "...",
        "imageKey": "image-key",
        "sizeBytes": 123
      }
    }
  ],
  "deleted": [
    {
      "imageUid": "image-uid",
      "serverVersion": 4,
      "deletedAt": 1782748800000
    }
  ],
  "missingBlobs": ["sha256-needed-by-client"]
}
```

### `POST /v1/sync/push`

Input:

```json
{
  "deviceId": "device-id",
  "baseCursor": 10,
  "images": [
    {
      "imageUid": "image-uid",
      "baseServerVersion": 2,
      "updatedAt": 1782748800000,
      "record": {},
      "blob": {
        "sha256": "...",
        "imageKey": "image-key",
        "sizeBytes": 123,
        "mimeType": "image/png"
      }
    }
  ],
  "deleted": [
    {
      "imageUid": "image-uid",
      "baseServerVersion": 2,
      "deletedAt": 1782748800000
    }
  ]
}
```

Output:

```json
{
  "cursor": 13,
  "serverTime": 1782748800000,
  "accepted": [
    {
      "imageUid": "image-uid",
      "serverVersion": 3
    }
  ],
  "rejected": [],
  "missingBlobs": ["sha256-to-upload-before-next-sync"]
}
```

### Blob Endpoints

- `HEAD /v1/blobs/{sha256}`
- `PUT /v1/blobs/{sha256}`
- `GET /v1/blobs/{sha256}`

Blob uploads verify that the body SHA-256 matches the path. Existing blobs are
deduplicated and not overwritten with different content.

## Conflict Policy

Use last-write-wins for this single-user personal workflow.

For each image:

1. Match records by `uid`.
2. If the client `baseServerVersion` matches the current server version, accept
   the client change.
3. If the server version changed, compare `updatedAt` or `deletedAt`.
4. The newest timestamp wins.
5. If timestamps tie, the server version wins to avoid repeated overwrite loops.
6. Deletes are tombstones and participate in the same timestamp comparison.

The server always increments `server_version` for accepted changes and appends a
sync event so other devices can pull the result.

## Flutter Client Changes

New Dart modules:

- `lib/domain/sync_models.dart`
  - JSON models for auth, sync pull, sync push, blob references, and sync
    status.
- `lib/data/pixrompt_api_client.dart`
  - HTTP client for login, session validation, pull, push, and blob transfer.
- `lib/data/sync_state_repository.dart`
  - Local persistence for API base URL, token, token expiration, device ID,
    sync cursor, known server versions, and delete tombstones.
- `lib/app/pixrompt_sync_controller.dart`
  - Coordinates login, logout, pull, push, full sync, status, and user-visible
    error messages.
- `lib/ui/account_sync_sheet.dart`
  - Settings sheet content for account login and sync controls.

Existing modules to modify:

- `lib/domain/prompt_image.dart`
  - Add optional maintenance fields and backward-compatible JSON handling.
- `lib/app/pixrompt_controller.dart`
  - Expose methods needed by sync for applying remote upserts/deletes and
    reading local records without coupling the gallery controller to HTTP.
- `lib/app/pixrompt_state.dart`
  - Add sync status only if needed for existing UI messages.
- `lib/data/hive_pixrompt_repository.dart`
  - Keep existing boxes; add sync-state box or key through a separate
    repository.
- `lib/data/memory_pixrompt_repository.dart`
  - Preserve test support for image and settings data.
- `lib/main.dart`
  - Initialize sync state and API client without blocking gallery startup.
- `lib/ui/settings_sheet.dart`
  - Add the "Account and Sync" section and open the sync sheet.
- `pubspec.yaml`
  - Add only necessary dependencies, expected to include an HTTP client and
    crypto hashing support.

## Sync Flow

On app startup:

1. Load local gallery from Hive as today.
2. Load sync state from the separate sync-state store.
3. Do not block the gallery on network availability.
4. If a valid token exists, the UI may show "signed in" and allow manual sync.

On login:

1. User enters API base URL, email, and password in the settings sheet.
2. Client posts to `/v1/auth/login`.
3. Client saves token, expiration, normalized email, and device ID.
4. Password is not persisted.

On manual sync:

1. Push local unsynced upserts and tombstones.
2. Upload missing blobs reported by the server.
3. Pull remote changes since the local cursor.
4. Download missing blobs required by pulled records.
5. Apply remote upserts/deletes to the existing repository.
6. Save the new cursor and known server versions.
7. Show success, partial failure, or error status in the settings UI.

Automatic background sync is not required for the first release. Manual sync is
enough for a predictable personal tool.

## UI Requirements

The UI remains consistent with the existing dark Material 3 Pixrompt shell and
with the design-system guidance gathered for this work:

- Keep the gallery as the first screen.
- Add account and sync controls inside Settings instead of a landing page.
- Use labeled form fields; do not rely on placeholders only.
- Disable login/sync buttons while requests are in progress.
- Show loading indicators for network operations that take more than 300 ms.
- Display explicit success and error messages.
- Keep touch targets at least 48 dp.
- Use Material icons, not emoji, for sync/account actions.
- Respect safe areas and existing sheet padding.

## Deployment Requirements

Local deployment on this machine should include:

- A Python virtual environment or equivalent isolated install under the project
  or server deployment path.
- A production environment file outside Git, such as `/etc/pixrompt/env`.
- A systemd service, such as `pixrompt-api.service`.
- A SQLite database path outside Git.
- A blob storage path outside Git.
- NPM public host `pixrompt.quaternijkon.online` with HTTPS.
- `/root/管理员手册.md` updated with endpoint, original port, account notes,
  paths, and management commands.

Deployment verification must check:

- `systemctl is-active pixrompt-api.service`
- `curl http://127.0.0.1:<port>/health`
- `curl https://pixrompt.quaternijkon.online/health`
- `curl https://pixrompt.quaternijkon.online/v1/health`
- Unauthorized sync returns 401.
- Login with the configured account returns a token.

## Testing Requirements

Backend tests:

- Configuration rejects missing secrets.
- Login succeeds with the configured email and password.
- Login rejects wrong email and wrong password.
- Protected endpoints reject missing and invalid tokens.
- Blob upload verifies SHA-256.
- Blob upload deduplicates existing content.
- Sync push accepts new records.
- Sync pull returns records after a cursor.
- Tombstone delete propagates through pull.
- Last-write-wins chooses the newer timestamp.
- Tied timestamps keep the server version.

Flutter tests:

- `PromptImageItem.fromJson` accepts old records without new optional fields.
- `PromptImageItem.toJson` includes optional maintenance fields only when set or
  handles nulls consistently.
- Sync models parse login and sync responses.
- API client builds `/v1` URLs correctly from `https://pixrompt.quaternijkon.online/v1`.
- Sync controller saves token state after login and clears it after logout.
- Sync controller applies remote upserts and tombstones without replacing Hive
  box names.
- Settings UI exposes labeled email, password, base URL, login, logout, and
  sync controls.

Verification may run `flutter test` and `flutter analyze` if the local Flutter
toolchain is available, but must not run `flutter build`.

## Security and Privacy Notes

- Do not commit production secrets.
- Do not log plaintext passwords or bearer tokens.
- Avoid logging full prompt or image metadata in server request logs.
- Password hashing should use a slow password hash implementation available in
  Python dependencies.
- Token storage on Flutter should use the best available local persistence for
  this project without requiring platform-specific setup that breaks builds.

## Acceptance Criteria

- GitHub contains the backend source, Flutter client changes, tests, and safe
  deployment templates.
- This machine runs the backend behind `https://pixrompt.quaternijkon.online/v1`.
- The configured single user can log in.
- A client can sync prompt records and original image bytes through the backend.
- Existing local Pixrompt data remains readable without user data recreation.
- The repository does not contain plaintext passwords, password hashes, bearer
  tokens, production environment files, SQLite databases, or blob payloads.
- Flutter app artifacts are not built on this machine.
