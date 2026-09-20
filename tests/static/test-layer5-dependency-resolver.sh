#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util, pathlib, sys, tempfile, tarfile
from unittest import mock
root = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("resolver", root / "layers/layer5-application/scripts/resolve-dependencies.py")
resolver = importlib.util.module_from_spec(spec); spec.loader.exec_module(resolver)

def archive(text, constants='CLIENT_VERSION = "3.0.0"', package=True):
    tmp = pathlib.Path(tempfile.mkdtemp()); root = tmp / "jellyfin-mpv-shim-9970b2d"; p = root / "pyproject.toml"; p.parent.mkdir(parents=True); p.write_text(text, encoding="utf-8")
    if package:
        package_dir = root / "jellyfin_mpv_shim"; package_dir.mkdir(); (package_dir / "__init__.py").write_text("", encoding="utf-8"); (package_dir / "constants.py").write_text(constants + "\n", encoding="utf-8")
    out = tmp / "source.tar.gz"
    with tarfile.open(out, "w:gz") as tar: tar.add(root, arcname=root.name)
    return out

base = '''[build-system]\nrequires = ["setuptools>=77", "wheel"]\n[project]\nname = "jellyfin-mpv-shim"\ndynamic = ["version"]\nrequires-python = ">=3.9"\ndependencies = ["python-mpv>=1.0.8", "jellyfin-apiclient-python>=1.18.0", "python-mpv-jsonipc>=1.4.0", "requests", "pillow"]\n[tool.setuptools.dynamic]\nversion = {attr = "jellyfin_mpv_shim.constants.CLIENT_VERSION"}\n'''
with tempfile.TemporaryDirectory() as td:
    good = archive(base); good_hash = resolver.sha256(good)
    assert resolver.source_metadata(good, good_hash)["version"] == "3.0.0"
    try: resolver.source_metadata(good, "0" * 64); raise AssertionError("hash mutant accepted")
    except ValueError as e: assert "SHA-256" in str(e)
    tagged = archive(base, 'CLIENT_VERSION = "2.9.0"')
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
    required = ["python-mpv", "jellyfin-apiclient-python", "python-mpv-jsonipc", "requests", "pillow"]
    complete = {"install": [item(name) for name in required]}
    assert len(resolver.report_artifacts(complete, "cp311", "cp311", "manylinux_2_17_x86_64")) == len(required)
    incomplete = {"install": [item(name) for name in required[:-1]]}
    try: resolver.report_artifacts(incomplete, "cp311", "cp311", "manylinux_2_17_x86_64"); raise AssertionError("incomplete report accepted")
    except ValueError as e: assert "incomplete" in str(e) and "pillow" in str(e)
    build_complete = {"install": [item(name) for name in ("setuptools", "wheel")]}
    assert len(resolver.report_artifacts(build_complete, "cp311", "cp311", "manylinux_2_17_x86_64", resolver.BUILD)) == 2
    missing_package = archive(base, package=False)
    try: resolver.source_metadata(missing_package, resolver.sha256(missing_package)); raise AssertionError("missing app package accepted")
    except ValueError as e: assert "constants.py" in str(e)
    duplicate = {"install": [*complete["install"], item("python-mpv", "python_mpv-2.0-py3-none-any.whl")]}
    try: resolver.report_artifacts(duplicate, "cp311", "cp311", "manylinux_2_17_x86_64"); raise AssertionError("duplicate report accepted")
    except ValueError as e: assert "duplicate" in str(e)
    bad_abi = {"install": [item(name) for name in required[:-1]] + [item("pillow", "pillow-1.0-cp310-cp310-manylinux_2_17_x86_64.whl")]}
    try: resolver.report_artifacts(bad_abi, "cp311", "cp311", "manylinux_2_17_x86_64"); raise AssertionError("ABI mutant accepted")
    except ValueError as e: assert "ABI" in str(e)
    with mock.patch("ctypes.util.find_library", return_value="libmpv.so"), mock.patch.dict(sys.modules, {"mpv": object(), "requests": object()}):
        evidence = resolver.probe_abi("cp311", "cp311", "manylinux_2_17_x86_64")
    assert evidence["passed"] is False and "verified dependency artifacts" in evidence["error"]
    assert resolver.origin_is_isolated("/usr/lib/python3/dist-packages/requests/__init__.py", (pathlib.Path("/tmp/target"),)) is False
    assert resolver.origin_is_isolated("/tmp/target/requests/__init__.py", (pathlib.Path("/tmp/target"),)) is True
print("layer5-dependency-resolver: closure/normalization/ABI isolation regressions: PASS")
PY
