#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location(
    'wtclean_safety', Path(__file__).resolve().parents[1] / 'lib/wtclean_safety.py')
safety = importlib.util.module_from_spec(spec)
spec.loader.exec_module(safety)


class RemovalPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'checkout'
        self.root.mkdir()

    def test_symlink_target_is_never_traversed(self):
        external = Path(self.temp.name) / 'external'
        external.mkdir()
        sentinel = external / 'important'
        sentinel.write_text('preserve')
        (self.root / 'link').symlink_to(external, target_is_directory=True)
        (self.root / 'dangling').symlink_to(external / 'missing')
        safety.check_removal(str(self.root), mountpoints=set())
        self.assertEqual(sentinel.read_text(), 'preserve')

    @unittest.skipIf(os.geteuid() == 0, 'root bypasses directory write permissions')
    def test_ignored_unwritable_directory_is_rejected(self):
        generated = self.root / 'ignored'
        generated.mkdir()
        (generated / 'file').write_text('data')
        generated.chmod(0o555)
        self.addCleanup(generated.chmod, 0o755)
        with self.assertRaisesRegex(safety.UnsafeRemoval, 'permissions'):
            safety.check_removal(str(self.root), mountpoints=set())
        self.assertEqual((generated / 'file').read_text(), 'data')

    def test_same_device_bind_mount_requires_review(self):
        mounted = self.root / 'mounted'
        mounted.mkdir()
        with self.assertRaisesRegex(safety.UnsafeRemoval, 'mounted filesystem'):
            safety.check_removal(str(self.root), mountpoints={str(mounted)})

    def test_mountinfo_unescapes_paths(self):
        self.assertEqual(safety.linux_mountpoints(
            '35 23 8:1 / /tmp/a\\040b rw - ext4 /dev/x rw\n'), {'/tmp/a b'})

    def test_invalid_mountinfo_fails_closed(self):
        with self.assertRaises(safety.UnsafeRemoval):
            safety.linux_mountpoints('not mountinfo')

    def prepare_dirty_git(self):
        def git(*args):
            return subprocess.check_output(['git', '-C', str(self.root), *args],
                                           stderr=subprocess.DEVNULL)
        git('init', '-q')
        git('config', 'user.name', 'Test')
        git('config', 'user.email', 'test@example.com')
        (self.root / 'file').write_text('base\n')
        git('add', 'file')
        git('-c', 'commit.gpgsign=false', 'commit', '-qm', 'base')
        (self.root / 'file').write_text('pending\n')
        return git

    def test_fingerprint_detects_content_with_preserved_mtime(self):
        self.prepare_dirty_git()
        file = self.root / 'file'
        times = (file.stat().st_atime_ns, file.stat().st_mtime_ns)
        before = safety.dirty_fingerprint(str(self.root))
        file.write_text('changed\n')
        os.utime(file, ns=times)
        self.assertNotEqual(before, safety.dirty_fingerprint(str(self.root)))

    def test_fingerprint_distinguishes_index_and_worktree(self):
        git = self.prepare_dirty_git()
        before = safety.dirty_fingerprint(str(self.root))
        git('add', 'file')
        self.assertNotEqual(before, safety.dirty_fingerprint(str(self.root)))

    def test_fingerprint_does_not_follow_untracked_symlinks(self):
        self.prepare_dirty_git()
        external = Path(self.temp.name) / 'external'
        external.write_text('outside')
        link = self.root / 'untracked-link'
        link.symlink_to(external)
        before = safety.dirty_fingerprint(str(self.root))
        external.write_text('outside changed')
        self.assertEqual(before, safety.dirty_fingerprint(str(self.root)))
        link.unlink()
        link.symlink_to(external.with_name('missing'))
        self.assertNotEqual(before, safety.dirty_fingerprint(str(self.root)))

    def test_fingerprint_fails_closed_on_git_error(self):
        self.prepare_dirty_git()
        with mock.patch.object(safety.subprocess, 'check_output',
                               side_effect=subprocess.CalledProcessError(1, 'git')):
            with self.assertRaises(subprocess.CalledProcessError):
                safety.dirty_fingerprint(str(self.root))

    def test_symlink_checkout_root_is_rejected(self):
        link = Path(self.temp.name) / 'checkout-link'
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(safety.UnsafeRemoval):
            safety.check_removal(str(link), mountpoints=set())


if __name__ == '__main__':
    unittest.main()
