#!/usr/bin/env python3
"""Resolve and prove the x86_64 Layer 5 dependency closure."""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from typing import Any

SOURCE_URL = "https://github.com/jellyfin/jellyfin-mpv-shim/archive/9970b2dc4a91f0c96a9fa5a1fcecf6a69331e315.tar.gz"
SOURCE_SHA256 = "c27b8ae2d698a152052586149b30b3125d82f9ac7695d2b32ca865ef6bd7f731"
SOURCE_COMMIT = "9970b2dc4a91f0c96a9fa5a1fcecf6a69331e315"
REQUIRED = ["python-mpv>=1.0.8", "jellyfin-apiclient-python>=1.18.0", "python-mpv-jsonipc>=1.4.0", "requests", "pillow"]
BUILD = ["setuptools>=77", "wheel"]
FORBIDDEN = {"python3-mpv"}


def normalized_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def requirement_name(requirement: str) -> str:
    match = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9_.-]*)", requirement)
    if not match:
        raise ValueError(f"invalid requirement name: {requirement!r}")
    return normalized_name(match.group(1))


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_metadata(archive: pathlib.Path, expected_hash: str = SOURCE_SHA256) -> dict[str, Any]:
    actual = sha256(archive)
    if actual != expected_hash:
        raise ValueError(f"source archive SHA-256 mismatch: {actual} != {expected_hash}")
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        with tarfile.open(archive, "r:gz") as tar:
            tar.extractall(root)
        projects = list(root.glob("*/pyproject.toml"))
        if len(projects) != 1:
            raise ValueError("pinned source archive does not contain exactly one pyproject.toml")
        import tomllib
        text = projects[0].read_text(encoding="utf-8")
        data = tomllib.loads(text)
    project = data.get("project", {})
    build = data.get("build-system", {})
    if project.get("name") != "jellyfin-mpv-shim" or project.get("version") != "3.0.0":
        raise ValueError("pinned source metadata name/version mismatch (tag/commit mismatch)")
    if project.get("requires-python") != ">=3.9":
        raise ValueError("upstream Python requirement differs")
    if project.get("dependencies") != REQUIRED:
        raise ValueError("upstream mandatory dependencies differ")
    if build.get("requires") != BUILD:
        raise ValueError("upstream build requirements differ")
    if any(re.search(rf"(?i)\b{re.escape(name)}\b", text) for name in FORBIDDEN):
        raise ValueError("forbidden package python3-mpv appears in pinned metadata")
    return {"name": project["name"], "version": project["version"], "requirements": REQUIRED,
            "build_requirements": BUILD, "pyproject_sha256": hashlib.sha256(text.encode()).hexdigest(),
            "source_sha256": actual, "source_commit": SOURCE_COMMIT}


def report_artifacts(report: dict[str, Any], python_tag: str, abi_tag: str, platform_tag: str,
                     required: list[str] | None = None) -> list[dict[str, str]]:
    installs = report.get("install")
    if not isinstance(installs, list) or not installs:
        raise ValueError("pip resolver report has no install entries; closure is unresolved")
    required_names = {requirement_name(item) for item in (required or REQUIRED + BUILD)}
    artifacts: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in installs:
        if not isinstance(item, dict):
            raise ValueError("pip resolver report contains an incomplete install entry")
        metadata = item.get("metadata")
        info = item.get("download_info")
        if not isinstance(metadata, dict) or not isinstance(info, dict):
            raise ValueError("resolver report contains an incomplete install entry")
        archive = info.get("archive_info")
        url = info.get("url", "")
        if not isinstance(archive, dict):
            raise ValueError("artifact lacks archive verification metadata")
        hashes = archive.get("hashes", {})
        filename = pathlib.PurePosixPath(url.split("?", 1)[0]).name
        digest = hashes.get("sha256") if isinstance(hashes, dict) else None
        if not url.startswith("https://") or not filename or not isinstance(digest, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", digest):
            raise ValueError(f"artifact lacks verified HTTPS URL/SHA-256: {metadata.get('name')}")
        if filename.endswith(".whl"):
            tags = filename[:-4].rsplit("-", 3)
            if len(tags) != 4:
                raise ValueError(f"artifact has malformed wheel filename: {filename}")
            _, wheel_python, wheel_abi, wheel_platform = tags
            python_ok = wheel_python in {python_tag, "py3"}
            abi_ok = wheel_abi in {abi_tag, "abi3", "none"}
            platform_ok = wheel_platform in {platform_tag, "any"}
            if not (python_ok and abi_ok and platform_ok):
                raise ValueError(f"artifact is incompatible with target ABI: {filename}")
        name, version = metadata.get("name"), metadata.get("version")
        if not isinstance(name, str) or not isinstance(version, str) or not name or not version:
            raise ValueError("resolver report artifact lacks name/version")
        canonical = normalized_name(name)
        if canonical in seen:
            raise ValueError(f"resolver report contains duplicate artifact: {name}")
        seen.add(canonical)
        artifacts.append({"name": name, "version": version, "filename": filename, "url": url,
                          "sha256": digest, "python_tag": python_tag, "abi_tag": abi_tag,
                          "platform_tag": platform_tag})
    missing = sorted(required_names - seen)
    if missing:
        raise ValueError("resolver report is incomplete; missing artifacts: " + ", ".join(missing))
    return artifacts


def sysconfig_soabi() -> str | None:
    import sysconfig
    return sysconfig.get_config_var("SOABI")


def probe_abi(python_tag: str, abi_tag: str, platform_tag: str,
              artifacts: list[dict[str, str]] | None = None,
              verified_dir: pathlib.Path | None = None,
              target_python: str = sys.executable) -> dict[str, Any]:
    evidence: dict[str, Any] = {"python": platform.python_version(), "implementation": sys.implementation.name,
        "python_tag": python_tag, "abi_tag": abi_tag, "platform_tag": platform_tag,
        "machine": platform.machine(), "soabi": sysconfig_soabi(), "imports": {}, "isolated": True}
    if not artifacts or verified_dir is None:
        evidence.update({"passed": False, "error": "isolated probe requires verified downloaded artifacts"})
        return evidence
    with tempfile.TemporaryDirectory() as tmp:
        target = pathlib.Path(tmp) / "target"
        target.mkdir()
        paths = []
        for item in artifacts:
            path = verified_dir / item["filename"]
            if not path.is_file() or sha256(path) != item["sha256"]:
                evidence.update({"passed": False, "error": f"verified artifact missing or changed: {item['filename']}"})
                return evidence
            paths.append(str(path))
        subprocess.run([target_python, "-m", "pip", "install", "--no-index", "--no-deps", "--only-binary=:all:",
                        "--target", str(target), *paths], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        script = r'''import ctypes, ctypes.util, importlib, json, sys, sysconfig
expected_python, expected_abi, expected_platform = sys.argv[2:5]
sys.path.insert(0, sys.argv[1])
result = {"imports": {}, "libmpv": ctypes.util.find_library("mpv"), "native": [],
          "target_implementation": sys.implementation.name, "target_soabi": sysconfig.get_config_var("SOABI"),
          "target_machine": __import__("platform").machine()}
result["target_tags_ok"] = (result["target_implementation"] == "cpython" and
                             expected_python.startswith("cp") and expected_abi in (result["target_soabi"] or "") and
                             result["target_machine"] in ("x86_64", "amd64"))
for module in ("mpv", "jellyfin_apiclient_python", "mpv_jsonipc", "requests", "PIL"):
    try:
        loaded = importlib.import_module(module)
        result["imports"][module] = "OK"
        origin = getattr(loaded, "__file__", "")
        if origin and origin.endswith((".so", ".pyd")): result["native"].append(origin)
    except Exception as exc: result["imports"][module] = f"FAIL: {type(exc).__name__}: {exc}"
if result["libmpv"]: ctypes.CDLL(result["libmpv"])
result["passed"] = result["target_tags_ok"] and bool(result["libmpv"]) and all(value == "OK" for value in result["imports"].values())
print(json.dumps(result))
'''
        completed = subprocess.run([target_python, "-I", "-S", "-c", script, str(target),
                                    python_tag, abi_tag, platform_tag], check=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        evidence.update(json.loads(completed.stdout))
    evidence["target_python"] = target_python
    return evidence


def verify_downloads(artifacts: list[dict[str, str]], dest: pathlib.Path) -> list[str]:
    dest.mkdir(parents=True, exist_ok=True)
    files = []
    for item in artifacts:
        path = dest / item["filename"]
        with urllib.request.urlopen(item["url"], timeout=120) as response, path.open("wb") as out:
            shutil.copyfileobj(response, out)
        actual = sha256(path)
        if actual != item["sha256"]:
            raise ValueError(f"artifact SHA-256 mismatch for {item['filename']}: {actual} != {item['sha256']}")
        files.append(str(path))
    return files


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--source", type=pathlib.Path)
    parser.add_argument("--pip", default=sys.executable)
    args = parser.parse_args(argv)
    evidence: dict[str, Any] = {"schema": "ashipaos.jellyfin-mpv-shim.resolution-evidence.v1", "status": "BLOCKED",
        "target": {"python_tag": "cp311", "abi_tag": "cp311", "platform_tag": "manylinux_2_17_x86_64"}}
    try:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            source = args.source or root / "source.tar.gz"
            if args.source is None:
                with urllib.request.urlopen(SOURCE_URL, timeout=120) as response, source.open("wb") as out: shutil.copyfileobj(response, out)
            meta = source_metadata(source)
            evidence["source"] = meta
            report = root / "pip-report.json"
            requirements = root / "requirements.txt"
            requirements.write_text("\n".join(meta["build_requirements"] + meta["requirements"]) + "\n", encoding="utf-8")
            subprocess.run([args.pip, "-m", "pip", "install", "--dry-run", "--ignore-installed", "--no-cache-dir", "--only-binary=:all:",
                            "--report", str(report), "--python-version", "3.11", "--implementation", "cp", "--abi", "cp311",
                            "--platform", "manylinux_2_17_x86_64", "-r", str(requirements)], check=True)
            report_data = json.loads(report.read_text(encoding="utf-8"))
            args.output.parent.mkdir(parents=True, exist_ok=True)
            (args.output.parent / "resolver-report.json").write_text(json.dumps(report_data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            artifacts = report_artifacts(report_data, "cp311", "cp311", "manylinux_2_17_x86_64", meta["build_requirements"] + meta["requirements"])
            evidence["resolver_report"], evidence["artifacts"] = report_data, artifacts
            verified = root / "verified-artifacts"
            verify_downloads(artifacts, verified)
            evidence["abi"] = probe_abi("cp311", "cp311", "manylinux_2_17_x86_64", artifacts, verified, args.pip)
            (args.output.parent / "native-import-evidence.json").write_text(json.dumps(evidence["abi"], indent=2, sort_keys=True) + "\n", encoding="utf-8")
            if not evidence["abi"].get("passed"):
                raise ValueError("target Python/libmpv/import ABI probe failed")
            evidence["status"] = "RESOLVED"
    except Exception as exc:
        evidence["error"] = f"{type(exc).__name__}: {exc}"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0 if evidence["status"] == "RESOLVED" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
