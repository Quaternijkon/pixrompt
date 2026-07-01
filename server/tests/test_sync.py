from conftest import sha256_hex, upload_blob


def image_payload(
    image_uid: str,
    *,
    updated_at: int,
    title: str,
    sha256: str,
    base_server_version: int = 0,
):
    return {
        "imageUid": image_uid,
        "baseServerVersion": base_server_version,
        "updatedAt": updated_at,
        "record": {
            "uid": image_uid,
            "title": title,
            "updatedAt": updated_at,
            "contentSha256": sha256,
        },
        "blob": {
            "sha256": sha256,
            "imageKey": f"{image_uid}.png",
            "sizeBytes": 19,
            "mimeType": "image/png",
        },
    }


def push_image(client, auth_headers, payload):
    response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={"deviceId": "phone-1", "baseCursor": 0, "images": [payload], "deleted": []},
    )
    assert response.status_code == 200
    return response.json()


def test_push_then_pull_returns_current_upsert(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    push_response = push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="First", sha256=digest),
    )

    pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={"deviceId": "phone-2", "cursor": 0, "knownBlobSha256": [digest]},
    )

    assert push_response["accepted"] == [{"imageUid": "image-1", "serverVersion": 1}]
    assert push_response["rejected"] == []
    assert push_response["missingBlobs"] == []
    assert pull_response.status_code == 200
    body = pull_response.json()
    assert body["cursor"] == push_response["cursor"]
    assert body["missingBlobs"] == []
    assert body["deleted"] == []
    assert len(body["changes"]) == 1
    assert body["changes"][0]["type"] == "upsert"
    assert body["changes"][0]["imageUid"] == "image-1"
    assert body["changes"][0]["serverVersion"] == 1
    assert body["changes"][0]["updatedAt"] == 1_000
    assert body["changes"][0]["record"]["title"] == "First"
    assert body["changes"][0]["blob"]["sha256"] == digest


def test_push_rejects_malformed_blob_sha_with_422(client, auth_headers):
    response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={
            "deviceId": "phone-1",
            "baseCursor": 0,
            "images": [
                image_payload(
                    "image-1",
                    updated_at=1_000,
                    title="First",
                    sha256="not-a-sha",
                )
            ],
            "deleted": [],
        },
    )

    assert response.status_code == 422


def test_push_rejects_uppercase_blob_sha_with_422(client, auth_headers):
    uppercase_sha = "A" * 64

    response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={
            "deviceId": "phone-1",
            "baseCursor": 0,
            "images": [
                image_payload(
                    "image-1",
                    updated_at=1_000,
                    title="First",
                    sha256=uppercase_sha,
                )
            ],
            "deleted": [],
        },
    )

    assert response.status_code == 422


def test_pull_rejects_invalid_known_blob_sha_with_422(client, auth_headers):
    response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={"deviceId": "phone-1", "cursor": 0, "knownBlobSha256": ["not-a-sha"]},
    )

    assert response.status_code == 422


def test_push_accepts_valid_lowercase_blob_sha(client, auth_headers):
    lowercase_sha = "a" * 64

    response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={
            "deviceId": "phone-1",
            "baseCursor": 0,
            "images": [
                image_payload(
                    "image-1",
                    updated_at=1_000,
                    title="First",
                    sha256=lowercase_sha,
                )
            ],
            "deleted": [],
        },
    )

    assert response.status_code == 200
    assert response.json()["accepted"] == [{"imageUid": "image-1", "serverVersion": 1}]
    assert response.json()["missingBlobs"] == [lowercase_sha]


def test_push_rejects_record_uid_that_does_not_match_image_uid(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    payload = image_payload("image-1", updated_at=1_000, title="First", sha256=digest)
    payload["record"]["uid"] = "different-image"

    response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={"deviceId": "phone-1", "baseCursor": 0, "images": [payload], "deleted": []},
    )

    assert response.status_code == 422


def test_pull_reports_missing_blobs_unknown_to_client(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="First", sha256=digest),
    )

    pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={"deviceId": "phone-2", "cursor": 0, "knownBlobSha256": []},
    )

    assert pull_response.status_code == 200
    assert pull_response.json()["missingBlobs"] == [digest]


def test_pull_omits_blob_ref_when_server_blob_row_is_missing(client, auth_headers):
    missing_digest = "b" * 64
    push_response = push_image(
        client,
        auth_headers,
        image_payload(
            "image-1",
            updated_at=1_000,
            title="Metadata before blob upload",
            sha256=missing_digest,
        ),
    )

    pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={"deviceId": "phone-2", "cursor": 0, "knownBlobSha256": []},
    )

    assert push_response["missingBlobs"] == [missing_digest]
    assert pull_response.status_code == 200
    body = pull_response.json()
    assert body["missingBlobs"] == []
    assert len(body["changes"]) == 1
    assert body["changes"][0]["record"]["title"] == "Metadata before blob upload"
    assert body["changes"][0]["blob"] is None


def test_push_reports_missing_blob_when_blob_file_is_missing(
    client,
    auth_headers,
    configured_env,
):
    data = b"pixrompt blob missing from filesystem"
    digest = upload_blob(client, auth_headers, data)
    blob_path = configured_env["blob_dir"] / digest[:2] / digest[2:4] / digest
    blob_path.unlink()

    push_response = push_image(
        client,
        auth_headers,
        image_payload(
            "image-1",
            updated_at=1_000,
            title="File missing after db row",
            sha256=digest,
        ),
    )
    pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={"deviceId": "phone-2", "cursor": 0, "knownBlobSha256": []},
    )

    assert push_response["missingBlobs"] == [digest]
    assert pull_response.status_code == 200
    body = pull_response.json()
    assert body["missingBlobs"] == []
    assert len(body["changes"]) == 1
    assert body["changes"][0]["blob"] is None


def test_blob_upload_reemits_upsert_after_missing_blob_pull(client, auth_headers):
    data = b"delayed pixrompt blob"
    digest = sha256_hex(data)
    push_response = push_image(
        client,
        auth_headers,
        image_payload(
            "image-1",
            updated_at=1_000,
            title="Metadata before blob upload",
            sha256=digest,
        ),
    )
    first_pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={"deviceId": "phone-2", "cursor": 0, "knownBlobSha256": []},
    )

    assert push_response["missingBlobs"] == [digest]
    assert first_pull_response.status_code == 200
    first_pull = first_pull_response.json()
    assert first_pull["changes"][0]["blob"] is None
    cursor_after_missing_blob_pull = first_pull["cursor"]

    put_response = client.put(
        f"/v1/blobs/{digest}",
        content=data,
        headers={**auth_headers, "content-type": "image/png"},
    )
    repair_pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={
            "deviceId": "phone-2",
            "cursor": cursor_after_missing_blob_pull,
            "knownBlobSha256": [],
        },
    )

    assert put_response.status_code == 201
    assert repair_pull_response.status_code == 200
    repair_pull = repair_pull_response.json()
    assert repair_pull["cursor"] > cursor_after_missing_blob_pull
    assert repair_pull["missingBlobs"] == [digest]
    assert repair_pull["deleted"] == []
    assert len(repair_pull["changes"]) == 1
    assert repair_pull["changes"][0]["imageUid"] == "image-1"
    assert repair_pull["changes"][0]["serverVersion"] == 1
    assert repair_pull["changes"][0]["record"]["title"] == "Metadata before blob upload"
    assert repair_pull["changes"][0]["blob"] == {
        "sha256": digest,
        "imageKey": "image-1.png",
        "sizeBytes": len(data),
    }


def test_tombstone_propagates_to_incremental_pull(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    first_push = push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="First", sha256=digest),
    )

    delete_response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={
            "deviceId": "phone-1",
            "baseCursor": first_push["cursor"],
            "images": [],
            "deleted": [
                {
                    "imageUid": "image-1",
                    "baseServerVersion": 1,
                    "deletedAt": 2_000,
                }
            ],
        },
    )
    pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={
            "deviceId": "phone-2",
            "cursor": first_push["cursor"],
            "knownBlobSha256": [digest],
        },
    )

    assert delete_response.status_code == 200
    assert delete_response.json()["accepted"] == [{"imageUid": "image-1", "serverVersion": 2}]
    assert pull_response.status_code == 200
    body = pull_response.json()
    assert body["changes"] == []
    assert body["deleted"] == [
        {"imageUid": "image-1", "serverVersion": 2, "deletedAt": 2_000}
    ]


def test_same_base_equal_timestamp_upsert_is_accepted(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    first_push = push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="Server", sha256=digest),
    )
    tied_payload = image_payload(
        "image-1",
        updated_at=1_000,
        title="Client tie on current base",
        sha256=digest,
        base_server_version=first_push["accepted"][0]["serverVersion"],
    )

    tied_response = push_image(client, auth_headers, tied_payload)
    pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={"deviceId": "phone-2", "cursor": 0, "knownBlobSha256": [digest]},
    )

    assert tied_response["accepted"] == [{"imageUid": "image-1", "serverVersion": 2}]
    assert tied_response["rejected"] == []
    assert pull_response.json()["changes"][0]["record"]["title"] == "Client tie on current base"


def test_same_base_equal_timestamp_delete_is_accepted(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    first_push = push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="Server", sha256=digest),
    )

    delete_response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={
            "deviceId": "phone-1",
            "baseCursor": first_push["cursor"],
            "images": [],
            "deleted": [
                {
                    "imageUid": "image-1",
                    "baseServerVersion": first_push["accepted"][0]["serverVersion"],
                    "deletedAt": 1_000,
                }
            ],
        },
    )

    assert delete_response.status_code == 200
    assert delete_response.json()["accepted"] == [{"imageUid": "image-1", "serverVersion": 2}]
    assert delete_response.json()["rejected"] == []


def test_newer_client_update_wins(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    first_push = push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="First", sha256=digest),
    )
    newer_push = push_image(
        client,
        auth_headers,
        image_payload(
            "image-1",
            updated_at=2_000,
            title="Newer",
            sha256=digest,
            base_server_version=first_push["accepted"][0]["serverVersion"],
        ),
    )

    pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={
            "deviceId": "phone-2",
            "cursor": first_push["cursor"],
            "knownBlobSha256": [digest],
        },
    )

    assert newer_push["accepted"] == [{"imageUid": "image-1", "serverVersion": 2}]
    assert newer_push["rejected"] == []
    assert pull_response.status_code == 200
    body = pull_response.json()
    assert body["changes"][0]["serverVersion"] == 2
    assert body["changes"][0]["record"]["title"] == "Newer"


def test_older_client_update_loses(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    first_push = push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="First", sha256=digest),
    )
    newer_push = push_image(
        client,
        auth_headers,
        image_payload(
            "image-1",
            updated_at=2_000,
            title="Server",
            sha256=digest,
            base_server_version=first_push["accepted"][0]["serverVersion"],
        ),
    )

    older_response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={
            "deviceId": "phone-2",
            "baseCursor": newer_push["cursor"],
            "images": [
                image_payload(
                    "image-1",
                    updated_at=1_500,
                    title="Older",
                    sha256=digest,
                    base_server_version=first_push["accepted"][0]["serverVersion"],
                )
            ],
            "deleted": [],
        },
    )
    pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={
            "deviceId": "phone-3",
            "cursor": newer_push["cursor"],
            "knownBlobSha256": [digest],
        },
    )

    assert older_response.status_code == 200
    assert older_response.json()["accepted"] == []
    assert older_response.json()["rejected"] == [
        {
            "imageUid": "image-1",
            "serverVersion": 2,
            "reason": "server_has_newer_or_equal_timestamp",
        }
    ]
    assert pull_response.status_code == 200
    assert pull_response.json()["changes"] == []
    assert pull_response.json()["deleted"] == []


def test_stale_base_newer_timestamp_upsert_is_accepted(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    first_push = push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="First", sha256=digest),
    )
    second_push = push_image(
        client,
        auth_headers,
        image_payload(
            "image-1",
            updated_at=2_000,
            title="Second",
            sha256=digest,
            base_server_version=first_push["accepted"][0]["serverVersion"],
        ),
    )

    stale_newer_response = push_image(
        client,
        auth_headers,
        image_payload(
            "image-1",
            updated_at=3_000,
            title="Stale but newer",
            sha256=digest,
            base_server_version=first_push["accepted"][0]["serverVersion"],
        ),
    )

    assert second_push["accepted"] == [{"imageUid": "image-1", "serverVersion": 2}]
    assert stale_newer_response["accepted"] == [{"imageUid": "image-1", "serverVersion": 3}]
    assert stale_newer_response["rejected"] == []


def test_stale_base_newer_timestamp_delete_is_accepted(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    first_push = push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="First", sha256=digest),
    )
    second_push = push_image(
        client,
        auth_headers,
        image_payload(
            "image-1",
            updated_at=2_000,
            title="Second",
            sha256=digest,
            base_server_version=first_push["accepted"][0]["serverVersion"],
        ),
    )

    delete_response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={
            "deviceId": "phone-1",
            "baseCursor": second_push["cursor"],
            "images": [],
            "deleted": [
                {
                    "imageUid": "image-1",
                    "baseServerVersion": first_push["accepted"][0]["serverVersion"],
                    "deletedAt": 3_000,
                }
            ],
        },
    )

    assert delete_response.status_code == 200
    assert delete_response.json()["accepted"] == [{"imageUid": "image-1", "serverVersion": 3}]
    assert delete_response.json()["rejected"] == []


def test_stale_base_equal_timestamp_is_rejected(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    first_push = push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="First", sha256=digest),
    )
    push_image(
        client,
        auth_headers,
        image_payload(
            "image-1",
            updated_at=2_000,
            title="Second",
            sha256=digest,
            base_server_version=first_push["accepted"][0]["serverVersion"],
        ),
    )

    stale_tie_response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={
            "deviceId": "phone-2",
            "baseCursor": 0,
            "images": [
                image_payload(
                    "image-1",
                    updated_at=2_000,
                    title="Stale tie",
                    sha256=digest,
                    base_server_version=first_push["accepted"][0]["serverVersion"],
                )
            ],
            "deleted": [],
        },
    )

    assert stale_tie_response.status_code == 200
    assert stale_tie_response.json()["accepted"] == []
    assert stale_tie_response.json()["rejected"] == [
        {
            "imageUid": "image-1",
            "serverVersion": 2,
            "reason": "server_has_newer_or_equal_timestamp",
        }
    ]


def test_sync_push_rolls_back_image_when_event_insert_fails(monkeypatch, client, auth_headers):
    from fastapi.testclient import TestClient

    import server.app.sync as sync_module

    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")

    def fail_insert_event(*args, **kwargs):
        raise RuntimeError("event insert failed")

    monkeypatch.setattr(sync_module, "_insert_event", fail_insert_event)
    safe_client = TestClient(client.app, raise_server_exceptions=False)

    response = safe_client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={
            "deviceId": "phone-1",
            "baseCursor": 0,
            "images": [
                image_payload("image-1", updated_at=1_000, title="First", sha256=digest)
            ],
            "deleted": [],
        },
    )

    monkeypatch.undo()
    pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={"deviceId": "phone-2", "cursor": 0, "knownBlobSha256": [digest]},
    )

    assert response.status_code == 500
    assert pull_response.status_code == 200
    assert pull_response.json()["changes"] == []
    assert pull_response.json()["deleted"] == []


def test_stale_base_tied_timestamp_keeps_server_record(client, auth_headers):
    digest = upload_blob(client, auth_headers, b"pixrompt sync bytes")
    first_push = push_image(
        client,
        auth_headers,
        image_payload("image-1", updated_at=1_000, title="Server", sha256=digest),
    )

    tied_response = client.post(
        "/v1/sync/push",
        headers=auth_headers,
        json={
            "deviceId": "phone-2",
            "baseCursor": first_push["cursor"],
            "images": [
                image_payload(
                    "image-1",
                    updated_at=1_000,
                    title="Client tie",
                    sha256=digest,
                    base_server_version=0,
                )
            ],
            "deleted": [],
        },
    )
    pull_response = client.post(
        "/v1/sync/pull",
        headers=auth_headers,
        json={"deviceId": "phone-3", "cursor": 0, "knownBlobSha256": [digest]},
    )

    assert tied_response.status_code == 200
    assert tied_response.json()["accepted"] == []
    assert tied_response.json()["rejected"] == [
        {
            "imageUid": "image-1",
            "serverVersion": 1,
            "reason": "server_has_newer_or_equal_timestamp",
        }
    ]
    assert pull_response.status_code == 200
    assert pull_response.json()["changes"][0]["record"]["title"] == "Server"
