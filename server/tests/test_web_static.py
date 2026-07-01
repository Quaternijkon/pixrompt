from fastapi.testclient import TestClient


def test_web_static_serves_index_assets_and_keeps_api_paths(
    configured_env,
    monkeypatch,
    tmp_path,
):
    web_dir = tmp_path / "web"
    assets_dir = web_dir / "assets"
    assets_dir.mkdir(parents=True)
    (web_dir / "index.html").write_text(
        '<!doctype html><title>Pixrompt</title><script src="main.dart.js"></script>',
        encoding="utf-8",
    )
    (assets_dir / "AssetManifest.json").write_text("{}", encoding="utf-8")
    monkeypatch.setenv("PIXROMPT_WEB_DIR", str(web_dir))

    from server.app.main import create_app

    app = create_app()
    with TestClient(app) as client:
        root_response = client.get("/")
        route_response = client.get("/library/deep/link")
        asset_response = client.get("/assets/AssetManifest.json")
        api_response = client.get("/v1/health")
        missing_api_response = client.get("/v1/not-a-real-route")

    assert root_response.status_code == 200
    assert "Pixrompt" in root_response.text
    assert route_response.status_code == 200
    assert "Pixrompt" in route_response.text
    assert asset_response.status_code == 200
    assert asset_response.text == "{}"
    assert api_response.status_code == 200
    assert api_response.json() == {"status": "ok"}
    assert missing_api_response.status_code == 404
