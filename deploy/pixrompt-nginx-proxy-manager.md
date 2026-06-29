# Pixrompt Sync API Deployment

This guide deploys the single-user Pixrompt sync backend on this host and exposes
it at:

```text
https://pixrompt.quaternijkon.online/v1
```

Do not commit production passwords, token secrets, bearer tokens, SQLite files,
or blob payloads. The Flutter app should be built on another machine.

## Runtime Layout

Recommended paths:

```text
/root/pixrompt                         repository
/root/pixrompt/server/.venv            Python virtual environment
/etc/pixrompt/env                      production environment file
/var/lib/pixrompt/pixrompt.sqlite3     SQLite metadata
/var/lib/pixrompt/blobs                original image blobs
/etc/systemd/system/pixrompt-api.service
```

The service listens on port `18182`. On this host Nginx Proxy Manager runs in a
Docker container, so the backend must be reachable from Docker through the host
gateway, usually `172.17.0.1:18182`. Direct public access to `18182` must be
blocked with `/usr/local/sbin/web-entry-firewall.sh`.

## Install Python Dependencies

If `python3 -m venv` is unavailable, install venv support first:

```bash
apt-get update
apt-get install -y python3-venv
```

Then install the backend dependencies:

```bash
cd /root/pixrompt
python3 -m venv server/.venv
server/.venv/bin/pip install --upgrade pip
server/.venv/bin/pip install -r server/requirements.txt
```

## Create Runtime Directories

```bash
install -d -m 700 /etc/pixrompt
install -d -m 700 /var/lib/pixrompt/blobs
```

## Create `/etc/pixrompt/env`

Generate a password hash interactively:

```bash
cd /root/pixrompt
server/.venv/bin/python server/scripts/hash_password.py
```

Generate a token secret:

```bash
python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
```

Create `/etc/pixrompt/env` with production values:

```bash
PIXROMPT_USER_EMAIL=you@example.invalid
PIXROMPT_PASSWORD_HASH=<paste-password-hash>
PIXROMPT_TOKEN_SECRET=<paste-random-token-secret>
PIXROMPT_DATABASE_PATH=/var/lib/pixrompt/pixrompt.sqlite3
PIXROMPT_BLOB_DIR=/var/lib/pixrompt/blobs
PIXROMPT_TOKEN_TTL_SECONDS=2592000
PIXROMPT_BASE_PATH=/v1
PIXROMPT_MAX_BLOB_BYTES=52428800
```

Use the real single-user email and generated password hash only in this file.
Do not put the plaintext password in the environment file.

## Install And Start systemd Service

```bash
cp /root/pixrompt/deploy/pixrompt-api.service.example \
  /etc/systemd/system/pixrompt-api.service
systemctl daemon-reload
systemctl enable --now pixrompt-api.service
systemctl status pixrompt-api.service --no-pager
```

Local health check:

```bash
curl -fsS http://127.0.0.1:18182/health
curl -fsS http://127.0.0.1:18182/v1/health
```

## Configure Nginx Proxy Manager

Create a proxy host:

```text
Domain Names: pixrompt.quaternijkon.online
Scheme: http
Forward Hostname / IP: 172.17.0.1
Forward Port: 18182
Cache Assets: off
Block Common Exploits: on
Websockets Support: off
SSL Certificate: *.quaternijkon.online wildcard certificate
Force SSL: on
HTTP/2 Support: on
HSTS: optional
```

Validate NPM after changing the host:

```bash
docker exec nginx-proxy-manager nginx -t
```

Public health checks:

```bash
curl -fsS https://pixrompt.quaternijkon.online/health
curl -fsS https://pixrompt.quaternijkon.online/v1/health
curl -i https://pixrompt.quaternijkon.online/v1/sync/pull
```

Unauthenticated sync should return `401` or a method error plus auth failure,
depending on the request method used.

## Verify Login Without Leaking Secrets

Use shell variables or a temporary file outside Git:

```bash
read -r PIXROMPT_EMAIL
read -rs PIXROMPT_PASSWORD
printf '\n'
curl -fsS https://pixrompt.quaternijkon.online/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$PIXROMPT_EMAIL\",\"password\":\"$PIXROMPT_PASSWORD\",\"deviceId\":\"ops-check\"}"
```

The response should include a bearer token and expiration. Do not paste that
token into docs, issue comments, logs, or committed files.

## Restrict Direct Port Access

Add `18182` to `HOST_PORTS` in `/usr/local/sbin/web-entry-firewall.sh`, then
apply the firewall:

```bash
/usr/local/sbin/web-entry-firewall.sh
```

Keep `/root/管理员手册.md` aligned with the live service after deployment:

```text
Service: Pixrompt Sync API
Public API base: https://pixrompt.quaternijkon.online/v1
Original backend port: 18182
Runtime path: /root/pixrompt
Service unit: pixrompt-api.service
Environment: /etc/pixrompt/env
Data: /var/lib/pixrompt/pixrompt.sqlite3 and /var/lib/pixrompt/blobs
Account: single-user email in /etc/pixrompt/env, password hash only
```

## Flutter Build Workflow

Do not build Flutter artifacts on this host for this deployment. Push the
repository changes, then build on a machine with Flutter and Android tooling:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
