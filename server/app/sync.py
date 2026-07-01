import json
from sqlite3 import Connection, Row

from fastapi import APIRouter, Depends, Request

from server.app import db
from server.app.auth import AuthSession, get_current_session, get_db, get_db_lock
from server.app.schemas import (
    AcceptedItem,
    PullBlob,
    PullChange,
    PullDeleted,
    PullRequest,
    PullResponse,
    PushDelete,
    PushImage,
    PushRequest,
    PushResponse,
    RejectedItem,
)
from server.app.security import now_ms


router = APIRouter()
_REJECT_NEWER_OR_EQUAL = "server_has_newer_or_equal_timestamp"


def _row_timestamp(row: Row) -> int:
    if row["deleted_at"] is not None:
        return int(row["deleted_at"])
    return int(row["updated_at"])


def _is_stale_conflict(existing: Row | None, base_server_version: int, client_timestamp: int) -> bool:
    if existing is None:
        return False
    if int(existing["server_version"]) == base_server_version:
        return False
    return client_timestamp <= _row_timestamp(existing)


def _get_image(connection: Connection, user_id: int, image_uid: str) -> Row | None:
    return connection.execute(
        "SELECT * FROM images WHERE user_id = ? AND image_uid = ?",
        (user_id, image_uid),
    ).fetchone()


def _blob_available(connection: Connection, sha256: str, blob_store) -> bool:
    row = connection.execute(
        "SELECT 1 FROM blobs WHERE sha256 = ?",
        (sha256,),
    ).fetchone()
    if row is None:
        return False
    return blob_store is None or blob_store.exists(sha256)


def _add_missing_blob(missing: list[str], seen: set[str], sha256: str) -> None:
    if sha256 not in seen:
        seen.add(sha256)
        missing.append(sha256)


def _insert_event(
    connection: Connection,
    *,
    user_id: int,
    image_uid: str,
    server_version: int,
    event: dict,
) -> int:
    cursor = connection.execute(
        """
        INSERT INTO sync_events (
            user_id, entity_type, entity_id, server_version, event_json, created_at
        ) VALUES (?, 'image', ?, ?, ?, ?)
        """,
        (
            user_id,
            image_uid,
            server_version,
            json.dumps(event, separators=(",", ":"), sort_keys=True),
            now_ms(),
        ),
    )
    return int(cursor.lastrowid)


def emit_blob_available_events(
    connection: Connection,
    *,
    user_id: int,
    sha256: str,
) -> int:
    rows = connection.execute(
        """
        SELECT image_uid, server_version
        FROM images
        WHERE user_id = ?
          AND content_sha256 = ?
          AND deleted_at IS NULL
        ORDER BY image_uid
        """,
        (user_id, sha256),
    ).fetchall()

    for row in rows:
        _insert_event(
            connection,
            user_id=user_id,
            image_uid=row["image_uid"],
            server_version=int(row["server_version"]),
            event={"type": "upsert", "imageUid": row["image_uid"]},
        )

    return len(rows)


def _accept_image(
    connection: Connection,
    *,
    user_id: int,
    payload: PushImage,
    existing: Row | None,
) -> int:
    timestamp = now_ms()
    server_version = 1 if existing is None else int(existing["server_version"]) + 1
    record_json = json.dumps(payload.record, separators=(",", ":"), sort_keys=True)
    image_key = payload.blob.image_key if payload.blob is not None else None
    content_sha256 = payload.blob.sha256 if payload.blob is not None else None

    if existing is None:
        connection.execute(
            """
            INSERT INTO images (
                user_id, image_uid, record_json, image_key, content_sha256,
                server_version, deleted_at, created_at, updated_at, server_updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?)
            """,
            (
                user_id,
                payload.image_uid,
                record_json,
                image_key,
                content_sha256,
                server_version,
                timestamp,
                payload.updated_at,
                timestamp,
            ),
        )
    else:
        connection.execute(
            """
            UPDATE images
            SET record_json = ?,
                image_key = ?,
                content_sha256 = ?,
                server_version = ?,
                deleted_at = NULL,
                updated_at = ?,
                server_updated_at = ?
            WHERE user_id = ? AND image_uid = ?
            """,
            (
                record_json,
                image_key,
                content_sha256,
                server_version,
                payload.updated_at,
                timestamp,
                user_id,
                payload.image_uid,
            ),
        )

    _insert_event(
        connection,
        user_id=user_id,
        image_uid=payload.image_uid,
        server_version=server_version,
        event={"type": "upsert", "imageUid": payload.image_uid},
    )
    return server_version


def _accept_delete(
    connection: Connection,
    *,
    user_id: int,
    payload: PushDelete,
    existing: Row | None,
) -> int:
    timestamp = now_ms()
    server_version = 1 if existing is None else int(existing["server_version"]) + 1

    if existing is None:
        connection.execute(
            """
            INSERT INTO images (
                user_id, image_uid, record_json, image_key, content_sha256,
                server_version, deleted_at, created_at, updated_at, server_updated_at
            ) VALUES (?, ?, '{}', NULL, NULL, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                payload.image_uid,
                server_version,
                payload.deleted_at,
                timestamp,
                payload.deleted_at,
                timestamp,
            ),
        )
    else:
        connection.execute(
            """
            UPDATE images
            SET server_version = ?,
                deleted_at = ?,
                updated_at = ?,
                server_updated_at = ?
            WHERE user_id = ? AND image_uid = ?
            """,
            (
                server_version,
                payload.deleted_at,
                payload.deleted_at,
                timestamp,
                user_id,
                payload.image_uid,
            ),
        )

    _insert_event(
        connection,
        user_id=user_id,
        image_uid=payload.image_uid,
        server_version=server_version,
        event={"type": "deleted", "imageUid": payload.image_uid},
    )
    return server_version


def _blob_for_row(connection: Connection, row: Row, blob_store) -> PullBlob | None:
    if row["content_sha256"] is None:
        return None
    blob = connection.execute(
        "SELECT size_bytes FROM blobs WHERE sha256 = ?",
        (row["content_sha256"],),
    ).fetchone()
    if blob is None:
        return None
    if blob_store is not None and not blob_store.exists(row["content_sha256"]):
        return None
    return PullBlob(
        sha256=row["content_sha256"],
        imageKey=row["image_key"] or "",
        sizeBytes=int(blob["size_bytes"]),
    )


@router.post("/sync/push", response_model=PushResponse)
def push(
    request: Request,
    payload: PushRequest,
    session: AuthSession = Depends(get_current_session),
) -> PushResponse:
    connection = get_db(request)
    accepted: list[AcceptedItem] = []
    rejected: list[RejectedItem] = []
    missing_blobs: list[str] = []
    missing_seen: set[str] = set()

    with get_db_lock(request):
        try:
            for image in payload.images:
                if image.blob is not None and not _blob_available(
                    connection,
                    image.blob.sha256,
                    request.app.state.blob_store,
                ):
                    _add_missing_blob(missing_blobs, missing_seen, image.blob.sha256)

                existing = _get_image(connection, session.user_id, image.image_uid)
                if _is_stale_conflict(
                    existing,
                    image.base_server_version,
                    image.updated_at,
                ):
                    rejected.append(
                        RejectedItem(
                            imageUid=image.image_uid,
                            serverVersion=int(existing["server_version"]),
                            reason=_REJECT_NEWER_OR_EQUAL,
                        )
                    )
                    continue

                version = _accept_image(
                    connection,
                    user_id=session.user_id,
                    payload=image,
                    existing=existing,
                )
                accepted.append(AcceptedItem(imageUid=image.image_uid, serverVersion=version))

            for deletion in payload.deleted:
                existing = _get_image(connection, session.user_id, deletion.image_uid)
                if _is_stale_conflict(
                    existing,
                    deletion.base_server_version,
                    deletion.deleted_at,
                ):
                    rejected.append(
                        RejectedItem(
                            imageUid=deletion.image_uid,
                            serverVersion=int(existing["server_version"]),
                            reason=_REJECT_NEWER_OR_EQUAL,
                        )
                    )
                    continue

                version = _accept_delete(
                    connection,
                    user_id=session.user_id,
                    payload=deletion,
                    existing=existing,
                )
                accepted.append(AcceptedItem(imageUid=deletion.image_uid, serverVersion=version))

            connection.commit()
            cursor = db.current_cursor(connection, session.user_id)
        except Exception:
            connection.rollback()
            raise

    return PushResponse(
        cursor=cursor,
        serverTime=now_ms(),
        accepted=accepted,
        rejected=rejected,
        missingBlobs=missing_blobs,
    )


def _rows_for_pull(connection: Connection, user_id: int, cursor: int) -> list[Row]:
    if cursor == 0:
        return list(
            connection.execute(
                "SELECT * FROM images WHERE user_id = ? ORDER BY image_uid",
                (user_id,),
            ).fetchall()
        )

    event_rows = connection.execute(
        """
        SELECT entity_id, MAX(id) AS latest_event_id
        FROM sync_events
        WHERE user_id = ? AND id > ?
        GROUP BY entity_id
        ORDER BY latest_event_id
        """,
        (user_id, cursor),
    ).fetchall()
    rows: list[Row] = []
    for event_row in event_rows:
        image = _get_image(connection, user_id, event_row["entity_id"])
        if image is not None:
            rows.append(image)
    return rows


@router.post("/sync/pull", response_model=PullResponse)
def pull(
    request: Request,
    payload: PullRequest,
    session: AuthSession = Depends(get_current_session),
) -> PullResponse:
    connection = get_db(request)
    known_blobs = set(payload.known_blob_sha256)
    missing_blobs: list[str] = []
    missing_seen: set[str] = set()
    changes: list[PullChange] = []
    deleted: list[PullDeleted] = []

    with get_db_lock(request):
        rows = _rows_for_pull(connection, session.user_id, payload.cursor)
        cursor = max(payload.cursor, db.current_cursor(connection, session.user_id))

        for row in rows:
            if row["deleted_at"] is not None:
                deleted.append(
                    PullDeleted(
                        imageUid=row["image_uid"],
                        serverVersion=int(row["server_version"]),
                        deletedAt=int(row["deleted_at"]),
                    )
                )
                continue

            blob = _blob_for_row(connection, row, request.app.state.blob_store)
            if blob is not None and blob.sha256 not in known_blobs:
                _add_missing_blob(missing_blobs, missing_seen, blob.sha256)
            changes.append(
                PullChange(
                    imageUid=row["image_uid"],
                    serverVersion=int(row["server_version"]),
                    updatedAt=int(row["updated_at"]),
                    record=json.loads(row["record_json"]),
                    blob=blob,
                )
            )

    return PullResponse(
        cursor=cursor,
        serverTime=now_ms(),
        changes=changes,
        deleted=deleted,
        missingBlobs=missing_blobs,
    )
