# Pixrompt Sync Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and deploy a self-hosted single-user Pixrompt sync backend and add Flutter client support for complete gallery sync without rebuilding Flutter on this machine.

**Architecture:** Add a FastAPI backend under `server/` with SQLite metadata, filesystem blob storage, bearer-token auth, and `/v1` sync/blob APIs. Add a Flutter sync client and settings-sheet UI that preserve the existing Hive gallery boxes and sync prompt records plus original image bytes through `https://pixrompt.quaternijkon.online/v1`.

**Tech Stack:** Python 3, FastAPI, SQLite, pytest, systemd, Nginx Proxy Manager, Dart/Flutter, Hive, `http`, `crypto`.

---

## File Structure

Backend files:

- Create `server/requirements.txt` with FastAPI, uvicorn, pydantic, passlib, bcrypt, itsdangerous, python-dotenv, pytest, httpx.
- Create `server/app/__init__.py`.
- Create `server/app/config.py` for environment loading and validation.
- Create `server/app/security.py` for password verification, token creation, token hashing, and token validation.
- Create `server/app/db.py` for SQLite schema creation and connection helpers.
- Create `server/app/blob_store.py` for SHA-256 verified filesystem blobs.
- Create `server/app/schemas.py` for Pydantic request/response models.
- Create `server/app/auth.py` for login, logout, session dependencies, and token persistence.
- Create `server/app/sync.py` for pull, push, last-write-wins, and sync events.
- Create `server/app/main.py` for FastAPI app and route registration.
- Create `server/scripts/hash_password.py` for generating the production password hash.
- Create `server/.env.example` with safe placeholder values only.
- Create backend tests under `server/tests/`.

Flutter files:

- Modify `pubspec.yaml` and `pubspec.lock` to add `http` and `crypto`.
- Modify `lib/domain/prompt_image.dart` to add optional maintenance fields.
- Create `lib/domain/sync_models.dart` for sync/auth JSON models.
- Create `lib/data/pixrompt_api_client.dart` for HTTP API and blob calls.
- Create `lib/data/sync_state_repository.dart` for sync state persistence.
- Create `lib/app/pixrompt_sync_controller.dart` for login, logout, and manual sync orchestration.
- Modify `lib/app/pixrompt_controller.dart` to expose sync-safe apply/upsert/delete helpers.
- Modify `lib/main.dart` to initialize sync state and controller without blocking gallery startup.
- Modify `lib/ui/settings_sheet.dart` to surface account and sync controls.
- Create `lib/ui/account_sync_sheet.dart`.
- Add tests under `test/domain/`, `test/data/`, `test/app/`, and `test/ui/`.

Deployment and docs files:

- Create `deploy/pixrompt-api.service.example`.
- Create `deploy/pixrompt-nginx-proxy-manager.md`.
- Modify `.gitignore` to exclude server databases, blob payloads, virtualenvs, and production env files.
- Modify `README.md` and `STANDALONE_PACKAGE.md` to document sync backend configuration and the no-local-build workflow.
- Update `/root/管理员手册.md` after live deployment, not as a committed repository file.

---

## Task 1: Backend API

**Files:**
- Create: `server/requirements.txt`
- Create: `server/app/__init__.py`
- Create: `server/app/config.py`
- Create: `server/app/security.py`
- Create: `server/app/db.py`
- Create: `server/app/blob_store.py`
- Create: `server/app/schemas.py`
- Create: `server/app/auth.py`
- Create: `server/app/sync.py`
- Create: `server/app/main.py`
- Create: `server/scripts/hash_password.py`
- Create: `server/.env.example`
- Create: `server/tests/conftest.py`
- Create: `server/tests/test_auth.py`
- Create: `server/tests/test_blob_store.py`
- Create: `server/tests/test_sync.py`
- Modify: `.gitignore`

- [ ] **Step 1: Write failing backend tests**

Create tests for config validation, login, token protection, blob SHA-256 validation, blob deduplication, push, pull, tombstone propagation, last-write-wins, and tied timestamp behavior.

Run:

```bash
cd /root/pixrompt
python3 -m pytest server/tests -q
```

Expected before implementation: pytest cannot import `server.app.main` or related modules.

- [ ] **Step 2: Implement backend dependencies and config**

Create `server/requirements.txt`:

```text
fastapi==0.115.6
uvicorn[standard]==0.34.0
pydantic==2.10.4
passlib[bcrypt]==1.7.4
itsdangerous==2.2.0
python-dotenv==1.0.1
pytest==8.3.4
httpx==0.28.1
```

Create config that reads these required variables:

```text
PIXROMPT_USER_EMAIL
PIXROMPT_PASSWORD_HASH
PIXROMPT_TOKEN_SECRET
PIXROMPT_DATABASE_PATH
PIXROMPT_BLOB_DIR
```

Default optional values:

```text
PIXROMPT_TOKEN_TTL_SECONDS=2592000
PIXROMPT_BASE_PATH=/v1
```

- [ ] **Step 3: Implement SQLite schema and migrations**

Initialize tables `users`, `sessions`, `images`, `blobs`, and `sync_events`. Add idempotent schema setup in `server/app/db.py`, and ensure the configured single user is present.

- [ ] **Step 4: Implement auth routes**

Implement:

```text
GET  /health
GET  /v1/health
POST /v1/auth/login
POST /v1/auth/logout
GET  /v1/auth/session
```

Login accepts email, password, and device ID. It verifies the password against `PIXROMPT_PASSWORD_HASH`, stores a hashed session token, and returns a bearer token plus expiration.

- [ ] **Step 5: Implement blob routes**

Implement:

```text
HEAD /v1/blobs/{sha256}
PUT  /v1/blobs/{sha256}
GET  /v1/blobs/{sha256}
```

`PUT` must verify the uploaded body SHA-256 matches the path and must write blobs under a prefix directory based on the hash.

- [ ] **Step 6: Implement sync routes**

Implement:

```text
POST /v1/sync/pull
POST /v1/sync/push
```

Use `sync_events.id` as the cursor. Use `image_uid` identity. Preserve the client record JSON in `images.record_json`. Implement last-write-wins with server tie-break.

- [ ] **Step 7: Run backend tests**

Run:

```bash
cd /root/pixrompt
python3 -m pytest server/tests -q
```

Expected after implementation: all backend tests pass.

- [ ] **Step 8: Commit backend API**

```bash
git add .gitignore server
git commit -m "feat: add pixrompt sync backend api"
```

---

## Task 2: Flutter Sync Domain And Data Layer

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `lib/domain/prompt_image.dart`
- Create: `lib/domain/sync_models.dart`
- Create: `lib/data/pixrompt_api_client.dart`
- Create: `lib/data/sync_state_repository.dart`
- Modify: `lib/data/hive_pixrompt_repository.dart`
- Modify: `lib/app/pixrompt_controller.dart`
- Create: `lib/app/pixrompt_sync_controller.dart`
- Test: `test/domain/prompt_image_sync_fields_test.dart`
- Test: `test/domain/sync_models_test.dart`
- Test: `test/data/pixrompt_api_client_test.dart`
- Test: `test/data/sync_state_repository_test.dart`
- Test: `test/app/pixrompt_sync_controller_test.dart`

- [ ] **Step 1: Add dependency tests first**

Write failing Dart tests that prove:

- Old `PromptImageItem` JSON still loads without maintenance fields.
- New optional fields round-trip.
- Sync auth/pull/push models parse and serialize expected payloads.
- API client joins `/v1` URLs without producing duplicate path segments.
- Sync state persists token, cursor, known server versions, and tombstones.
- Sync controller can login, logout, push local records, apply remote upserts, and apply remote tombstones against in-memory repositories.

Run:

```bash
cd /root/pixrompt
flutter test test/domain/prompt_image_sync_fields_test.dart test/domain/sync_models_test.dart test/data/pixrompt_api_client_test.dart test/data/sync_state_repository_test.dart test/app/pixrompt_sync_controller_test.dart
```

Expected before implementation: tests fail because sync modules and fields do not exist.

- [ ] **Step 2: Add Dart dependencies**

Add:

```yaml
dependencies:
  crypto: ^3.0.6
  http: ^1.2.2
```

Run:

```bash
cd /root/pixrompt
flutter pub get
```

- [ ] **Step 3: Add optional image maintenance fields**

Add nullable fields to `PromptImageItem`:

```dart
final String? originalFileName;
final String? contentSha256;
final String? mimeType;
final int? importedAt;
final int? lastSyncedAt;
```

Update constructor, `sample`, `fromJson`, `toJson`, and `copyWith`. Preserve existing `uid`, `createdAt`, and `updatedAt`.

- [ ] **Step 4: Add sync models and API client**

Implement strongly typed models for login/session, blob refs, push, pull, accepted records, rejected records, and tombstones. Implement API calls with bearer auth and clear exceptions for 401, network failure, and malformed responses.

- [ ] **Step 5: Add sync state persistence**

Use a separate Hive box or compatible abstraction that does not modify `pixrompt_records` or `pixrompt_image_bytes`. Persist:

```text
apiBaseUrl
accountEmail
token
tokenExpiresAt
deviceId
cursor
knownServerVersions
deletedTombstones
lastSyncAt
```

- [ ] **Step 6: Add controller sync helpers**

Add non-HTTP helpers to `PixromptController` for applying remote records and tombstones. Implement `PixromptSyncController` to coordinate login, logout, push/pull, SHA-256 calculation, blob upload/download, and status messages.

- [ ] **Step 7: Run Flutter sync tests**

Run:

```bash
cd /root/pixrompt
flutter test test/domain/prompt_image_sync_fields_test.dart test/domain/sync_models_test.dart test/data/pixrompt_api_client_test.dart test/data/sync_state_repository_test.dart test/app/pixrompt_sync_controller_test.dart
```

Expected after implementation: selected sync tests pass.

- [ ] **Step 8: Commit Flutter sync layer**

```bash
git add pubspec.yaml pubspec.lock lib/domain/prompt_image.dart lib/domain/sync_models.dart lib/data/pixrompt_api_client.dart lib/data/sync_state_repository.dart lib/data/hive_pixrompt_repository.dart lib/app/pixrompt_controller.dart lib/app/pixrompt_sync_controller.dart test/domain/prompt_image_sync_fields_test.dart test/domain/sync_models_test.dart test/data/pixrompt_api_client_test.dart test/data/sync_state_repository_test.dart test/app/pixrompt_sync_controller_test.dart
git commit -m "feat: add pixrompt flutter sync layer"
```

---

## Task 3: Flutter Account And Sync UI

**Files:**
- Create: `lib/ui/account_sync_sheet.dart`
- Modify: `lib/ui/settings_sheet.dart`
- Modify: `lib/ui/pixrompt_app.dart` if constructor wiring requires a sync controller.
- Modify: `lib/main.dart`
- Test: `test/ui/account_sync_sheet_test.dart`
- Modify: `test/ui/pixrompt_app_test.dart`

- [ ] **Step 1: Write failing UI tests**

Write widget tests that prove:

- Settings shows an "Account and Sync" entry.
- The account sheet exposes labeled API Base URL, email, and password fields.
- Login button is disabled while loading.
- A signed-in state shows account email, last sync time, sync button, and logout button.
- Icon-only controls keep tooltips or semantic labels.

Run:

```bash
cd /root/pixrompt
flutter test test/ui/account_sync_sheet_test.dart test/ui/pixrompt_app_test.dart
```

Expected before implementation: tests fail because the sheet and settings entry do not exist.

- [ ] **Step 2: Implement account sync sheet**

Create a bottom-sheet UI using existing `PixromptSheetFrame`, `PixromptSpace`, `PixromptRadius`, Material `TextField`, `FilledButton`, and Material icons. Default API Base URL is:

```text
https://pixrompt.quaternijkon.online/v1
```

Do not persist passwords. Use explicit labels and loading indicators.

- [ ] **Step 3: Wire settings and app startup**

Initialize `PixromptSyncController` in `main.dart`, pass it into `PixromptApp`, and pass it to `SettingsSheet`. Keep gallery startup offline-first and do not block on network calls.

- [ ] **Step 4: Run UI tests**

Run:

```bash
cd /root/pixrompt
flutter test test/ui/account_sync_sheet_test.dart test/ui/pixrompt_app_test.dart
```

Expected after implementation: UI tests pass.

- [ ] **Step 5: Commit Flutter sync UI**

```bash
git add lib/ui/account_sync_sheet.dart lib/ui/settings_sheet.dart lib/ui/pixrompt_app.dart lib/main.dart test/ui/account_sync_sheet_test.dart test/ui/pixrompt_app_test.dart
git commit -m "feat: add pixrompt account sync ui"
```

---

## Task 4: Deployment Templates And Documentation

**Files:**
- Create: `deploy/pixrompt-api.service.example`
- Create: `deploy/pixrompt-nginx-proxy-manager.md`
- Modify: `README.md`
- Modify: `STANDALONE_PACKAGE.md`
- Modify: `.gitignore`

- [ ] **Step 1: Write deployment docs**

Document:

- How to create `/etc/pixrompt/env`.
- How to generate a password hash with `server/scripts/hash_password.py`.
- How to install Python dependencies.
- How to start `pixrompt-api.service`.
- How to configure NPM for `pixrompt.quaternijkon.online`.
- How to run health and login verification.
- That Flutter artifacts must be built elsewhere.

- [ ] **Step 2: Add systemd example**

Create `deploy/pixrompt-api.service.example` with:

```ini
[Unit]
Description=Pixrompt Sync API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/root/pixrompt
EnvironmentFile=/etc/pixrompt/env
ExecStart=/root/pixrompt/server/.venv/bin/uvicorn server.app.main:app --host 127.0.0.1 --port 18182
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: Verify docs do not contain secrets**

Run a secret scan without embedding the production plaintext password or
personal email in the committed command:

```bash
cd /root/pixrompt
rg -n "Bearer [A-Za-z0-9]|PIXROMPT_TOKEN_SECRET=|PIXROMPT_PASSWORD_HASH=\\$" README.md STANDALONE_PACKAGE.md deploy server docs
```

Expected: no production plaintext password, email, token, or real hash is present.

- [ ] **Step 4: Commit deployment docs**

```bash
git add deploy README.md STANDALONE_PACKAGE.md .gitignore
git commit -m "docs: add pixrompt sync deployment guide"
```

---

## Task 5: Verification, Local Deployment, Public Routing, And Push

**Files:**
- Modify outside repo: `/etc/pixrompt/env`
- Modify outside repo: `/etc/systemd/system/pixrompt-api.service`
- Modify outside repo: Nginx Proxy Manager SQLite/config for `pixrompt.quaternijkon.online`
- Modify outside repo: `/root/管理员手册.md`

- [ ] **Step 1: Run backend verification**

Run:

```bash
cd /root/pixrompt
python3 -m pytest server/tests -q
```

Expected: all backend tests pass.

- [ ] **Step 2: Run Flutter verification without building**

Run:

```bash
cd /root/pixrompt
flutter test
flutter analyze
```

Expected: tests and analysis pass. Do not run `flutter build`.

- [ ] **Step 3: Deploy backend locally**

Create production env under `/etc/pixrompt/env`, generate a password hash using the user-provided password without committing it, install dependencies under `server/.venv`, install `pixrompt-api.service`, and start the service.

- [ ] **Step 4: Configure public HTTPS route**

Add or update NPM so `https://pixrompt.quaternijkon.online` forwards to the local backend port. Validate NPM syntax with:

```bash
docker exec nginx-proxy-manager nginx -t
```

- [ ] **Step 5: Verify public backend**

Run:

```bash
curl -fsS http://127.0.0.1:18182/health
curl -fsS https://pixrompt.quaternijkon.online/health
curl -fsS https://pixrompt.quaternijkon.online/v1/health
curl -i https://pixrompt.quaternijkon.online/v1/sync/pull
```

Expected: health checks succeed; unauthenticated sync returns 401 or 405/401 depending on method enforcement.

- [ ] **Step 6: Verify login**

Use the production email and password only in the shell command or a temporary file outside Git. Confirm `/v1/auth/login` returns a token. Do not paste the token into committed docs.

- [ ] **Step 7: Update administrator manual**

Update `/root/管理员手册.md` with:

- Service name: Pixrompt Sync API.
- Public entry: `https://pixrompt.quaternijkon.online/v1`.
- Original backend port: `18182`.
- Account note: single-user email stored in `/etc/pixrompt/env`, password hash only.
- Runtime path: `/root/pixrompt`.
- Service: `pixrompt-api.service`.
- Data paths: configured SQLite path and blob dir.

- [ ] **Step 8: Final secret scan**

Run:

```bash
cd /root/pixrompt
rg -n "Bearer [A-Za-z0-9]|PIXROMPT_TOKEN_SECRET=|PIXROMPT_PASSWORD_HASH=\\$" .
git status --short
```

Expected: no production secret in tracked or untracked repo files.

- [ ] **Step 9: Push to GitHub**

Run:

```bash
cd /root/pixrompt
git push origin main
git ls-remote origin refs/heads/main
git rev-parse HEAD
```

Expected: remote `main` matches local `HEAD`.
