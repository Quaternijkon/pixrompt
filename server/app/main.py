from contextlib import asynccontextmanager
from threading import RLock

from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.responses import FileResponse

from server.app import db
from server.app.auth import get_current_session, router as auth_router
from server.app.blob_store import (
    BlobHashMismatch,
    BlobNotFound,
    BlobStore,
    BlobTooLarge,
    InvalidBlobHash,
)
from server.app.config import Settings, load_settings
from server.app.sync import router as sync_router
from server.app.security import now_ms


def _health() -> dict[str, str]:
    return {"status": "ok"}


def _blob_headers(
    sha256: str,
    size_bytes: int,
    *,
    include_content_length: bool = False,
) -> dict[str, str]:
    headers = {
        "x-pixrompt-sha256": sha256,
        "x-pixrompt-blob-size": str(size_bytes),
    }
    if include_content_length:
        headers["content-length"] = str(size_bytes)
    return headers


def _blob_row(request: Request, sha256: str):
    try:
        request.app.state.blob_store.stat(sha256)
    except (InvalidBlobHash, BlobNotFound):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Blob not found") from None

    with request.app.state.db_lock:
        row = request.app.state.db.execute(
            "SELECT * FROM blobs WHERE sha256 = ?",
            (sha256,),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Blob not found")
    return row


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or load_settings()

    @asynccontextmanager
    async def lifespan(fastapi_app: FastAPI):
        try:
            yield
        finally:
            fastapi_app.state.db.close()

    app = FastAPI(title="Pixrompt Sync API", lifespan=lifespan)
    app.state.settings = settings
    app.state.db = db.init_db(settings)
    app.state.db_lock = RLock()
    app.state.blob_store = BlobStore(settings.blob_dir)

    app.add_api_route("/health", _health, methods=["GET"])
    app.add_api_route(f"{settings.base_path}/health", _health, methods=["GET"])
    app.include_router(auth_router, prefix=settings.base_path)
    app.include_router(sync_router, prefix=settings.base_path)

    @app.head(
        f"{settings.base_path}/blobs/{{sha256}}",
        dependencies=[Depends(get_current_session)],
    )
    def head_blob(request: Request, sha256: str) -> Response:
        row = _blob_row(request, sha256)
        return Response(
            status_code=status.HTTP_200_OK,
            headers=_blob_headers(sha256, int(row["size_bytes"]), include_content_length=True),
            media_type=row["mime_type"],
        )

    @app.get(
        f"{settings.base_path}/blobs/{{sha256}}",
        dependencies=[Depends(get_current_session)],
    )
    def get_blob(request: Request, sha256: str) -> FileResponse:
        row = _blob_row(request, sha256)
        path = request.app.state.blob_store.path_for(sha256)
        return FileResponse(
            path,
            media_type=row["mime_type"],
            headers=_blob_headers(sha256, int(row["size_bytes"])),
        )

    @app.put(
        f"{settings.base_path}/blobs/{{sha256}}",
        dependencies=[Depends(get_current_session)],
    )
    async def put_blob(request: Request, sha256: str) -> Response:
        mime_type = request.headers.get("content-type") or "application/octet-stream"
        mime_type = mime_type.split(";", 1)[0].strip() or "application/octet-stream"

        try:
            stored = await request.app.state.blob_store.put_stream(
                sha256,
                request.stream(),
                max_bytes=request.app.state.settings.max_blob_bytes,
            )
        except InvalidBlobHash:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Blob not found",
            ) from None
        except BlobTooLarge as exc:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=str(exc),
            ) from exc
        except BlobHashMismatch as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(exc),
            ) from exc

        with request.app.state.db_lock:
            try:
                request.app.state.db.execute(
                    """
                    INSERT OR IGNORE INTO blobs (
                        sha256, size_bytes, mime_type, storage_path, created_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (sha256, stored.size_bytes, mime_type, stored.relative_path, now_ms()),
                )
                row = request.app.state.db.execute(
                    "SELECT size_bytes, mime_type FROM blobs WHERE sha256 = ?",
                    (sha256,),
                ).fetchone()
                request.app.state.db.commit()
            except Exception:
                request.app.state.db.rollback()
                raise

        response_size = int(row["size_bytes"]) if row is not None else stored.size_bytes
        response_mime_type = row["mime_type"] if row is not None else mime_type

        return Response(
            status_code=status.HTTP_201_CREATED if stored.created else status.HTTP_200_OK,
            headers=_blob_headers(sha256, response_size),
            media_type=response_mime_type,
        )

    return app


app = create_app()
