import secrets
from dataclasses import dataclass
from sqlite3 import Connection, Row
from threading import RLock

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status

from server.app import db
from server.app.config import Settings
from server.app.schemas import LoginRequest, LoginResponse, SessionResponse
from server.app.security import (
    TokenError,
    create_signed_token,
    hash_token,
    load_signed_token,
    now_ms,
    verify_password,
)


router = APIRouter()


@dataclass(frozen=True)
class AuthSession:
    session_id: str
    user_id: int
    email: str
    device_id: str
    expires_at: int
    token_hash: str


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


def get_db(request: Request) -> Connection:
    return request.app.state.db


def get_db_lock(request: Request) -> RLock:
    return request.app.state.db_lock


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Unauthorized",
        headers={"WWW-Authenticate": "Bearer"},
    )


def _bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise _unauthorized()
    scheme, separator, token = authorization.partition(" ")
    if separator != " " or scheme.lower() != "bearer" or not token:
        raise _unauthorized()
    return token


def get_current_session(
    request: Request,
    authorization: str | None = Header(default=None),
) -> AuthSession:
    settings = get_settings(request)
    connection = get_db(request)
    token = _bearer_token(authorization)

    try:
        payload = load_signed_token(settings, token)
    except TokenError:
        raise _unauthorized() from None

    token_digest = hash_token(token)
    with get_db_lock(request):
        row = connection.execute(
            """
            SELECT
                sessions.id,
                sessions.user_id,
                sessions.token_hash,
                sessions.device_id,
                sessions.expires_at,
                sessions.revoked_at,
                users.email
            FROM sessions
            JOIN users ON users.id = sessions.user_id
            WHERE sessions.id = ? AND sessions.user_id = ? AND sessions.token_hash = ?
            """,
            (payload["sid"], payload["uid"], token_digest),
        ).fetchone()

    if row is None or row["revoked_at"] is not None or int(row["expires_at"]) <= now_ms():
        raise _unauthorized()

    return AuthSession(
        session_id=row["id"],
        user_id=int(row["user_id"]),
        email=row["email"],
        device_id=row["device_id"],
        expires_at=int(row["expires_at"]),
        token_hash=row["token_hash"],
    )


def _configured_user(connection: Connection, email: str) -> Row:
    return db.ensure_user(connection, email)


@router.post("/auth/login", response_model=LoginResponse)
def login(request: Request, payload: LoginRequest) -> LoginResponse:
    settings = get_settings(request)
    normalized_email = payload.email.strip().lower()

    if normalized_email != settings.user_email:
        raise _unauthorized()
    if not verify_password(payload.password, settings.password_hash):
        raise _unauthorized()

    connection = get_db(request)
    with get_db_lock(request):
        try:
            user = _configured_user(connection, settings.user_email)
            expires_at = now_ms() + settings.token_ttl_seconds * 1000
            session_id = secrets.token_urlsafe(18)
            token = create_signed_token(
                settings,
                session_id=session_id,
                user_id=int(user["id"]),
                expires_at_ms=expires_at,
            )
            connection.execute(
                """
                INSERT INTO sessions (
                    id, user_id, token_hash, device_id, expires_at, revoked_at, created_at
                ) VALUES (?, ?, ?, ?, ?, NULL, ?)
                """,
                (
                    session_id,
                    int(user["id"]),
                    hash_token(token),
                    payload.device_id,
                    expires_at,
                    now_ms(),
                ),
            )
            connection.commit()
        except Exception:
            connection.rollback()
            raise

    return LoginResponse(token=token, expiresAt=expires_at, email=settings.user_email)


@router.post("/auth/logout")
def logout(
    request: Request,
    session: AuthSession = Depends(get_current_session),
) -> dict[str, str]:
    connection = get_db(request)
    with get_db_lock(request):
        try:
            connection.execute(
                """
                UPDATE sessions
                SET revoked_at = ?
                WHERE id = ? AND token_hash = ?
                """,
                (now_ms(), session.session_id, session.token_hash),
            )
            connection.commit()
        except Exception:
            connection.rollback()
            raise
    return {"status": "ok"}


@router.get("/auth/session", response_model=SessionResponse)
def session(session: AuthSession = Depends(get_current_session)) -> SessionResponse:
    return SessionResponse(
        email=session.email,
        deviceId=session.device_id,
        expiresAt=session.expires_at,
    )
