#!/usr/bin/env python3
"""生成 AcePanel 路由与 AcePocket 调用的只读 JSON 清单。"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


REPO = "acepanel/panel"
API_BASE = f"https://api.github.com/repos/{REPO}"
ROUTE_RE = re.compile(
    r"\{\s*Method\s*:\s*(?P<method>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\s*,"
    r"\s*Path\s*:\s*(?P<quote>[\"'])(?P<path>/api(?:/[^\"']*)?)(?P=quote)",
    re.MULTILINE,
)
ROUTE_FALLBACK_RE = re.compile(
    r"\{[^\n{}]*?Path\s*:\s*([\"'])(?P<path>/api(?:/[^\"']*)?)\1",
    re.MULTILINE,
)
CALL_START_RE = re.compile(
    r"\b(?:(?P<receiver>[A-Za-z_]\w*)\s*\.\s*)?"
    r"(?P<method>get|post|put|delete|patch|getBytes|postFile|uploadMultipart|downloadToFile)\s*\(",
    re.IGNORECASE,
)
WS_CALL_RE = re.compile(r"\bwsConnect\s*\(")
QUOTED_RE = re.compile(r"^[rR]?([\"'])(.*)\1$", re.DOTALL)
INTERPOLATION_RE = re.compile(r"\$\{[^}]+\}|\$[A-Za-z_]\w*")
HTTP_METHODS = {
    "get": ("GET", None),
    "post": ("POST", None),
    "put": ("PUT", None),
    "delete": ("DELETE", None),
    "patch": ("PATCH", None),
    "getbytes": ("GET", None),
    "postfile": ("POST", None),
    "uploadmultipart": ("POST", "apiPath"),
    "downloadtofile": ("GET", "apiPath"),
}
RAW_HELPERS = {"getbytes", "postfile", "uploadmultipart", "downloadtofile"}


def _line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _mask_comments(text: str) -> str:
    """屏蔽行注释和块注释，同时保留行号与字符串内容。"""
    chars = list(text)
    quote = None
    escaped = False
    line_comment = False
    block_comment = False
    index = 0
    while index < len(chars):
        char = chars[index]
        next_char = chars[index + 1] if index + 1 < len(chars) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
            else:
                chars[index] = " "
        elif block_comment:
            if char == "*" and next_char == "/":
                chars[index] = chars[index + 1] = " "
                block_comment = False
                index += 1
            elif char != "\n":
                chars[index] = " "
        elif quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in "'\"`":
            quote = char
        elif char == "/" and next_char == "/":
            chars[index] = chars[index + 1] = " "
            line_comment = True
            index += 1
        elif char == "/" and next_char == "*":
            chars[index] = chars[index + 1] = " "
            block_comment = True
            index += 1
        index += 1
    return "".join(chars)


def _is_declaration(text: str, offset: int) -> bool:
    prefix = text[text.rfind("\n", 0, offset) + 1 : offset]
    return re.fullmatch(
        r"\s*(?:static\s+)?(?:Future(?:<[^>\n]+>)?|Stream(?:<[^>\n]+>)?|void|dynamic|[A-Z]\w*(?:<[^>\n]+>)?)\s+",
        prefix,
    ) is not None


def _read_json(url: str) -> dict:
    request = Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "acepocket-maintainer",
        },
    )
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def _download(url: str, destination: Path) -> None:
    request = Request(url, headers={"User-Agent": "acepocket-maintainer"})
    with urlopen(request, timeout=60) as response, destination.open("wb") as output:
        shutil.copyfileobj(response, output)


def _resolve_release(ref: str | None) -> tuple[str, str]:
    if ref is None:
        release = _read_json(f"{API_BASE}/releases/latest")
        ref = release.get("tag_name") or release.get("target_commitish")
        if not ref:
            raise RuntimeError("GitHub release 未返回 tag_name")
    if re.fullmatch(r"[0-9a-fA-F]{7,40}", ref):
        commit = _read_json(f"{API_BASE}/commits/{ref}").get("sha")
        if not commit:
            raise RuntimeError(f"无法解析 commit {ref}")
        return ref, commit
    tag_ref = _read_json(f"{API_BASE}/git/ref/tags/{ref}")
    obj = tag_ref.get("object") or {}
    sha = obj.get("sha")
    if not sha:
        raise RuntimeError(f"无法解析 tag {ref} 的 commit")
    if obj.get("type") == "tag":
        sha = (_read_json(f"{API_BASE}/git/tags/{sha}").get("object") or {}).get("sha") or sha
    return ref, sha


def _local_commit(source: Path, ref: str | None) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(source), "rev-parse", f"{ref or 'HEAD'}^{{commit}}"],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def _obtain_source(ref: str | None, source_dir: str | None, no_network: bool):
    if source_dir:
        path = Path(source_dir).resolve()
        if not (path / "internal" / "route").is_dir():
            raise RuntimeError(f"上游源码目录缺少 internal/route: {path}")
        return path, {"ref": ref or "local", "commit": _local_commit(path, ref), "source": "local"}, None
    if no_network:
        path = Path.cwd().resolve()
        if not (path / "internal" / "route").is_dir():
            raise RuntimeError("--no-network 需要 --source-dir，或当前目录必须包含 internal/route")
        return path, {"ref": ref or "local", "commit": _local_commit(path, ref), "source": "cwd"}, None

    resolved_ref, commit = _resolve_release(ref)
    temp_dir = Path(tempfile.mkdtemp(prefix="acepanel-maintainer-"))
    try:
        archive = temp_dir / "source.tar.gz"
        _download(f"https://github.com/{REPO}/archive/{commit}.tar.gz", archive)
        extract_dir = temp_dir / "src"
        extract_dir.mkdir()
        with tarfile.open(archive, "r:gz") as bundle:
            try:
                bundle.extractall(extract_dir, filter="data")
            except TypeError:
                if any(extract_dir not in (extract_dir / member.name).resolve().parents for member in bundle.getmembers()):
                    raise RuntimeError("上游压缩包包含越界路径")
                bundle.extractall(extract_dir)
        roots = [item for item in extract_dir.iterdir() if item.is_dir()]
        if len(roots) != 1 or not (roots[0] / "internal" / "route").is_dir():
            raise RuntimeError("上游压缩包中未找到 internal/route")
        return roots[0], {"ref": resolved_ref, "commit": commit, "source": "github"}, temp_dir
    except Exception:
        shutil.rmtree(temp_dir, ignore_errors=True)
        raise


def _route_records(source: Path, warnings: list[dict]) -> list[dict]:
    records = []
    route_dir = source / "internal" / "route"
    for file in sorted(route_dir.rglob("*.go")):
        try:
            text = file.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            warnings.append({"kind": "route_read", "file": str(file.relative_to(source)), "message": str(error)})
            continue
        scan_text = _mask_comments(text)
        matched_spans = set()
        for match in ROUTE_RE.finditer(scan_text):
            method_name = match.group("method").rsplit(".", 1)[-1]
            method = {
                "MethodGet": "GET",
                "MethodPost": "POST",
                "MethodPut": "PUT",
                "MethodDelete": "DELETE",
                "MethodPatch": "PATCH",
            }.get(method_name, method_name.upper())
            records.append({
                "method": method,
                "path": match.group("path"),
                "file": str(file.relative_to(source)),
                "line": _line_number(text, match.start()),
            })
            matched_spans.add(match.start())
            if method not in {"GET", "POST", "PUT", "DELETE", "PATCH"}:
                warnings.append({
                    "kind": "route_method",
                    "file": str(file.relative_to(source)),
                    "line": _line_number(text, match.start()),
                    "message": f"无法解析路由方法 {match.group('method')}: {match.group('path')}",
                })
        for match in ROUTE_FALLBACK_RE.finditer(scan_text):
            if match.start() not in matched_spans:
                warnings.append({
                    "kind": "route_method",
                    "file": str(file.relative_to(source)),
                    "line": _line_number(text, match.start()),
                    "message": f"无法解析路由方法: {match.group('path')}",
                })
    return records


def _literal_path(argument: str) -> tuple[str | None, bool]:
    value = argument.strip()
    quoted = QUOTED_RE.match(value)
    if not quoted:
        return None, True
    path = quoted.group(2)
    return path, bool(INTERPOLATION_RE.search(path))


def _arguments(text: str, start: int, limit: int) -> list[str]:
    """返回调用前几个参数，足以定位 API 路径且不解析 Dart。"""
    arguments = []
    depth = 0
    quote = None
    escaped = False
    argument_start = start
    for index in range(start, len(text)):
        char = text[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in "'\"":
            quote = char
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            if depth == 0:
                arguments.append(text[argument_start:index].strip())
                return arguments
            depth -= 1
        elif char == "," and depth == 0:
            arguments.append(text[argument_start:index].strip())
            if len(arguments) >= limit:
                return arguments
            argument_start = index + 1
    arguments.append(text[argument_start:].strip())
    return arguments


def _client_records(client_dir: Path, warnings: list[dict]) -> list[dict]:
    records = []
    for file in sorted(client_dir.rglob("*.dart")):
        if any(part.startswith(".") for part in file.relative_to(client_dir).parts):
            continue
        try:
            text = file.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            warnings.append({"kind": "client_read", "file": str(file.relative_to(client_dir)), "message": str(error)})
            continue
        scan_text = _mask_comments(text)
        relative = str(file.relative_to(client_dir))
        for match in CALL_START_RE.finditer(scan_text):
            if _is_declaration(scan_text, match.start()):
                continue
            receiver = match.group("receiver") or ""
            method_key = match.group("method").lower()
            method, named_path = HTTP_METHODS[method_key]
            if method_key not in RAW_HELPERS and "api" not in receiver.lower() and "client" not in receiver.lower():
                continue
            argument = _arguments(scan_text, match.end(), 1)[0]
            if named_path and argument.startswith("apiPath:"):
                argument = argument.split(":", 1)[1].strip()
            path, dynamic = _literal_path(argument)
            item = {
                "kind": "http",
                "method": method,
                "path": path,
                "dynamic": dynamic,
                "file": relative,
                "line": _line_number(text, match.start()),
            }
            if path is None:
                warnings.append({"kind": "client_path", "file": relative, "line": item["line"], "message": "HTTP 调用的路径不是字符串字面量"})
            records.append(item)
        for match in WS_CALL_RE.finditer(scan_text):
            if _is_declaration(scan_text, match.start()):
                continue
            arguments = _arguments(scan_text, match.end(), 2)
            argument = arguments[1] if len(arguments) > 1 else ""
            path, dynamic = _literal_path(argument)
            item = {
                "kind": "websocket",
                "method": "GET",
                "path": path,
                "dynamic": dynamic,
                "file": relative,
                "line": _line_number(text, match.start()),
            }
            if path is None:
                warnings.append({"kind": "client_path", "file": relative, "line": item["line"], "message": "WebSocket 调用的路径不是字符串字面量"})
            records.append(item)
    return records


def _normalize_client_path(path: str, kind: str) -> str:
    if path.startswith("/api/"):
        return path
    return "/api" + (path if path.startswith("/") else "/" + path)


def _path_pattern(path: str) -> str:
    segments = []
    for segment in path.split("/"):
        if (segment.startswith("{") and segment.endswith("}")) or INTERPOLATION_RE.search(segment):
            segments.append("[^/]+")
        else:
            segments.append(re.escape(segment))
    return "^" + "/".join(segments) + "$"


def _matches(route: dict, call: dict) -> bool:
    if call["path"] is None or route["method"] != call["method"]:
        return False
    if route["path"].startswith("/api/ws/") != (call["kind"] == "websocket"):
        return False
    return re.fullmatch(_path_pattern(route["path"]), _normalize_client_path(call["path"], call["kind"])) is not None


def build_inventory(source: Path, client_dir: Path, metadata: dict) -> dict:
    warnings: list[dict] = []
    routes = _route_records(source, warnings)
    calls = _client_records(client_dir, warnings)
    path_matches = []
    uncovered = []
    for route in routes:
        matched_calls = [call for call in calls if _matches(route, call)]
        path_matches.append({"route": route, "calls": matched_calls})
        if not matched_calls:
            uncovered.append(route)
    return {
        "source": metadata,
        "upstream_routes": routes,
        "client_calls": calls,
        "path_matches": path_matches,
        "uncovered_interfaces": uncovered,
        "dynamic_paths": [call for call in calls if call["dynamic"]],
        "parse_warnings": warnings,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="审计 AcePanel 路由与 AcePocket API 调用")
    parser.add_argument("--ref", help="上游 tag 或 commit；默认最新稳定 release")
    parser.add_argument("--source-dir", help="本地 AcePanel 源码目录，必须包含 internal/route")
    parser.add_argument("--client-dir", default=".", help="AcePocket 客户端目录，默认当前目录")
    parser.add_argument("--no-network", action="store_true", help="禁止网络；需配合 --source-dir 或在当前目录提供 internal/route")
    args = parser.parse_args(argv)
    temp_dir = None
    try:
        source, metadata, temp_dir = _obtain_source(args.ref, args.source_dir, args.no_network)
        result = build_inventory(source, Path(args.client_dir).resolve(), metadata)
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except (OSError, HTTPError, URLError, RuntimeError, tarfile.TarError) as error:
        print(f"api_inventory: {error}", file=sys.stderr)
        return 2
    finally:
        if temp_dir is not None:
            shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
