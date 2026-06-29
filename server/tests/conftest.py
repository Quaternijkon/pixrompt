import hashlib
import secrets

import pytest


TEST_EMAIL = "pixrompt-user@example.test"


@pytest.fixture()
def configured_env(monkeypatch, tmp_path):
    from server.app.security import hash_password

    db_path = tmp_path / "pixrompt.sqlite3"
    blob_dir = tmp_path / "blobs"

    monkeypatch.setenv("PIXROMPT_USER_EMAIL", TEST_EMAIL)
    test_password = secrets.token_urlsafe(18)
    monkeypatch.setenv("PIXROMPT_PASSWORD_HASH", hash_password(test_password))
    monkeypatch.setenv("PIXROMPT_TOKEN_SECRET", secrets.token_urlsafe(32))
    monkeypatch.setenv("PIXROMPT_DATABASE_PATH", str(db_path))
    monkeypatch.setenv("PIXROMPT_BLOB_DIR", str(blob_dir))
    monkeypatch.setenv("PIXROMPT_TOKEN_TTL_SECONDS", "3600")
    monkeypatch.setenv("PIXROMPT_BASE_PATH", "/v1")

    return {
        "email": TEST_EMAIL,
        "password": test_password,
        "database_path": db_path,
        "blob_dir": blob_dir,
    }


@pytest.fixture()
def client(configured_env):
    from server.app.main import create_app
    from fastapi.testclient import TestClient

    app = create_app()
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def auth_headers(client, configured_env):
    response = client.post(
        "/v1/auth/login",
        json={
            "email": configured_env["email"],
            "password": configured_env["password"],
            "deviceId": "pytest-device",
        },
    )
    assert response.status_code == 200
    token = response.json()["token"]
    return {"Authorization": f"Bearer {token}"}


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def upload_blob(client, auth_headers, data: bytes, mime_type: str = "image/png") -> str:
    digest = sha256_hex(data)
    response = client.put(
        f"/v1/blobs/{digest}",
        content=data,
        headers={**auth_headers, "content-type": mime_type},
    )
    assert response.status_code in {200, 201}
    return digest
