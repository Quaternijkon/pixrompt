def _settings(tmp_path):
    from server.app.config import Settings

    return Settings(
        user_email="pixrompt-user@example.test",
        password_hash="placeholder-hash",
        token_secret="x" * 32,
        database_path=tmp_path / "pixrompt.sqlite3",
        blob_dir=tmp_path / "blobs",
    )


def test_init_db_sets_sqlite_durability_pragmas(tmp_path):
    from server.app import db

    connection = db.init_db(_settings(tmp_path))
    try:
        assert connection.execute("PRAGMA foreign_keys").fetchone()[0] == 1
        assert connection.execute("PRAGMA busy_timeout").fetchone()[0] == 5_000
        assert connection.execute("PRAGMA journal_mode").fetchone()[0].lower() == "wal"
        assert connection.execute("PRAGMA synchronous").fetchone()[0] == 1
    finally:
        connection.close()


def test_image_blob_integrity_issues_report_missing_blob_rows_and_files(tmp_path):
    from server.app import db

    settings = _settings(tmp_path)
    connection = db.init_db(settings)
    try:
        user = db.ensure_user(connection, settings.user_email)
        missing_row_sha = "a" * 64
        missing_file_sha = "b" * 64
        connection.execute(
            """
            INSERT INTO blobs (sha256, size_bytes, mime_type, storage_path, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (missing_file_sha, 10, "image/png", "bb/bb/blob", 1),
        )
        connection.execute(
            """
            INSERT INTO images (
                user_id, image_uid, record_json, image_key, content_sha256,
                server_version, deleted_at, created_at, updated_at, server_updated_at
            ) VALUES
                (?, 'image-missing-row', '{}', 'missing-row.png', ?, 1, NULL, 1, 1, 1),
                (?, 'image-missing-file', '{}', 'missing-file.png', ?, 1, NULL, 1, 1, 1)
            """,
            (int(user["id"]), missing_row_sha, int(user["id"]), missing_file_sha),
        )
        connection.commit()

        issues = db.image_blob_integrity_issues(connection, settings.blob_dir)

        assert issues == [
            {
                "image_uid": "image-missing-file",
                "sha256": missing_file_sha,
                "reason": "missing_blob_file",
            },
            {
                "image_uid": "image-missing-row",
                "sha256": missing_row_sha,
                "reason": "missing_blob_row",
            },
        ]
    finally:
        connection.close()
