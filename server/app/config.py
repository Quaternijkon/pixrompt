import os
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

try:
    from dotenv import load_dotenv
except ModuleNotFoundError:  # pragma: no cover - dependency is installed in runtime envs.
    load_dotenv = None


REQUIRED_ENV = (
    "PIXROMPT_USER_EMAIL",
    "PIXROMPT_PASSWORD_HASH",
    "PIXROMPT_TOKEN_SECRET",
    "PIXROMPT_DATABASE_PATH",
    "PIXROMPT_BLOB_DIR",
)


class ConfigError(RuntimeError):
    """Raised when required Pixrompt backend configuration is missing."""


@dataclass(frozen=True)
class Settings:
    user_email: str
    password_hash: str
    token_secret: str
    database_path: Path
    blob_dir: Path
    token_ttl_seconds: int = 2_592_000
    base_path: str = "/v1"
    max_blob_bytes: int = 52_428_800


def _normalize_base_path(value: str) -> str:
    base_path = value.strip() or "/v1"
    if not base_path.startswith("/"):
        base_path = f"/{base_path}"
    return base_path.rstrip("/") or ""


def _parse_positive_int(value: str, name: str) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise ConfigError(f"{name} must be an integer") from exc
    if parsed <= 0:
        raise ConfigError(f"{name} must be greater than zero")
    return parsed


def _validate_token_secret(value: str) -> str:
    secret = value.strip()
    weak_placeholders = {
        "<random-32-byte-or-longer-secret>",
        "change-me",
        "changeme",
        "secret",
        "password",
        "pixrompt-token-secret",
    }
    if len(secret) < 32 or secret.lower() in weak_placeholders:
        raise ConfigError(
            "PIXROMPT_TOKEN_SECRET must be a non-placeholder secret at least 32 characters long"
        )
    if secret.startswith("<") and secret.endswith(">"):
        raise ConfigError("PIXROMPT_TOKEN_SECRET must not use the example placeholder")
    return secret


def load_settings(environ: Mapping[str, str] | None = None) -> Settings:
    if environ is None and load_dotenv is not None:
        load_dotenv()

    env = environ if environ is not None else os.environ
    missing = [name for name in REQUIRED_ENV if not env.get(name)]
    if missing:
        raise ConfigError(
            "Missing required Pixrompt environment variable(s): " + ", ".join(missing)
        )

    return Settings(
        user_email=env["PIXROMPT_USER_EMAIL"].strip().lower(),
        password_hash=env["PIXROMPT_PASSWORD_HASH"].strip(),
        token_secret=_validate_token_secret(env["PIXROMPT_TOKEN_SECRET"]),
        database_path=Path(env["PIXROMPT_DATABASE_PATH"]),
        blob_dir=Path(env["PIXROMPT_BLOB_DIR"]),
        token_ttl_seconds=_parse_positive_int(
            env.get("PIXROMPT_TOKEN_TTL_SECONDS", "2592000"),
            "PIXROMPT_TOKEN_TTL_SECONDS",
        ),
        base_path=_normalize_base_path(env.get("PIXROMPT_BASE_PATH", "/v1")),
        max_blob_bytes=_parse_positive_int(
            env.get("PIXROMPT_MAX_BLOB_BYTES", "52428800"),
            "PIXROMPT_MAX_BLOB_BYTES",
        ),
    )
