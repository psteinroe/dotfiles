#!/usr/bin/env python3
"""Conservative filesystem preflight; never changes permissions or deletes files."""
from __future__ import annotations

from pathlib import Path
import hashlib
import os
import re
import stat
import subprocess
import sys


class UnsafeRemoval(Exception):
    pass


def linux_mountpoints(mountinfo: str) -> set[str]:
    points = set()
    for line in mountinfo.splitlines():
        fields = line.split()
        if len(fields) < 6 or " - " not in line:
            raise UnsafeRemoval("unreadable mount table")
        points.add(re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), fields[4]))
    return points


def check_removal(path: str, mountpoints: set[str] | None = None) -> None:
    root = os.path.abspath(path)
    if os.path.islink(root) or not os.path.isdir(root):
        raise UnsafeRemoval(f"not a real worktree directory: {root}")
    root = os.path.realpath(root)
    parent = os.path.dirname(root)
    if root == parent or not os.access(parent, os.W_OK | os.X_OK):
        raise UnsafeRemoval(f"parent directory is not removable: {parent}")
    parent_stat = os.stat(parent)
    if (parent_stat.st_mode & stat.S_ISVTX and os.geteuid() != 0
            and os.geteuid() not in (parent_stat.st_uid, os.stat(root).st_uid)):
        raise UnsafeRemoval(f"sticky parent does not permit deletion: {parent}")
    if mountpoints is None:
        mountpoints = (linux_mountpoints(Path("/proc/self/mountinfo").read_text())
                       if sys.platform.startswith("linux") else set())
    for mount in mountpoints:
        mount = os.path.realpath(mount)
        if mount == root or mount.startswith(root + os.sep):
            raise UnsafeRemoval(f"mounted filesystem requires manual review: {mount}")

    def failed(error: OSError) -> None:
        raise error

    immutable = sum(getattr(stat, name, 0) for name in
                    ("UF_IMMUTABLE", "SF_IMMUTABLE", "UF_APPEND", "SF_APPEND"))
    for directory, dirs, files in os.walk(root, followlinks=False, onerror=failed):
        if os.path.ismount(directory):
            raise UnsafeRemoval(f"mounted directory requires manual review: {directory}")
        if not os.access(directory, os.R_OK | os.W_OK | os.X_OK):
            raise UnsafeRemoval(f"directory permissions prevent safe removal: {directory}")
        for name in [*dirs, *files]:
            entry = os.path.join(directory, name)
            if getattr(os.lstat(entry), "st_flags", 0) & immutable:
                raise UnsafeRemoval(f"immutable/append-only entry requires review: {entry}")
        # A symlink itself can be removed; its target must never be traversed.
        dirs[:] = [name for name in dirs if not os.path.islink(os.path.join(directory, name))]


def dirty_fingerprint(path: str) -> str:
    """Fingerprint nonignored local work, not just its filenames or timestamps."""
    git = ["git", "--no-optional-locks", "-C", path]
    digest = hashlib.sha256()

    def record(label: bytes, data: bytes) -> None:
        digest.update(label + b"\0" + str(len(data)).encode() + b"\0" + data)

    def query(*args: str) -> bytes:
        return subprocess.check_output([*git, *args], stderr=subprocess.DEVNULL)

    before = query("status", "--porcelain=v1", "-z", "--untracked-files=all")
    record(b"status", before)
    # Keep index vs. worktree changes distinct, including binary changes.
    # Disable external diff/textconv programs: inspection must not execute them.
    for label, extra in ((b"staged", ["--cached"]), (b"unstaged", [])):
        record(label, b"")
        with subprocess.Popen(
            [*git, "diff", "--binary", "--full-index", "--no-ext-diff",
             "--no-textconv", "--no-renames", "--ignore-submodules=none", *extra, "--"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        ) as process:
            while chunk := process.stdout.read(65536):
                digest.update(chunk)
            if process.wait():
                raise UnsafeRemoval("could not inspect dirty Git contents")

    names = query("ls-files", "--modified", "--others", "--exclude-standard", "-z")
    for name in sorted(set(names.split(b"\0")) - {b""}):
        relative = os.fsdecode(name)
        if os.path.isabs(relative) or ".." in relative.split(os.sep):
            raise UnsafeRemoval("dirty path escapes worktree")
        entry = os.path.join(path, relative)
        info = os.lstat(entry)
        record(b"path", name)
        record(b"mode", str(info.st_mode).encode())
        if stat.S_ISLNK(info.st_mode):
            record(b"symlink", os.fsencode(os.readlink(entry)))
        elif stat.S_ISREG(info.st_mode):
            flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
            with os.fdopen(os.open(entry, flags), "rb") as file:
                start = os.fstat(file.fileno())
                if not stat.S_ISREG(start.st_mode):
                    raise UnsafeRemoval("dirty file changed type during inspection")
                content = hashlib.sha256()
                while chunk := file.read(65536):
                    content.update(chunk)
                end = os.fstat(file.fileno())
                if ((start.st_ino, start.st_size, start.st_mtime_ns, start.st_ctime_ns)
                        != (end.st_ino, end.st_size, end.st_mtime_ns, end.st_ctime_ns)):
                    raise UnsafeRemoval("dirty file changed during inspection")
            record(b"contents", content.digest())
        else:
            raise UnsafeRemoval(f"unsupported dirty entry requires review: {entry}")
    if query("status", "--porcelain=v1", "-z", "--untracked-files=all") != before:
        raise UnsafeRemoval("dirty path set changed during inspection")
    return digest.hexdigest()


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--fingerprint":
            print(dirty_fingerprint(sys.argv[2]))
        else:
            check_removal(sys.argv[1])
    except (OSError, UnsafeRemoval, subprocess.CalledProcessError) as error:
        print(f"Filesystem review required: {error}", file=sys.stderr)
        raise SystemExit(1)
