from conftest import sha256_hex


def test_blob_put_get_head_verify_hash_and_deduplicate(client, auth_headers, configured_env):
    data = b"pixrompt image bytes"
    digest = sha256_hex(data)

    first_response = client.put(
        f"/v1/blobs/{digest}",
        content=data,
        headers={**auth_headers, "content-type": "image/png"},
    )
    second_response = client.put(
        f"/v1/blobs/{digest}",
        content=data,
        headers={**auth_headers, "content-type": "image/png"},
    )
    head_response = client.head(f"/v1/blobs/{digest}", headers=auth_headers)
    get_response = client.get(f"/v1/blobs/{digest}", headers=auth_headers)

    stored_files = [path for path in configured_env["blob_dir"].rglob("*") if path.is_file()]
    assert first_response.status_code == 201
    assert second_response.status_code == 200
    assert len(stored_files) == 1
    assert head_response.status_code == 200
    assert head_response.headers["x-pixrompt-sha256"] == digest
    assert head_response.headers["x-pixrompt-blob-size"] == str(len(data))
    assert get_response.status_code == 200
    assert get_response.content == data
    assert get_response.headers["content-type"].startswith("image/png")


def test_blob_put_rejects_body_that_does_not_match_path_hash(
    client,
    auth_headers,
    configured_env,
):
    digest = sha256_hex(b"expected bytes")

    response = client.put(
        f"/v1/blobs/{digest}",
        content=b"different bytes",
        headers={**auth_headers, "content-type": "application/octet-stream"},
    )

    stored_files = [path for path in configured_env["blob_dir"].rglob("*") if path.is_file()]
    assert response.status_code == 400
    assert stored_files == []


def test_blob_missing_returns_not_found(client, auth_headers):
    missing_digest = "0" * 64

    head_response = client.head(f"/v1/blobs/{missing_digest}", headers=auth_headers)
    get_response = client.get(f"/v1/blobs/{missing_digest}", headers=auth_headers)

    assert head_response.status_code == 404
    assert get_response.status_code == 404
