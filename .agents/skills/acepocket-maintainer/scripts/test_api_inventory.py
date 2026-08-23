#!/usr/bin/env python3
"""api_inventory.py 的最小离线回归测试。"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def run_inventory(upstream: Path, client: Path) -> dict:
    completed = subprocess.run(
        [
            sys.executable,
            "-B",
            str(ROOT / "api_inventory.py"),
            "--source-dir",
            str(upstream),
            "--client-dir",
            str(client),
            "--no-network",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="api-inventory-test-") as raw:
        root = Path(raw)
        upstream = root / "upstream"
        routes = upstream / "internal" / "route"
        routes.mkdir(parents=True)
        (routes / "sample.go").write_text(
            """package route
import \"net/http\"
var routes = Endpoints{
 {Method: http.MethodGet, Path: \"/api/home/panel\"},
 {Method: http.MethodGet, Path: \"/api/container/{id}\"},
 {Method: http.MethodGet, Path: \"/api/ws/pty\"},
 {Method: broken, Path: \"/api/unparsed\"},
}
""",
            encoding="utf-8",
        )
        client = root / "client"
        lib = client / "lib"
        lib.mkdir(parents=True)
        (lib / "sample.dart").write_text(
            """Future<void> uploadMultipart({required String apiPath}) async {}
Future<void> f() async {
  // _api.delete('/comment-only');
  _api.get('/home/panel');
  _api.get('/container/$id');
  wsConnect(server, '/ws/pty');
  await uploadMultipart(apiPath: '/api/file/upload');
  _api.post(path);
}
""",
            encoding="utf-8",
        )

        result = run_inventory(upstream, client)
        assert len(result["upstream_routes"]) == 4
        assert len(result["client_calls"]) == 5
        assert sum(bool(item["calls"]) for item in result["path_matches"]) == 3
        assert any(call["path"] == "/container/$id" for call in result["dynamic_paths"])
        assert any(warning["kind"] == "route_method" for warning in result["parse_warnings"])
        assert any(warning["kind"] == "client_path" for warning in result["parse_warnings"])

        assert result["source"]["ref"] == "local"
        assert result["uncovered_interfaces"]
    print("api_inventory tests passed")


if __name__ == "__main__":
    main()
