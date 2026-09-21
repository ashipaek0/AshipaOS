#!/usr/bin/env python3
"""Resolve and probe the Jellyfin MPV Shim closure for Debian arm64."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

from packaging.utils import parse_wheel_filename

ROOT = pathlib.Path(__file__).resolve().parents[3]
BASE_PATH = ROOT / "layers/layer5-application/scripts/resolve-dependencies.py"
spec = importlib.util.spec_from_file_location("x86_resolver", BASE_PATH)
assert spec and spec.loader
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

PYTHON_TAG = "cp311"
ABI_TAG = "cp311"
PLATFORM_TAG = "manylinux_2_27_aarch64"
QEMU = "qemu-aarch64-static"


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_extract(archive: pathlib.Path, destination: pathlib.Path) -> None:
    with tarfile.open(archive, "r:gz") as tar:
        members = tar.getmembers()
        root = destination.resolve()
        for member in members:
            target = (destination / member.name).resolve()
            if target != root and not str(target).startswith(str(root) + "/"):
                raise ValueError("archive contains an unsafe path")
        tar.extractall(destination, members=members)


def download(url: str, destination: pathlib.Path, expected: str) -> None:
    with urllib.request.urlopen(url, timeout=120) as response, destination.open("wb") as out:
        shutil.copyfileobj(response, out)
    actual = sha256(destination)
    if actual != expected:
        raise ValueError(f"SHA-256 mismatch for {destination.name}: {actual} != {expected}")


def target_python(rootfs: pathlib.Path) -> pathlib.Path:
    candidates = [rootfs / "usr/bin/python3.11", rootfs / "usr/bin/python3"]
    candidates.extend(sorted(rootfs.rglob("python3.11")))
    candidates.extend(sorted(rootfs.rglob("python3")))
    for candidate in candidates:
        if candidate.is_file() and not candidate.name.endswith("-config"):
            return candidate
    discovered = [str(p.relative_to(rootfs)) for p in rootfs.rglob("*python3*")][:40]
    raise ValueError("ARM64 target rootfs does not contain Python 3.11; discovered: " + ", ".join(discovered))


def probe(rootfs: pathlib.Path, source_root: pathlib.Path, wheel_dir: pathlib.Path) -> dict:
    python = target_python(rootfs)
    libmpv = next((p for p in sorted(rootfs.rglob("libmpv.so*")) if p.is_file()), None)
    if libmpv is None:
        raise ValueError("ARM64 target rootfs does not contain libmpv.so*")
    target = pathlib.Path(tempfile.mkdtemp(prefix="ashipaos-arm64-python-"))
    try:
        for wheel in sorted(wheel_dir.glob("*.whl")):
            subprocess.run([sys.executable, "-m", "pip", "install", "--no-index", "--no-deps", "--only-binary=:all:", "--target", str(target), str(wheel)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        script = r'''import ctypes, ctypes.util, importlib, json, pathlib, sys
root, source, packages, libmpv = map(pathlib.Path, sys.argv[1:])
sys.path[:] = [str(root / "usr/lib/python3.11"), str(root / "usr/lib/python3/dist-packages"), str(packages), str(source)]
original = ctypes.util.find_library
ctypes.util.find_library = lambda name: str(libmpv) if name == "mpv" else original(name)
result = {"imports": {}, "libmpv": str(libmpv), "target_machine": "aarch64", "target_python": sys.version}
for module in ("jellyfin_mpv_shim", "mpv", "jellyfin_apiclient_python", "python_mpv_jsonipc", "requests", "PIL"):
    try:
        loaded = importlib.import_module(module)
        result["imports"][module] = "OK"
        origin = getattr(loaded, "__file__", "")
        if origin and not (pathlib.Path(origin).resolve().is_relative_to(packages.resolve()) or pathlib.Path(origin).resolve().is_relative_to(source.resolve())):
            raise RuntimeError(f"host-masked import: {origin}")
    except Exception as exc:
        result["imports"][module] = f"FAIL: {type(exc).__name__}: {exc}"
ctypes.CDLL(str(libmpv))
result["passed"] = all(value == "OK" for value in result["imports"].values())
print(json.dumps(result))
'''
        env = {"PATH": "/usr/bin:/bin", "HOME": "/tmp", "PYTHONNOUSERSITE": "1"}
        command = [QEMU, "-L", str(rootfs), str(python), "-I", "-S", "-c", script, str(rootfs), str(source_root), str(target), str(libmpv)]
        completed = subprocess.run(command, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        if completed.returncode != 0:
            raise RuntimeError(f"ARM64 probe failed: {completed.stderr[-12000:]}")
        result = json.loads(completed.stdout)
        result["stderr"] = completed.stderr
        if not result.get("passed"):
            raise RuntimeError(f"ARM64 imports failed: {result}")
        return result
    finally:
        shutil.rmtree(target, ignore_errors=True)


def main() -> int:
    parser = __import__("argparse").ArgumentParser()
    parser.add_argument("--rootfs", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--artifacts-dir", required=True, type=pathlib.Path)
    args = parser.parse_args()
    evidence = {"schema": "ashipaos.jellyfin-mpv-shim.dependency-lock.v1", "status": "BLOCKED", "target": {"python_tag": PYTHON_TAG, "abi_tag": ABI_TAG, "platform_tag": PLATFORM_TAG, "architecture": "arm64"}}
    try:
        with tempfile.TemporaryDirectory(prefix="ashipaos-arm64-resolver-") as tmp:
            work = pathlib.Path(tmp)
            source = work / "source.tar.gz"
            download(base.SOURCE_URL, source, base.SOURCE_SHA256)
            meta = base.source_metadata(source)
            evidence["source"] = meta
            reports = {}
            for kind, requirements in (("runtime", meta["requirements"]), ("build", meta["build_requirements"])):
                requirements_file = work / f"{kind}.txt"
                report_file = work / f"{kind}.json"
                requirements_file.write_text("\n".join(requirements) + "\n", encoding="utf-8")
                subprocess.run([sys.executable, "-m", "pip", "install", "--dry-run", "--ignore-installed", "--no-cache-dir", "--only-binary=:all:", "--report", str(report_file), "--python-version", "3.11", "--implementation", "cp", "--abi", ABI_TAG, "--platform", PLATFORM_TAG, "-r", str(requirements_file)], check=True)
                reports[kind] = json.loads(report_file.read_text(encoding="utf-8"))
            runtime = base.report_artifacts(reports["runtime"], PYTHON_TAG, ABI_TAG, PLATFORM_TAG, meta["requirements"])
            build = base.report_artifacts(reports["build"], PYTHON_TAG, ABI_TAG, PLATFORM_TAG, meta["build_requirements"])
            artifacts = runtime + [item for item in build if item["name"] not in {x["name"] for x in runtime}]
            args.artifacts_dir.mkdir(parents=True, exist_ok=True)
            downloaded = []
            for item in artifacts:
                destination = args.artifacts_dir / item["filename"]
                download(item["url"], destination, item["sha256"])
                downloaded.append(item)
            source_root = work / "source"
            source_root.mkdir()
            safe_extract(source, source_root)
            source_project = next(source_root.glob("*/jellyfin_mpv_shim"), None)
            if source_project is None:
                raise ValueError("source package missing")
            probe_result = probe(args.rootfs, source_project.parent, args.artifacts_dir)
            evidence.update({"status": "RESOLVED", "artifacts": downloaded, "build_artifacts": build, "abi": probe_result})
    except Exception as exc:
        evidence["error"] = f"{type(exc).__name__}: {exc}"
        print(f"ARM64 dependency resolution failed: {evidence['error']}", file=sys.stderr)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0 if evidence["status"] == "RESOLVED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
