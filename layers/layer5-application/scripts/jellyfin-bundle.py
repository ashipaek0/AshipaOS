#!/usr/bin/env python3
"""Jellyfin MPV Shim bundle tooling for the A95X F3 Air (Debian arm64, CPython 3.13).

Subcommands:
  update-lock  Re-resolve the dependency closure from PyPI and rewrite the lock.
               Maintenance only; review the diff before committing it.
  resolve      CI: verify the committed lock (source pin, wheel tags, closure
               completeness under --require-hashes), download every artifact
               by hash, and import-probe the closure in a chroot of the
               target rootfs (qemu-user via binfmt; uses sudo when not root).
               Writes the resolution evidence JSON.
  install      Install the verified closure plus the pinned application source
               into a self-contained bundle directory (no network access).
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from typing import Any

from packaging.tags import Tag, compatible_tags, cpython_tags
from packaging.utils import canonicalize_name, parse_wheel_filename

LAYER_DIR = pathlib.Path(__file__).resolve().parents[1]
LOCK_FILE = LAYER_DIR / "config" / "dependencies.lock.json"
LOCK_SCHEMA = "ashipaos.jellyfin-mpv-shim.dependency-lock.v2"
EVIDENCE_SCHEMA = "ashipaos.jellyfin-mpv-shim.resolution.v1"

NAME = "jellyfin-mpv-shim"
VERSION = "3.0.0"
SOURCE_COMMIT = "9970b2dc4a91f0c96a9fa5a1fcecf6a69331e315"
SOURCE_URL = f"https://github.com/jellyfin/jellyfin-mpv-shim/archive/{SOURCE_COMMIT}.tar.gz"
SOURCE_SHA256 = "c27b8ae2d698a152052586149b30b3125d82f9ac7695d2b32ca865ef6bd7f731"
REQUIRED = ["python-mpv>=1.0.8", "jellyfin-apiclient-python>=1.18.0",
            "python-mpv-jsonipc>=1.4.0", "requests", "pillow"]
BUILD = ["setuptools>=77", "wheel"]
FORBIDDEN = ("python3-mpv",)

PYTHON_VERSION = "3.13"
PYTHON_TAG = "cp313"
ABI_TAG = "cp313"
PLATFORM_TAG = "manylinux_2_27_aarch64"
QEMU = "qemu-aarch64-static"
PROBE_MODULES = ("jellyfin_mpv_shim", "mpv", "jellyfin_apiclient_python",
                 "python_mpv_jsonipc", "requests", "PIL")


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, destination: pathlib.Path, expected: str) -> None:
    if not url.startswith("https://"):
        raise ValueError(f"refusing non-HTTPS download: {url}")
    partial = destination.with_name(destination.name + ".partial")
    with urllib.request.urlopen(url, timeout=120) as response, partial.open("wb") as out:
        shutil.copyfileobj(response, out)
    actual = sha256(partial)
    if actual != expected:
        partial.unlink()
        raise ValueError(f"SHA-256 mismatch for {destination.name}: {actual} != {expected}")
    partial.replace(destination)


def extract_tar(archive: pathlib.Path, destination: pathlib.Path) -> None:
    """Extract without letting any member escape the destination."""
    with tarfile.open(archive, "r:*") as tar:
        if hasattr(tarfile, "tar_filter"):
            tar.extractall(destination, filter="tar")
            return
        root = destination.resolve()
        for member in tar.getmembers():
            target = (destination / member.name).resolve()
            if target != root and not target.is_relative_to(root):
                raise ValueError(f"archive member escapes destination: {member.name}")
        tar.extractall(destination)


def requirement_name(requirement: str) -> str:
    match = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9_.-]*)", requirement)
    if not match:
        raise ValueError(f"invalid requirement: {requirement!r}")
    return canonicalize_name(match.group(1))


def source_metadata(archive: pathlib.Path) -> dict[str, Any]:
    """Verify the pinned source archive and that upstream metadata is unchanged."""
    actual = sha256(archive)
    if actual != SOURCE_SHA256:
        raise ValueError(f"source archive SHA-256 mismatch: {actual} != {SOURCE_SHA256}")
    import tomllib
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        extract_tar(archive, root)
        projects = list(root.glob("*/pyproject.toml"))
        if len(projects) != 1:
            raise ValueError("pinned source archive does not contain exactly one pyproject.toml")
        text = projects[0].read_text(encoding="utf-8")
        data = tomllib.loads(text)
        constants = projects[0].parent / "jellyfin_mpv_shim" / "constants.py"
        declared = None
        for node in ast.parse(constants.read_text(encoding="utf-8")).body:
            if (isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant)
                    and any(isinstance(t, ast.Name) and t.id == "CLIENT_VERSION" for t in node.targets)):
                declared = node.value.value
    project = data.get("project", {})
    if project.get("name") != NAME or declared != VERSION:
        raise ValueError("pinned source name/version mismatch (tag/commit mismatch)")
    if project.get("requires-python") != ">=3.9":
        raise ValueError("upstream Python requirement differs")
    if project.get("dependencies") != REQUIRED:
        raise ValueError("upstream mandatory dependencies differ from the pinned set")
    if data.get("build-system", {}).get("requires") != BUILD:
        raise ValueError("upstream build requirements differ")
    if project.get("scripts", {}).get(NAME) != "jellyfin_mpv_shim.mpv_shim:main":
        raise ValueError("upstream entry point differs")
    if any(re.search(rf"(?i)\b{re.escape(name)}\b", text) for name in FORBIDDEN):
        raise ValueError("forbidden Debian python3-mpv appears in pinned metadata")
    return {"name": NAME, "version": VERSION, "commit": SOURCE_COMMIT, "url": SOURCE_URL,
            "sha256": actual, "requirements": REQUIRED,
            "pyproject_sha256": hashlib.sha256(text.encode()).hexdigest()}


def target_tags() -> set[Tag]:
    """Tags the target accepts: CPython 3.13, aarch64, glibc manylinux <= 2.27."""
    platforms = [f"manylinux_2_{minor}_aarch64" for minor in range(27, 16, -1)]
    platforms.append("manylinux2014_aarch64")
    version = tuple(int(part) for part in PYTHON_VERSION.split("."))
    tags = set(cpython_tags(python_version=version, abis=[ABI_TAG], platforms=platforms))
    tags.update(compatible_tags(python_version=version, interpreter=PYTHON_TAG, platforms=platforms))
    return tags


def check_artifact(item: dict[str, Any]) -> None:
    fields = ("name", "version", "filename", "url", "sha256")
    if set(item) != set(fields) or not all(isinstance(item[k], str) and item[k] for k in fields):
        raise ValueError(f"lock artifact has unexpected shape: {item}")
    if not item["url"].startswith("https://files.pythonhosted.org/") or not item["url"].endswith("/" + item["filename"]):
        raise ValueError(f"lock artifact URL is not a PyPI file URL for its filename: {item['filename']}")
    if not re.fullmatch(r"[0-9a-f]{64}", item["sha256"]):
        raise ValueError(f"lock artifact hash is malformed: {item['filename']}")
    name, version, _build, tags = parse_wheel_filename(item["filename"])
    if name != canonicalize_name(item["name"]) or str(version) != item["version"]:
        raise ValueError(f"wheel filename does not match name/version: {item['filename']}")
    if not tags & target_tags():
        raise ValueError(f"wheel is incompatible with the target ABI/platform: {item['filename']}")


def load_lock(path: pathlib.Path) -> dict[str, Any]:
    lock = json.loads(path.read_text(encoding="utf-8"))
    expected_target = {"python_version": PYTHON_VERSION, "python_tag": PYTHON_TAG,
                       "abi_tag": ABI_TAG, "platform_tag": PLATFORM_TAG, "architecture": "arm64"}
    if lock.get("schema") != LOCK_SCHEMA or lock.get("status") != "RESOLVED":
        raise ValueError("dependency lock is not a RESOLVED v2 lock")
    if lock.get("target") != expected_target:
        raise ValueError("dependency lock target does not match the A95X runtime")
    if lock.get("source") != {"name": NAME, "version": VERSION, "commit": SOURCE_COMMIT,
                              "url": SOURCE_URL, "sha256": SOURCE_SHA256, "requirements": REQUIRED}:
        raise ValueError("dependency lock source does not match the pinned application source")
    artifacts = lock.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ValueError("dependency lock has no artifacts")
    seen: set[str] = set()
    for item in artifacts:
        check_artifact(item)
        canonical = canonicalize_name(item["name"])
        if canonical in seen:
            raise ValueError(f"duplicate lock artifact: {item['name']}")
        seen.add(canonical)
    missing = {requirement_name(r) for r in REQUIRED} - seen
    if missing:
        raise ValueError("lock is missing required distributions: " + ", ".join(sorted(missing)))
    return lock


def pip_report(requirements: list[str], work: pathlib.Path, require_hashes: bool) -> dict[str, Any]:
    requirements_file = work / "requirements.txt"
    report_file = work / "report.json"
    requirements_file.write_text("\n".join(requirements) + "\n", encoding="utf-8")
    command = [sys.executable, "-m", "pip", "install", "--dry-run", "--ignore-installed",
               "--no-cache-dir", "--only-binary=:all:", "--report", str(report_file),
               "--python-version", PYTHON_VERSION, "--implementation", "cp", "--abi", ABI_TAG,
               "--platform", PLATFORM_TAG, "-r", str(requirements_file)]
    if require_hashes:
        command.append("--require-hashes")
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
    return json.loads(report_file.read_text(encoding="utf-8"))


def report_artifacts(report: dict[str, Any]) -> list[dict[str, str]]:
    artifacts = []
    for entry in report.get("install") or []:
        info, metadata = entry["download_info"], entry["metadata"]
        url = info["url"]
        artifacts.append({"name": metadata["name"], "version": metadata["version"],
                          "filename": url.rsplit("/", 1)[1], "url": url,
                          "sha256": info["archive_info"]["hashes"]["sha256"]})
    return artifacts


def verify_closure(lock: dict[str, Any], work: pathlib.Path) -> None:
    """pip must resolve REQUIRED to exactly the locked, hashed artifact set."""
    pins = [f"{a['name']}=={a['version']} --hash=sha256:{a['sha256']}" for a in lock["artifacts"]]
    resolved = report_artifacts(pip_report(pins, work, require_hashes=True))
    key = lambda a: (canonicalize_name(a["name"]), a["version"], a["filename"], a["sha256"])
    if sorted(map(key, resolved)) != sorted(map(key, lock["artifacts"])):
        raise ValueError("pip closure differs from the committed lock")
    for requirement in REQUIRED:
        if requirement_name(requirement) not in {canonicalize_name(a["name"]) for a in resolved}:
            raise ValueError(f"closure lacks {requirement}")


def install_wheel(wheel: pathlib.Path, site: pathlib.Path) -> None:
    """Unpack a wheel into site-packages, mapping .data/purelib|platlib."""
    with zipfile.ZipFile(wheel) as archive:
        for member in archive.infolist():
            parts = pathlib.PurePosixPath(member.filename).parts
            if not parts or member.filename.startswith("/") or ".." in parts:
                raise ValueError(f"unsafe wheel member in {wheel.name}: {member.filename}")
            if parts[0].endswith(".data"):
                if len(parts) < 3 or parts[1] not in ("purelib", "platlib"):
                    continue  # scripts/headers/data are not used by the bundle
                parts = parts[2:]
            destination = site.joinpath(*parts)
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member) as src, destination.open("wb") as out:
                shutil.copyfileobj(src, out)


def install_closure(lock: dict[str, Any], artifacts_dir: pathlib.Path,
                    source_archive: pathlib.Path, site: pathlib.Path) -> None:
    site.mkdir(parents=True, exist_ok=True)
    for item in lock["artifacts"]:
        wheel = artifacts_dir / item["filename"]
        if not wheel.is_file() or sha256(wheel) != item["sha256"]:
            raise ValueError(f"artifact missing or hash mismatch: {item['filename']}")
        install_wheel(wheel, site)
    source_metadata(source_archive)
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        extract_tar(source_archive, root)
        package = next(root.glob("*/jellyfin_mpv_shim"), None)
        if package is None or not (package / "mpv_shim.py").is_file():
            raise ValueError("pinned source archive lacks the jellyfin_mpv_shim package")
        shutil.copytree(package, site / "jellyfin_mpv_shim", dirs_exist_ok=False)


PROBE = r'''import ctypes, ctypes.util, importlib, json, pathlib, sys
site, libmpv = pathlib.Path(sys.argv[1]).resolve(), sys.argv[2]
sys.path.insert(0, str(site))
find_library = ctypes.util.find_library
ctypes.util.find_library = lambda name: libmpv if name == "mpv" else find_library(name)
result = {"target_python": sys.version, "machine": __import__("platform").machine(),
          "libmpv": libmpv, "imports": {}}
for module in sys.argv[3:]:
    try:
        origin = pathlib.Path(importlib.import_module(module).__file__).resolve()
        result["imports"][module] = "OK" if origin.is_relative_to(site) else f"FAIL: imported from {origin}"
    except Exception as exc:
        result["imports"][module] = f"FAIL: {type(exc).__name__}: {exc}"
ctypes.CDLL(libmpv)
result["passed"] = all(v == "OK" for v in result["imports"].values())
print(json.dumps(result))
'''


def probe(rootfs: pathlib.Path, site: pathlib.Path) -> dict[str, Any]:
    """Import the closure on the target interpreter inside a chroot of the rootfs.

    A chroot (not ``qemu -L``) is required: Debian's update-alternatives links
    (e.g. libblas.so.3 -> /etc/alternatives/...) are absolute, and qemu's -L
    prefix does not apply to symlink targets, so they would resolve against
    the build host instead of the target.
    """
    if not (rootfs / "usr/bin/python3").exists():
        raise ValueError("target rootfs lacks /usr/bin/python3")
    libmpv = next(iter(sorted((rootfs / "usr/lib/aarch64-linux-gnu").glob("libmpv.so.*"))), None)
    if libmpv is None:
        raise ValueError("target rootfs lacks libmpv.so.*")
    qemu = shutil.which(QEMU)
    if qemu is None:
        raise ValueError(f"{QEMU} is required to run the arm64 probe")
    # Stage the closure and the emulator inside the rootfs (a scratch copy).
    staged_site = rootfs / "tmp/ashipaos-probe/site-packages"
    shutil.copytree(site, staged_site)
    staged_qemu = rootfs / "usr/bin" / QEMU
    if not staged_qemu.exists():
        shutil.copy2(qemu, staged_qemu)
    sudo = [] if os.geteuid() == 0 else ["sudo", "-n"]
    command = [*sudo, "chroot", str(rootfs), "/usr/bin/env", "-i", "PATH=/usr/bin:/bin",
               "HOME=/tmp", "LC_ALL=C.UTF-8", "/usr/bin/python3", "-I", "-S", "-B", "-c", PROBE,
               "/tmp/ashipaos-probe/site-packages",
               "/" + str(libmpv.relative_to(rootfs)), *PROBE_MODULES]
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(f"target probe failed: {completed.stderr[-12000:]}")
    result = json.loads(completed.stdout)
    if not result.get("passed") or result.get("machine") != "aarch64":
        raise RuntimeError(f"target imports failed: {result}")
    return result


def cmd_update_lock(args: argparse.Namespace) -> int:
    with tempfile.TemporaryDirectory(prefix="ashipaos-lock-") as tmp:
        work = pathlib.Path(tmp)
        source = work / "source.tar.gz"
        download(SOURCE_URL, source, SOURCE_SHA256)
        meta = source_metadata(source)
        artifacts = report_artifacts(pip_report(REQUIRED, work, require_hashes=False))
    lock = {"schema": LOCK_SCHEMA, "status": "RESOLVED",
            "target": {"python_version": PYTHON_VERSION, "python_tag": PYTHON_TAG, "abi_tag": ABI_TAG,
                       "platform_tag": PLATFORM_TAG, "architecture": "arm64"},
            "source": {k: meta[k] for k in ("name", "version", "commit", "url", "sha256", "requirements")},
            "forbidden_debian_package": FORBIDDEN[0],
            "artifacts": sorted(artifacts, key=lambda a: canonicalize_name(a["name"]))}
    args.lock.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
    load_lock(args.lock)
    print(f"wrote {args.lock} ({len(artifacts)} artifacts)")
    return 0


def cmd_resolve(args: argparse.Namespace) -> int:
    evidence: dict[str, Any] = {"schema": EVIDENCE_SCHEMA, "status": "BLOCKED", "lock": str(args.lock)}
    try:
        lock = load_lock(args.lock)
        evidence["lock_sha256"] = sha256(args.lock)
        evidence["target"] = lock["target"]
        args.artifacts_dir.mkdir(parents=True, exist_ok=True)
        source = args.artifacts_dir / "source.tar.gz"
        download(SOURCE_URL, source, SOURCE_SHA256)
        evidence["source"] = source_metadata(source)
        # The probe runs as root in a chroot; never fail the step on cleanup.
        with tempfile.TemporaryDirectory(prefix="ashipaos-resolve-", ignore_cleanup_errors=True) as tmp:
            work = pathlib.Path(tmp)
            verify_closure(lock, work)
            for item in lock["artifacts"]:
                download(item["url"], args.artifacts_dir / item["filename"], item["sha256"])
            site = work / "site-packages"
            install_closure(lock, args.artifacts_dir, source, site)
            rootfs = work / "rootfs"
            rootfs.mkdir()
            extract_tar(args.rootfs, rootfs)
            evidence["probe"] = probe(rootfs, site)
        evidence.update({"status": "RESOLVED", "artifacts": lock["artifacts"]})
    except Exception as exc:  # recorded as evidence, then fails the step
        evidence["error"] = f"{type(exc).__name__}: {exc}"
        print(f"Jellyfin MPV Shim resolution failed: {evidence['error']}", file=sys.stderr)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0 if evidence["status"] == "RESOLVED" else 1


def cmd_install(args: argparse.Namespace) -> int:
    lock = load_lock(args.lock)
    resolution = json.loads(args.resolution.read_text(encoding="utf-8"))
    if resolution.get("status") != "RESOLVED" or resolution.get("lock_sha256") != sha256(args.lock):
        raise SystemExit("resolution evidence is not RESOLVED for this exact lock")
    install_closure(lock, args.artifacts_dir, args.artifacts_dir / "source.tar.gz", args.site)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lock", type=pathlib.Path, default=LOCK_FILE)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("update-lock").set_defaults(func=cmd_update_lock)
    resolve = commands.add_parser("resolve")
    resolve.add_argument("--rootfs", required=True, type=pathlib.Path)
    resolve.add_argument("--artifacts-dir", required=True, type=pathlib.Path)
    resolve.add_argument("--output", required=True, type=pathlib.Path)
    resolve.set_defaults(func=cmd_resolve)
    install = commands.add_parser("install")
    install.add_argument("--resolution", required=True, type=pathlib.Path)
    install.add_argument("--artifacts-dir", required=True, type=pathlib.Path)
    install.add_argument("--site", required=True, type=pathlib.Path)
    install.set_defaults(func=cmd_install)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
