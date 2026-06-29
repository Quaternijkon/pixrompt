from conftest import upload_blob


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


def test_tied_timestamp_keeps_server_record(client, auth_headers):
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
                    base_server_version=first_push["accepted"][0]["serverVersion"],
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
