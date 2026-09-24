#!/usr/bin/env bash
# CI: CycloneDX SBOM for the A95X image, generated from what was actually built:
# the rootfs dpkg database, the Jellyfin MPV Shim lock, and the release images.
# Usage: ci-generate-sbom.sh <output.json> <rootfs.tar.gz> <images_dir>
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -eq 3 ]] || { printf 'Usage: %s <output.json> <rootfs.tar.gz> <images_dir>\n' "$(basename "$0")" >&2; exit 2; }
OUTPUT="$1" ROOTFS="$2" IMAGES="$3"
[[ -s "$ROOTFS" ]] || { printf 'rootfs tarball not found: %s\n' "$ROOTFS" >&2; exit 1; }
[[ -d "$IMAGES" ]] || { printf 'images directory not found: %s\n' "$IMAGES" >&2; exit 1; }

commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
tag="$(git -C "$REPO_ROOT" describe --tags --exact-match 2>/dev/null || printf '')"
mkdir -p "$(dirname "$OUTPUT")"

python3 - "$OUTPUT" "$ROOTFS" "$IMAGES" "$REPO_ROOT/layers/layer5-application/config/dependencies.lock.json" \
    "$commit" "$tag" "${GITHUB_REPOSITORY:-ashipaek0/AshipaOS}" <<'PY'
import hashlib, json, pathlib, sys, tarfile, time
output, rootfs, images, lock_path, commit, tag, repository = sys.argv[1:]

def dpkg_status(archive):
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar:
            if member.name.lstrip("./") == "var/lib/dpkg/status":
                return tar.extractfile(member).read().decode("utf-8")
    raise SystemExit("rootfs has no var/lib/dpkg/status")

def packages(text):
    for stanza in text.split("\n\n"):
        fields = {}
        for line in stanza.splitlines():
            if line and not line[0].isspace() and ":" in line:
                key, value = line.split(":", 1)
                fields[key] = value.strip()
        if fields.get("Status") == "install ok installed":
            yield fields

components = []
for pkg in sorted(packages(dpkg_status(rootfs)), key=lambda p: p["Package"]):
    arch = pkg.get("Architecture", "all")
    component = {"type": "library", "name": pkg["Package"], "version": pkg["Version"],
                 "purl": f"pkg:deb/debian/{pkg['Package']}@{pkg['Version']}?arch={arch}&distro=debian-13",
                 "supplier": {"name": pkg.get("Maintainer", "Debian")}}
    if pkg.get("Source"):
        component["properties"] = [{"name": "debian:source", "value": pkg["Source"]}]
    components.append(component)

lock = json.loads(pathlib.Path(lock_path).read_text(encoding="utf-8"))
source = lock["source"]
components.append({"type": "application", "name": source["name"], "version": source["version"],
                   "purl": f"pkg:github/jellyfin/jellyfin-mpv-shim@{source['commit']}",
                   "hashes": [{"alg": "SHA-256", "content": source["sha256"]}]})
for artifact in lock["artifacts"]:
    components.append({"type": "library", "name": artifact["name"], "version": artifact["version"],
                       "purl": f"pkg:pypi/{artifact['name'].lower()}@{artifact['version']}",
                       "hashes": [{"alg": "SHA-256", "content": artifact["sha256"]}]})

image_hashes = []
for image in sorted(pathlib.Path(images).glob("*.img.gz")):
    h = hashlib.sha256()
    with image.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h.update(chunk)
    image_hashes.append({"name": image.name, "sha256": h.hexdigest()})
if not image_hashes:
    raise SystemExit("no release images to describe")

sbom = {
    "bomFormat": "CycloneDX", "specVersion": "1.5", "version": 1,
    "metadata": {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "tools": [{"vendor": "AshipaOS", "name": "ci-generate-sbom.sh"}],
        "component": {"type": "operating-system", "name": "AshipaOS A95X F3 Air",
                      "version": tag or commit, "purl": f"pkg:github/{repository}@{commit}",
                      "properties": [{"name": "image", "value": f"{i['name']} sha256:{i['sha256']}"}
                                     for i in image_hashes]},
    },
    "components": components,
}
pathlib.Path(output).write_text(json.dumps(sbom, indent=2) + "\n", encoding="utf-8")
print(f"SBOM: {len(components)} components -> {output}")
PY
