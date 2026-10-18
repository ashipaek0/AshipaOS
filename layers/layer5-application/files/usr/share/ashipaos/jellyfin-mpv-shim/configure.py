"""Prepare persistent settings without replacing user customizations."""
import hashlib
import math
import os
from pathlib import Path
import sys
import tempfile


# The unmodified mpv.conf shipped by A95XF3-Air at 69ea3a3. Only this exact
# preimage is upgraded automatically; user-edited files remain untouched.
LEGACY_MPV_SHA256 = "a390f0aca88e40f4431c6b8b7a9c906634a27ce51ee91b302df286c27923e358"


def atomic_write(path, data):
    fd, temporary = tempfile.mkstemp(prefix=".ashipaos-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def prepare(config, defaults):
    for name in ("conf.json", "mpv.conf"):
        target = config / name
        if target.is_symlink():
            raise ValueError(f"refusing symlink configuration: {name}")
        if not target.exists():
            atomic_write(target, (defaults / name).read_bytes())
        elif name == "mpv.conf":
            old = target.read_bytes()
            if hashlib.sha256(old).hexdigest() == LEGACY_MPV_SHA256:
                backup = config / "mpv.conf.pre-tv-fix"
                # Exclusive creation preserves earlier recovery copies.
                try:
                    fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                except FileExistsError:
                    if backup.is_symlink() or backup.read_bytes() != old:
                        raise ValueError("existing mpv.conf backup differs; refusing migration")
                else:
                    with os.fdopen(fd, "wb") as stream:
                        stream.write(old)
                        stream.flush()
                        os.fsync(stream.fileno())
                atomic_write(target, (defaults / name).read_bytes())
                print("ashipaos: upgraded stock mpv defaults; original backed up", file=sys.stderr)


def runtime_args(path):
    """Read recovery options as data, never as shell commands or environment."""
    if not path.exists():
        return []
    options = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        key, separator, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if not separator or key not in ("UI_SCALE", "VIDEO_DECODE") or key in options:
            raise ValueError("invalid or duplicate playback.txt option")
        options[key] = value
    args = []
    scale = options.get("UI_SCALE", "auto")
    if scale != "auto":
        number = float(scale)
        if not math.isfinite(number) or not 0.5 <= number <= 4:
            raise ValueError("UI_SCALE must be auto or a number from 0.5 to 4")
        args.extend(("--scale", str(number)))
    decode = options.get("VIDEO_DECODE", "auto")
    if decode == "software":
        args.append("--disable-hwdec")
    elif decode != "auto":
        raise ValueError("VIDEO_DECODE must be auto or software")
    return args


if __name__ == "__main__":
    prepare(Path(sys.argv[1]), Path(__file__).parent)
    try:
        args = runtime_args(Path(os.environ.get("ASHIPAOS_PLAYBACK_CONFIG", "/boot/firmware/playback.txt")))
    except (ValueError, OSError) as error:
        # A typo on the removable FAT partition must not prevent reaching UI.
        print(f"ashipaos: ignoring playback.txt: {error}", file=sys.stderr)
        args = []
    os.execv(sys.argv[2], [sys.argv[2], *args, *sys.argv[3:]])
