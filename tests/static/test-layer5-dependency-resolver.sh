#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util, pathlib, sys, tempfile, tarfile
from unittest import mock
root = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("resolver", root / "layers/layer5-application/scripts/resolve-dependencies.py")
resolver = importlib.util.module_from_spec(spec); spec.loader.exec_module(resolver)

def archive(text, name="jellyfin-mpv-shim-9970b2d/pyproject.toml"):
    tmp = pathlib.Path(tempfile.mkdtemp()); p = tmp / name; p.parent.mkdir(parents=True); p.write_text(text, encoding="utf-8")
    out = tmp / "source.tar.gz"
    with tarfile.open(out, "w:gz") as tar: tar.add(p, arcname=name)
    return out

base = '''[build-system]\nrequires = ["setuptools>=77", "wheel"]\n[project]\nname = "jellyfin-mpv-shim"\nversion = "3.0.0"\nrequires-python = ">=3.9"\ndependencies = ["python-mpv>=1.0.8", "jellyfin-apiclient-python>=1.18.0", "python-mpv-jsonipc>=1.4.0", "requests", "pillow"]\n'''
with tempfile.TemporaryDirectory() as td:
    good = archive(base); good_hash = resolver.sha256(good)
    assert resolver.source_metadata(good, good_hash)["version"] == "3.0.0"
    try: resolver.source_metadata(good, "0" * 64); raise AssertionError("hash mutant accepted")
    except ValueError as e: assert "SHA-256" in str(e)
    tagged = archive(base.replace('version = "3.0.0"', 'version = "2.9.0"'))
    try: resolver.source_metadata(tagged, resolver.sha256(tagged)); raise AssertionError("tag mutant accepted")
    except ValueError as e: assert "name/version" in str(e)
    forbidden = archive(base + '\n# python3-mpv\n')
    try: resolver.source_metadata(forbidden, resolver.sha256(forbidden)); raise AssertionError("forbidden package accepted")
    except ValueError as e: assert "forbidden" in str(e)
    try: resolver.report_artifacts({}, "cp311", "cp311", "manylinux_2_17_x86_64"); raise AssertionError("unresolved report accepted")
    except ValueError as e: assert "no install entries" in str(e)
    def item(name, filename=None):
        filename = filename or (name.replace("-", "_") + "-1.0-py3-none-any.whl")
        return {"metadata": {"name": name, "version": "1.0"}, "download_info": {"url": "https://example.invalid/" + filename, "archive_info": {"hashes": {"sha256": "a" * 64}}}}
    required = ["python-mpv", "jellyfin-apiclient-python", "python-mpv-jsonipc", "requests", "pillow", "setuptools", "wheel"]
    complete = {"install": [item(name) for name in required]}
    assert len(resolver.report_artifacts(complete, "cp311", "cp311", "manylinux_2_17_x86_64")) == len(required)
    incomplete = {"install": [item(name) for name in required[:-1]]}
    try: resolver.report_artifacts(incomplete, "cp311", "cp311", "manylinux_2_17_x86_64"); raise AssertionError("incomplete report accepted")
    except ValueError as e: assert "incomplete" in str(e) and "wheel" in str(e)
    duplicate = {"install": [*complete["install"], item("setuptools", "setuptools-2.0-py3-none-any.whl")]}
    try: resolver.report_artifacts(duplicate, "cp311", "cp311", "manylinux_2_17_x86_64"); raise AssertionError("duplicate report accepted")
    except ValueError as e: assert "duplicate" in str(e)
    bad_abi = {"install": [item(name) for name in required[:-1]] + [item("wheel", "wheel-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")]}
    try: resolver.report_artifacts(bad_abi, "cp311", "cp311", "manylinux_2_17_x86_64"); raise AssertionError("ABI mutant accepted")
    except ValueError as e: assert "ABI" in str(e)
    with mock.patch("ctypes.util.find_library", return_value="libmpv.so"), mock.patch.dict(sys.modules, {"mpv": object(), "requests": object()}):
        evidence = resolver.probe_abi("cp311", "cp311", "manylinux_2_17_x86_64")
    assert evidence["passed"] is False and "verified downloaded artifacts" in evidence["error"]
print("layer5-dependency-resolver: closure/normalization/ABI isolation regressions: PASS")
PY
