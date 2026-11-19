#!/usr/bin/env python3
"""Scan source, optional Git history/artifacts, without printing matched content."""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    "Google API credential": re.compile(rb"AIza[0-9A-Za-z_-]{35}"),
    "GitHub credential": re.compile(rb"(?:gh[pousr]_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{40,})"),
    "LLM API credential": re.compile(rb"(?:sk-(?:proj-|svcacct-|admin-|ant-|or-v1-)?[0-9A-Za-z_-]{32,}|gsk_[0-9A-Za-z]{40,})"),
    "private key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "populated development credential": re.compile(rb"(?m)^Gemi_APi_key\s*=\s*[\"']?[A-Za-z0-9_-]{20,}"),
}


def detections(data):
    return [label for label, pattern in PATTERNS.items() if pattern.search(data)]


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], stderr=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true")
    parser.add_argument("--artifact", type=Path, action="append", default=[])
    options = parser.parse_args()
    assert detections(b"AIza" + b"x" * 35) == ["Google API credential"]
    assert detections(b"sk-proj-" + b"x" * 48) == ["LLM API credential"]
    assert detections(b"Gemi_APi_key=\n") == []
    assert detections(b"-----BEGIN " + b"PRIVATE KEY-----") == ["private key"]
    failed = False
    count = 0

    def check(label, data):
        nonlocal failed, count
        count += 1
        for kind in detections(data):
            print(f"FAIL: {label}: {kind} (value suppressed)")
            failed = True

    for raw in git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0"):
        if not raw:
            continue
        path = ROOT / raw.decode()
        if path.is_symlink():
            print(f"FAIL: source symlink requires review: {path.relative_to(ROOT)}")
            failed = True
        elif path.is_file():
            check(str(path.relative_to(ROOT)), path.read_bytes())
    if options.history:
        try:
            objects = git("rev-list", "--objects", "--all").splitlines()
        except subprocess.CalledProcessError:
            objects = []
        for entry in objects:
            oid = entry.split(b" ", 1)[0].decode()
            if git("cat-file", "-t", oid).strip() == b"blob":
                check("Git history blob " + oid[:12], git("cat-file", "blob", oid))
    for artifact in options.artifact:
        if not artifact.exists():
            print(f"FAIL: artifact not found: {artifact.name}")
            failed = True
            continue
        files = artifact.rglob("*") if artifact.is_dir() else [artifact]
        for path in files:
            if path.is_file() and not path.is_symlink():
                check("artifact " + str(path.relative_to(artifact.parent)), path.read_bytes())
    print(f"{'FAILED' if failed else 'PASS'}: scanned {count} files/blobs; no matched values printed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
