import time

import pytest


REQUIRED_ENV = [
    "PIXROMPT_USER_EMAIL",
    "PIXROMPT_PASSWORD_HASH",
    "PIXROMPT_TOKEN_SECRET",
    "PIXROMPT_DATABASE_PATH",
    "PIXROMPT_BLOB_DIR",
]


def test_config_requires_secret_env(monkeypatch):
    from server.app.config import ConfigError, load_settings

    for name in REQUIRED_ENV:
        monkeypatch.delenv(name, raising=False)

    with pytest.raises(ConfigError) as exc_info:
        load_settings()

    message = str(exc_info.value)
    for name in REQUIRED_ENV:
        assert name in message


def test_health_endpoints_are_public(client):
    root_response = client.get("/health")
    versioned_response = client.get("/v1/health")

    assert root_response.status_code == 200
    assert root_response.json() == {"status": "ok"}
    assert versioned_response.status_code == 200
    assert versioned_response.json() == {"status": "ok"}


def test_login_success_returns_signed_session(client, configured_env):
    response = client.post(
        "/v1/auth/login",
        json={
            "email": configured_env["email"].upper(),
            "password": configured_env["password"],
            "deviceId": "phone-1",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["token"]
    assert body["tokenType"] == "bearer"
    assert body["email"] == configured_env["email"]
    assert body["expiresAt"] > int(time.time() * 1000)

    session_response = client.get(
        "/v1/auth/session",
        headers={"Authorization": f"Bearer {body['token']}"},
    )
    assert session_response.status_code == 200
    assert session_response.json()["email"] == configured_env["email"]
    assert session_response.json()["deviceId"] == "phone-1"


def test_login_rejects_wrong_credentials(client, configured_env):
    wrong_password_response = client.post(
        "/v1/auth/login",
        json={
            "email": configured_env["email"],
            "password": f"{configured_env['password']}-wrong",
            "deviceId": "phone-1",
        },
    )
    wrong_email_response = client.post(
        "/v1/auth/login",
        json={
            "email": "someone-else@example.test",
            "password": configured_env["password"],
            "deviceId": "phone-1",
        },
    )

    assert wrong_password_response.status_code == 401
    assert wrong_email_response.status_code == 401


def test_protected_endpoint_requires_bearer_token(client):
    response = client.post(
        "/v1/sync/pull",
        json={"deviceId": "phone-1", "cursor": 0, "knownBlobSha256": []},
    )

    assert response.status_code == 401


def test_logout_revokes_current_session(client, configured_env):
    login_response = client.post(
        "/v1/auth/login",
        json={
            "email": configured_env["email"],
            "password": configured_env["password"],
            "deviceId": "phone-1",
        },
    )
    token = login_response.json()["token"]
    headers = {"Authorization": f"Bearer {token}"}

    logout_response = client.post("/v1/auth/logout", headers=headers)
    session_response = client.get("/v1/auth/session", headers=headers)

    assert logout_response.status_code == 200
    assert logout_response.json() == {"status": "ok"}
    assert session_response.status_code == 401
