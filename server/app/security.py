import hashlib
import secrets
import time
from typing import Any

from itsdangerous import BadData, SignatureExpired, URLSafeTimedSerializer
from passlib.context import CryptContext

from server.app.config import Settings


_PASSWORD_CONTEXT = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")
_TOKEN_SALT = "pixrompt-session-v1"


class TokenError(ValueError):
    """Raised when a bearer token is malformed, expired, or not trusted."""


def now_ms() -> int:
    return int(time.time() * 1000)


def hash_password(password: str) -> str:
    return _PASSWORD_CONTEXT.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _PASSWORD_CONTEXT.verify(password, password_hash)
    except ValueError:
        return False


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _serializer(settings: Settings) -> URLSafeTimedSerializer:
    return URLSafeTimedSerializer(settings.token_secret, salt=_TOKEN_SALT)


def create_signed_token(
    settings: Settings,
    *,
    session_id: str,
    user_id: int,
    expires_at_ms: int,
) -> str:
    payload = {
        "sid": session_id,
        "uid": user_id,
        "exp": expires_at_ms,
        "nonce": secrets.token_urlsafe(18),
    }
    return _serializer(settings).dumps(payload)


def load_signed_token(settings: Settings, token: str) -> dict[str, Any]:
    try:
        payload = _serializer(settings).loads(token, max_age=settings.token_ttl_seconds)
    except SignatureExpired as exc:
        raise TokenError("token expired") from exc
    except BadData as exc:
        raise TokenError("invalid token") from exc

    if not isinstance(payload, dict):
        raise TokenError("invalid token payload")
    if not isinstance(payload.get("sid"), str):
        raise TokenError("token missing session")
    if not isinstance(payload.get("uid"), int):
        raise TokenError("token missing user")
    if not isinstance(payload.get("exp"), int):
        raise TokenError("token missing expiration")
    if payload["exp"] <= now_ms():
        raise TokenError("token expired")
    return payload
