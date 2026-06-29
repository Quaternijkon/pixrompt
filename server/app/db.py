import sqlite3
from pathlib import Path

from server.app.config import Settings
from server.app.security import now_ms


def connect(database_path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(database_path, check_same_thread=False)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    return connection


def init_db(settings: Settings) -> sqlite3.Connection:
    settings.database_path.parent.mkdir(parents=True, exist_ok=True)
    settings.blob_dir.mkdir(parents=True, exist_ok=True)

    connection = connect(settings.database_path)
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL UNIQUE,
            created_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            token_hash TEXT NOT NULL UNIQUE,
            device_id TEXT NOT NULL,
            expires_at INTEGER NOT NULL,
            revoked_at INTEGER,
            created_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS blobs (
            sha256 TEXT PRIMARY KEY,
            size_bytes INTEGER NOT NULL,
            mime_type TEXT NOT NULL,
            storage_path TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS images (
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            image_uid TEXT NOT NULL,
            record_json TEXT NOT NULL,
            image_key TEXT,
            content_sha256 TEXT,
            server_version INTEGER NOT NULL,
            deleted_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            server_updated_at INTEGER NOT NULL,
            PRIMARY KEY (user_id, image_uid)
        );

        CREATE TABLE IF NOT EXISTS sync_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            server_version INTEGER NOT NULL,
            event_json TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
        CREATE INDEX IF NOT EXISTS idx_sync_events_user_cursor ON sync_events(user_id, id);
        CREATE INDEX IF NOT EXISTS idx_images_user_updated ON images(user_id, server_updated_at);
        """
    )
    ensure_user(connection, settings.user_email)
    connection.commit()
    return connection


def ensure_user(connection: sqlite3.Connection, email: str) -> sqlite3.Row:
    normalized = email.strip().lower()
    timestamp = now_ms()
    connection.execute(
        "INSERT OR IGNORE INTO users (email, created_at) VALUES (?, ?)",
        (normalized, timestamp),
    )
    row = connection.execute("SELECT * FROM users WHERE email = ?", (normalized,)).fetchone()
    if row is None:
        raise RuntimeError("failed to initialize configured Pixrompt user")
    return row


def current_cursor(connection: sqlite3.Connection, user_id: int) -> int:
    row = connection.execute(
        "SELECT COALESCE(MAX(id), 0) AS cursor FROM sync_events WHERE user_id = ?",
        (user_id,),
    ).fetchone()
    return int(row["cursor"])
