"""Host regressions for appliance startup and TV layout; no display required."""
import ast
import hashlib
import importlib.util
import json
import pathlib
import os
import subprocess
import sys
import tempfile
import textwrap
import types
import unittest

LAYER = pathlib.Path(__file__).resolve().parents[1]
DEFAULTS = LAYER / 'files/usr/share/ashipaos/jellyfin-mpv-shim'
spec = importlib.util.spec_from_file_location('configure', DEFAULTS / 'configure.py')
configure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure)


class ApplianceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.config = pathlib.Path(self.tmp.name)

    def test_fresh_settings_are_private_and_repeatable(self):
        configure.prepare(self.config, DEFAULTS)
        for name in ('conf.json', 'mpv.conf'):
            self.assertEqual((self.config / name).stat().st_mode & 0o777, 0o600)
            self.assertEqual((self.config / name).read_bytes(), (DEFAULTS / name).read_bytes())
        configure.prepare(self.config, DEFAULTS)
        self.assertFalse((self.config / 'mpv.conf.pre-tv-fix').exists())

    def test_custom_settings_are_preserved(self):
        (self.config / 'conf.json').write_text('{"ui_scale": 2, "server": "keep"}')
        (self.config / 'mpv.conf').write_text('audio-spdif=ac3\nhwdec=no\n')
        before = {p.name: p.read_bytes() for p in self.config.iterdir()}
        configure.prepare(self.config, DEFAULTS)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.config.iterdir()})

    def test_symlink_configuration_is_rejected(self):
        (self.config / 'conf.json').symlink_to(DEFAULTS / 'conf.json')
        with self.assertRaises(ValueError):
            configure.prepare(self.config, DEFAULTS)

    def test_stock_migration_preserves_backup(self):
        # Historical full file, checked against the real migration preimage.
        old = (LAYER / 'tests/fixtures/legacy-mpv.conf').read_bytes()
        self.assertEqual(hashlib.sha256(old).hexdigest(), configure.LEGACY_MPV_SHA256)
        (self.config / 'mpv.conf').write_bytes(old)
        configure.prepare(self.config, DEFAULTS)
        self.assertEqual((self.config / 'mpv.conf.pre-tv-fix').read_bytes(), old)
        self.assertEqual((self.config / 'mpv.conf').read_bytes(), (DEFAULTS / 'mpv.conf').read_bytes())
        configure.prepare(self.config, DEFAULTS)
        self.assertEqual((self.config / 'mpv.conf.pre-tv-fix').read_bytes(), old)

    def test_conflicting_backup_cannot_be_overwritten(self):
        old = (LAYER / 'tests/fixtures/legacy-mpv.conf').read_bytes()
        (self.config / 'mpv.conf').write_bytes(old)
        (self.config / 'mpv.conf.pre-tv-fix').write_text('keep')
        with self.assertRaises(ValueError):
            configure.prepare(self.config, DEFAULTS)
        self.assertEqual((self.config / 'mpv.conf').read_bytes(), old)

    def test_recovery_options(self):
        path = self.config / 'playback.txt'
        self.assertEqual(configure.runtime_args(path), [])
        path.write_bytes(b'\xef\xbb\xbfUI_SCALE=2.5\r\nVIDEO_DECODE=software # recovery\r\n')
        self.assertEqual(configure.runtime_args(path), ['--scale', '2.5', '--disable-hwdec'])
        self.assertEqual(configure.runtime_args(DEFAULTS / 'playback.txt'), [])

    def test_invalid_recovery_options(self):
        path = self.config / 'playback.txt'
        for text in ('UI_SCALE=nan', 'UI_SCALE=inf', 'UI_SCALE=0', 'UI_SCALE=5',
                     'UI_SCALE=$(touch /tmp/unsafe)', 'VIDEO_DECODE=unknown',
                     'UI_SCALE=1\nUI_SCALE=2', 'LD_PRELOAD=bad', 'missing_equals'):
            with self.subTest(text=text):
                path.write_text(text)
                with self.assertRaises(ValueError):
                    configure.runtime_args(path)

    def test_startup_executes_player_with_recovery_and_forwarded_arguments(self):
        recovery = self.config / 'playback.txt'
        recovery.write_text('UI_SCALE=2\nVIDEO_DECODE=software\n')
        player = self.config / 'player'
        player.write_text('#!' + sys.executable + '\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
        player.chmod(0o700)
        result = subprocess.run(
            [sys.executable, str(DEFAULTS / 'configure.py'), str(self.config),
             str(player), '--scale', '1.5'],
            env={**os.environ, 'ASHIPAOS_PLAYBACK_CONFIG': str(recovery)},
            capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout),
                         ['--scale', '2.0', '--disable-hwdec', '--scale', '1.5'])
        recovery.write_text('UI_SCALE=nan')
        result = subprocess.run(
            [sys.executable, str(DEFAULTS / 'configure.py'), str(self.config), str(player)],
            env={**os.environ, 'ASHIPAOS_PLAYBACK_CONFIG': str(recovery)},
            capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), [])
        self.assertIn('ignoring playback.txt', result.stderr)

    def test_tv_scale_uses_viewport_and_honors_user_choice(self):
        # Execute the actual method installed by the pinned patch, isolating
        # only its settings import and renderer (no GPU in a host unit test).
        patch = json.loads((LAYER / 'patches/tv-scale.json').read_text())
        tree = ast.parse(textwrap.dedent(patch['new']))
        method = tree.body[0]
        method.body = [node for node in method.body if not isinstance(node, ast.ImportFrom)]
        settings = types.SimpleNamespace(ui_scale=None)
        scaling = types.SimpleNamespace(set_scale=lambda value: value)
        namespace = dict(settings=settings, scaling=scaling, log=types.SimpleNamespace(info=lambda *a: None))
        # Capture the value passed to the actual scaling boundary.
        values = []
        scaling.set_scale = lambda value: values.append(value) or value
        exec(compile(tree, '<tv-scale>', 'exec'), namespace)
        resolve = namespace['_resolve_scale']
        for size, expected in (((1280,720),1), ((1920,1080),1.5), ((3840,2160),3),
                               ((1024,768),0.8), ((0,0),0.5), ((7680,4320),4)):
            with self.subTest(size=size):
                resolve(types.SimpleNamespace(size=size))
                self.assertEqual(values[-1], expected)
                if size[0] >= 1280 and size[1] >= 720 and expected < 4:
                    self.assertGreaterEqual(size[0] / expected, 1280)
                    self.assertGreaterEqual(size[1] / expected, 720)
        settings.ui_scale = 2
        resolve(types.SimpleNamespace(size=(1920,1080)))
        self.assertEqual(values[-1], 2)


if __name__ == '__main__':
    unittest.main()
