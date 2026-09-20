#!/usr/bin/env python3
"""Resolve and prove the x86_64 Layer 5 dependency closure."""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
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

from packaging.tags import Tag, compatible_tags, cpython_tags
from packaging.utils import parse_wheel_filename

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
            members = tar.getmembers()
            for member in members:
                destination = (root / member.name).resolve()
                if not str(destination).startswith(str(root.resolve()) + "/"):
                    raise ValueError("source archive contains an unsafe path")
            tar.extractall(root, members=members)
        projects = list(root.glob("*/pyproject.toml"))
        if len(projects) != 1:
            raise ValueError("pinned source archive does not contain exactly one pyproject.toml")
        import tomllib
        project_file = projects[0]
        text = project_file.read_text(encoding="utf-8")
        data = tomllib.loads(text)
        constants_file = project_file.parent / "jellyfin_mpv_shim" / "constants.py"
        if not constants_file.is_file():
            raise ValueError("pinned source archive is missing declared constants.py")
        constants = ast.parse(constants_file.read_text(encoding="utf-8"), filename=str(constants_file))
        declared_version = None
        for node in constants.body:
            if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "CLIENT_VERSION" for target in node.targets):
                if not isinstance(node.value, ast.Constant) or not isinstance(node.value.value, str):
                    raise ValueError("CLIENT_VERSION is not a literal string")
                declared_version = node.value.value
                break
        if declared_version is None:
            raise ValueError("pinned source archive does not declare CLIENT_VERSION")
    project = data.get("project", {})
    build = data.get("build-system", {})
    dynamic = project.get("dynamic")
    setuptools_dynamic = data.get("tool", {}).get("setuptools", {}).get("dynamic", {})
    if dynamic != ["version"] or setuptools_dynamic.get("version", {}).get("attr") != "jellyfin_mpv_shim.constants.CLIENT_VERSION":
        raise ValueError("pinned source metadata does not use the declared dynamic version")
    if project.get("name") != "jellyfin-mpv-shim" or declared_version != "3.0.0":
        raise ValueError("pinned source metadata name/version mismatch (tag/commit mismatch)")
    if project.get("requires-python") != ">=3.9":
        raise ValueError("upstream Python requirement differs")
    if project.get("dependencies") != REQUIRED:
        raise ValueError("upstream mandatory dependencies differ")
    if build.get("requires") != BUILD:
        raise ValueError("upstream build requirements differ")
    if any(re.search(rf"(?i)\b{re.escape(name)}\b", text) for name in FORBIDDEN):
        raise ValueError("forbidden package python3-mpv appears in pinned metadata")
    return {"name": project["name"], "version": declared_version, "requirements": REQUIRED,
            "build_requirements": BUILD, "pyproject_sha256": hashlib.sha256(text.encode()).hexdigest(),
            "source_sha256": actual, "source_commit": SOURCE_COMMIT}


def target_wheel_tags(python_tag: str, abi_tag: str, platform_tag: str) -> set[Tag]:
    """Return packaging's supported tags for the declared target."""
    if not re.fullmatch(r"cp[0-9]+", python_tag) or not re.fullmatch(r"cp[0-9]+", abi_tag):
        raise ValueError("target Python/ABI declarations are malformed")
    if not re.fullmatch(r"[A-Za-z0-9_]+", platform_tag):
        raise ValueError("target platform declaration is malformed")
    version = (int(python_tag[2:]) // 100, int(python_tag[2:]) % 100)
    tags = set(cpython_tags(python_version=version, abis=[abi_tag], platforms=[platform_tag]))
    tags.update(compatible_tags(python_version=version, interpreter="cp", platforms=[platform_tag]))
    return tags


def wheel_is_compatible(filename: str, python_tag: str, abi_tag: str, platform_tag: str,
                        metadata_name: str, metadata_version: str) -> None:
    if not filename.endswith(".whl"):
        raise ValueError(f"artifact has malformed wheel filename: {filename}")
    try:
        wheel_name, wheel_version, _build, wheel_tags = parse_wheel_filename(filename)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"artifact has malformed wheel filename: {filename}") from exc
    if normalized_name(str(wheel_name)) != normalized_name(metadata_name) or str(wheel_version) != metadata_version:
        raise ValueError(f"wheel filename metadata mismatch: {filename}")
    if not wheel_tags.intersection(target_wheel_tags(python_tag, abi_tag, platform_tag)):
        raise ValueError(f"artifact is incompatible with target ABI/platform: {filename}")


def report_artifacts(report: dict[str, Any], python_tag: str, abi_tag: str, platform_tag: str,
                     required: list[str] | None = None) -> list[dict[str, str]]:
    installs = report.get("install")
    if not isinstance(installs, list) or not installs:
        raise ValueError("pip resolver report has no install entries; closure is unresolved")
    required_names = {requirement_name(item) for item in (required or REQUIRED)}
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
        name, version = metadata.get("name"), metadata.get("version")
        if not isinstance(name, str) or not isinstance(version, str) or not name or not version:
            raise ValueError("resolver report artifact lacks name/version")
        wheel_is_compatible(filename, python_tag, abi_tag, platform_tag, name, version)
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


def origin_is_isolated(origin: str, allowed_roots: tuple[pathlib.Path, ...]) -> bool:
    if not origin:
        return True
    path = pathlib.Path(origin).resolve()
    return any(path.is_relative_to(root.resolve()) for root in allowed_roots)


def probe_abi(python_tag: str, abi_tag: str, platform_tag: str,
              artifacts: list[dict[str, str]] | None = None,
              verified_dir: pathlib.Path | None = None,
              source_archive: pathlib.Path | None = None,
              source_sha256: str | None = None,
              rootfs_archive: pathlib.Path | None = None,
              target_python: str = sys.executable) -> dict[str, Any]:
    evidence: dict[str, Any] = {"python": platform.python_version(), "implementation": sys.implementation.name,
        "python_tag": python_tag, "abi_tag": abi_tag, "platform_tag": platform_tag,
        "machine": platform.machine(), "soabi": sysconfig_soabi(), "imports": {}, "isolated": True}
    if (not artifacts or verified_dir is None or source_archive is None or
            source_sha256 is None or rootfs_archive is None):
        evidence.update({"passed": False, "error": "isolated probe requires verified artifacts, application source, and target rootfs"})
        return evidence
    with tempfile.TemporaryDirectory() as tmp:
        target = pathlib.Path(tmp) / "target"
        target.mkdir()
        source_root = pathlib.Path(tmp) / "source"
        source_root.mkdir()
        rootfs_root = pathlib.Path(tmp) / "rootfs"
        rootfs_root.mkdir()
        with tarfile.open(rootfs_archive, "r:gz") as rootfs_tar:
            members = rootfs_tar.getmembers()
            for member in members:
                destination = (rootfs_root / member.name).resolve()
                if not str(destination).startswith(str(rootfs_root.resolve()) + "/"):
                    evidence.update({"passed": False, "error": "target rootfs archive contains an unsafe path"})
                    return evidence
            rootfs_tar.extractall(rootfs_root, members=members)
        if sha256(source_archive) != source_sha256:
            evidence.update({"passed": False, "error": "verified application source is missing or changed"})
            return evidence
        with tarfile.open(source_archive, "r:gz") as tar:
            members = tar.getmembers()
            for member in members:
                destination = (source_root / member.name).resolve()
                if not str(destination).startswith(str(source_root.resolve()) + "/"):
                    evidence.update({"passed": False, "error": "application source archive contains an unsafe path"})
                    return evidence
            tar.extractall(source_root, members=members)
        source_projects = list(source_root.glob("*/jellyfin_mpv_shim/__init__.py"))
        if len(source_projects) != 1:
            evidence.update({"passed": False, "error": "verified application source does not contain exactly one package"})
            return evidence
        app_root = source_projects[0].parent.parent
        paths = []
        for item in artifacts:
            path = verified_dir / item["filename"]
            if not path.is_file() or sha256(path) != item["sha256"]:
                evidence.update({"passed": False, "error": f"verified artifact missing or changed: {item['filename']}"})
                return evidence
            paths.append(str(path))
        subprocess.run([target_python, "-m", "pip", "install", "--no-index", "--no-deps", "--only-binary=:all:",
                        "--target", str(target), *paths], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        script = r'''import ctypes, ctypes.util, importlib, json, pathlib, sys, sysconfig
expected_python, expected_abi, expected_platform = sys.argv[2:5]
target_root, source_root = sys.argv[1:3]
stdlib_paths = [path for path in sys.path if path and
                "site-packages" not in path and "dist-packages" not in path]
sys.path[:] = [target_root, source_root, *stdlib_paths]
def origin_is_isolated(origin, allowed_roots):
    if not origin: return True
    path = pathlib.Path(origin).resolve()
    return any(path.is_relative_to(root.resolve()) for root in allowed_roots)
result = {"imports": {}, "libmpv": ctypes.util.find_library("mpv"), "native": [], "native_paths_ok": True,
          "target_implementation": sys.implementation.name, "target_soabi": sysconfig.get_config_var("SOABI"),
          "target_machine": __import__("platform").machine()}
result["target_tags_ok"] = (result["target_implementation"] == "cpython" and
                             expected_python.startswith("cp") and
                             expected_abi[2:] in (result["target_soabi"] or "") and
                             result["target_machine"] in ("x86_64", "amd64"))
for module in ("jellyfin_mpv_shim", "mpv", "jellyfin_apiclient_python", "python_mpv_jsonipc", "requests", "PIL"):
    try:
        loaded = importlib.import_module(module)
        result["imports"][module] = "OK"
        origin = getattr(loaded, "__file__", "")
        allowed = (pathlib.Path(target_root), pathlib.Path(source_root))
        if not origin_is_isolated(origin, allowed):
            raise RuntimeError(f"host-masked import: {origin}")
        if origin and origin.endswith((".so", ".pyd")):
            result["native"].append(origin)
            result["native_paths_ok"] = result["native_paths_ok"] and origin_is_isolated(origin, allowed)
    except Exception as exc: result["imports"][module] = f"FAIL: {type(exc).__name__}: {exc}"
if result["libmpv"]: ctypes.CDLL(result["libmpv"])
result["passed"] = (result["target_tags_ok"] and bool(result["libmpv"]) and result["native_paths_ok"] and
                    all(value == "OK" for value in result["imports"].values()))
print(json.dumps(result))
'''
        library_paths = [rootfs_root / "lib/x86_64-linux-gnu", rootfs_root / "usr/lib/x86_64-linux-gnu"]
        probe_env = os.environ.copy()
        probe_env["LD_LIBRARY_PATH"] = ":".join(str(path) for path in library_paths if path.is_dir())
        completed = subprocess.run([target_python, "-I", "-S", "-c", script, str(target), str(app_root),
                                    python_tag, abi_tag, platform_tag], check=False,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   env=probe_env)
        if completed.returncode != 0:
            evidence.update({"passed": False, "error": "isolated probe interpreter failed",
                             "probe_returncode": completed.returncode,
                             "probe_stdout": completed.stdout,
                             "probe_stderr": completed.stderr})
            return evidence
        try:
            evidence.update(json.loads(completed.stdout))
        except json.JSONDecodeError as exc:
            evidence.update({"passed": False, "error": "isolated probe returned invalid JSON",
                             "probe_stdout": completed.stdout, "probe_stderr": completed.stderr,
                             "probe_json_error": str(exc)})
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
    parser.add_argument("--rootfs", type=pathlib.Path)
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
            reports: dict[str, dict[str, Any]] = {}
            for kind, requirements_list in (("runtime", meta["requirements"]), ("build", meta["build_requirements"])):
                report = root / f"pip-report-{kind}.json"
                requirements = root / f"requirements-{kind}.txt"
                requirements.write_text("\n".join(requirements_list) + "\n", encoding="utf-8")
                subprocess.run([args.pip, "-m", "pip", "install", "--dry-run", "--ignore-installed", "--no-cache-dir", "--only-binary=:all:",
                                "--report", str(report), "--python-version", "3.11", "--implementation", "cp", "--abi", "cp311",
                                "--platform", "manylinux_2_17_x86_64", "-r", str(requirements)], check=True)
                reports[kind] = json.loads(report.read_text(encoding="utf-8"))
            args.output.parent.mkdir(parents=True, exist_ok=True)
            (args.output.parent / "resolver-report.json").write_text(json.dumps(reports["runtime"], indent=2, sort_keys=True) + "\n", encoding="utf-8")
            runtime_artifacts = report_artifacts(reports["runtime"], "cp311", "cp311", "manylinux_2_17_x86_64", meta["requirements"])
            build_artifacts = report_artifacts(reports["build"], "cp311", "cp311", "manylinux_2_17_x86_64", meta["build_requirements"])
            by_name = {item["name"]: item for item in runtime_artifacts}
            by_name.update({item["name"]: item for item in build_artifacts})
            artifacts = list(by_name.values())
            evidence["resolver_report"], evidence["artifacts"] = reports["runtime"], runtime_artifacts
            evidence["build_requirements"] = {"requirements": meta["build_requirements"], "resolver_report": reports["build"],
                                                "artifacts": build_artifacts}
            verified = root / "verified-artifacts"
            verify_downloads(artifacts, verified)
            evidence["abi"] = probe_abi("cp311", "cp311", "manylinux_2_17_x86_64", artifacts, verified,
                                         source, meta["source_sha256"], args.rootfs, args.pip)
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
