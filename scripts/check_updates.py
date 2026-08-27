#!/usr/bin/env python3
"""
Check for newer container images listed in ansible/group_vars/all/versions.yml.
Requires skopeo (dnf install skopeo).

    python3 scripts/check_updates.py                 # readable table
    python3 scripts/check_updates.py --json           # machine-readable
    python3 scripts/check_updates.py --only lidarr    # a single key
    python3 scripts/check_updates.py --apply          # write updates to versions.yml
    python3 scripts/check_updates.py --refresh        # ignore the cached tag lists
    python3 scripts/check_updates.py --jobs 8 --timeout 30

Tag lists (the slow call - open-webui alone has ~39k tags) are cached for 6h
under ~/.cache/homelab-check-updates/; digest and freshness checks are live.

mode: semver
    `skopeo list-tags`, then keep only tags in the same *family* as the pinned
    one: same optional leading "v" and the same non-numeric skeleton of whatever
    follows the dotted version. So "3.1.0.4875-ls39" only competes with other
    "X.Y.Z.W-lsN" tags - never "8.1.2135", "nightly-*", "amd64-*", "*-rc1".
    Candidates are ordered by their numeric fields; the winner only counts as an
    update if its image was also *built later* than the pinned one.
    `tag_pattern` (a regex) replaces the family filter when you need something
    stricter (e.g. pinning a major version).

mode: digest
    `skopeo inspect`, compares Digest to last_digest. Empty last_digest on the
    first run reports "no baseline": needs one --apply to record it.

skopeo calls run in parallel; each row prints as soon as it is ready.
--apply only rewrites versions.yml - it never touches Ansible or runs a deploy.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import yaml

try:
    from ruamel.yaml import YAML
    HAVE_RUAMEL = True
except ImportError:
    HAVE_RUAMEL = False

REPO_ROOT = Path(__file__).resolve().parent.parent
VERSIONS_FILE = REPO_ROOT / "ansible" / "group_vars" / "all" / "versions.yml"

DEFAULT_TIMEOUT = 30
DEFAULT_JOBS = 12

# `skopeo list-tags` on a mega-repo (open-webui ~39k tags, lidarr ~9k) can take a
# minute, so it gets a longer timeout and a short-lived on-disk cache. Digest and
# freshness `inspect` calls are always live.
LIST_TAGS_TIMEOUT = 120
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "homelab-check-updates"
CACHE_TTL = 6 * 3600
REFRESH = False  # set from --refresh

UP_TO_DATE = "up_to_date"
UPDATE_AVAILABLE = "update_available"
NO_BASELINE = "no_baseline"
ERROR = "error"

STATUS_LABELS = {
    UP_TO_DATE: "up to date",
    UPDATE_AVAILABLE: "UPDATE AVAILABLE",
    NO_BASELINE: "no baseline (run --apply)",
    ERROR: "ERROR",
}

# leading optional "v", a dotted numeric version, then whatever else ("rest")
VER_RX = re.compile(r"^(v?)(\d+(?:\.\d+)*)(.*)$", re.DOTALL)

# arch / OS / pre-release variants that must never win, on any code path
JUNK_RX = re.compile(
    r"(?i)(^|[-/_.])("
    r"amd64|arm64v8|arm64|arm32v7|armv7|armhf|arm|ppc64le|s390x|i386|x86[_-]?64|"
    r"linux|windows|nightly|develop|dev|beta|alpha|canary|edge|snapshot|preview|"
    r"insiders?|unstable|rc\d*|test"
    r")([-/_.]|$)"
)


def tag_family(tag):
    """(has_v, num_components, skeleton_of_rest) - only tags in the same family
    are comparable, so a 3-part "1.29.1" never competes with a 1-part "8400" and
    "3.1.0.4875-ls39" only competes with other "X.Y.Z.W-lsN" tags.

    "3.1.0.4875-ls39" -> ("", 4, "-ls#")     "v1.19.2" -> ("v", 3, "")
    "8.1.2135"         -> ("", 1, "")         "nightly-1.2.3" -> None
    """
    m = VER_RX.match(tag)
    if not m:
        return None
    lead_v, dotted, rest = m.groups()
    return lead_v, dotted.count(".") + 1, re.sub(r"\d+", "#", rest)


def tag_sortkey(tag):
    """All numeric fields as an int tuple, trailing zeros trimmed so
    "v1.20" and "v1.20.0" compare equal."""
    nums = [int(n) for n in re.findall(r"\d+", tag)]
    while len(nums) > 1 and nums[-1] == 0:
        nums.pop()
    return tuple(nums)


def result(key, current, latest, status, detail=None):
    return {"key": key, "current": current, "latest": latest, "status": status, "detail": detail}


def run_skopeo(args, timeout):
    try:
        proc = subprocess.run(
            ["skopeo", "--command-timeout", f"{timeout}s", *args],
            capture_output=True, text=True, timeout=timeout + 10, check=True,
        )
    except FileNotFoundError:
        raise RuntimeError("'skopeo' not found on this system (dnf install skopeo)")
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"timed out after {timeout}s (slow or unreachable registry)")
    except subprocess.CalledProcessError as e:
        msg = (e.stderr or "").strip()
        raise RuntimeError(msg.splitlines()[-1] if msg else f"skopeo exited {e.returncode}")
    return proc.stdout


def list_tags(repo, timeout):
    cache = CACHE_DIR / (hashlib.sha256(repo.encode()).hexdigest()[:16] + ".json")
    if not REFRESH and cache.is_file() and time.time() - cache.stat().st_mtime < CACHE_TTL:
        return json.loads(cache.read_text())
    raw = run_skopeo(["list-tags", f"docker://{repo}"], max(timeout, LIST_TAGS_TIMEOUT))
    tags = json.loads(raw).get("Tags", [])
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(tags))
    return tags


def image_created(repo, ref, timeout):
    """RFC3339 build timestamp of repo:ref ('' if the registry doesn't report one)."""
    raw = run_skopeo(["inspect", "--no-tags", f"docker://{repo}:{ref}"], timeout)
    return json.loads(raw).get("Created", "")


def check_semver(key, entry, timeout):
    repo = entry["image"]
    pinned = str(entry["tag"])
    tags = list_tags(repo, timeout)

    pattern = entry.get("tag_pattern")
    if pattern:
        regex = re.compile(pattern)
        candidates = [t for t in tags if regex.search(t)]
        scope = "tag_pattern"
    else:
        family = tag_family(pinned)
        if family is None:
            return result(key, pinned, None, ERROR,
                          "pinned tag is not version-like - use mode: digest")
        candidates = [t for t in tags if tag_family(t) == family]
        scope = f"family {family}"

    candidates = sorted({t for t in candidates if not JUNK_RX.search(t)}, key=tag_sortkey)
    if not candidates:
        return result(key, pinned, None, ERROR, f"no tag in scope ({scope}); check tag_pattern")

    latest = candidates[-1]
    if tag_sortkey(latest) <= tag_sortkey(pinned):
        return result(key, pinned, latest, UP_TO_DATE)

    # A higher tag exists - require its image to be genuinely newer, so a
    # re-pointed or mis-sorted tag can't masquerade as an update.
    detail = None
    if not entry.get("pin_digest"):
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                new_built, old_built = pool.map(
                    lambda ref: image_created(repo, ref, timeout), (latest, pinned))
            if new_built and old_built and new_built <= old_built:
                return result(key, pinned, latest, UP_TO_DATE,
                              f"tag {latest} exists but its image is not newer "
                              f"({new_built[:10]} <= {old_built[:10]})")
            if new_built:
                detail = f"built {new_built[:10]}"
        except RuntimeError as e:
            detail = f"freshness check skipped ({e})"

    return result(key, pinned, latest, UPDATE_AVAILABLE, detail)


def check_digest(key, entry, timeout):
    repo = entry["image"]
    tag = str(entry["tag"])
    last_digest = entry.get("last_digest") or ""

    raw = run_skopeo(["inspect", "--no-tags", f"docker://{repo}:{tag}"], timeout)
    current_digest = json.loads(raw).get("Digest", "")

    if not last_digest:
        return result(key, "(no baseline)", current_digest, NO_BASELINE)
    status = UPDATE_AVAILABLE if current_digest != last_digest else UP_TO_DATE
    return result(key, last_digest, current_digest, status)


def check_one(key, entry, timeout):
    mode = entry.get("mode")
    try:
        if mode == "semver":
            res = check_semver(key, entry, timeout)
        elif mode == "digest":
            res = check_digest(key, entry, timeout)
        else:
            res = result(key, entry.get("tag"), None, ERROR, f"unknown mode: {mode!r}")
    except RuntimeError as e:
        res = result(key, entry.get("tag"), None, ERROR, str(e))
    res["mode"] = mode

    if entry.get("pin_digest"):
        note = "quadlet runs pin_digest; --apply only updates the label"
        res["detail"] = f"{res['detail']}; {note}" if res["detail"] else note
    return res


def print_row(r, name_w):
    label = STATUS_LABELS[r["status"]]
    if r["detail"]:
        label += f"  ({r['detail']})"
    current = (r["current"] or "")[:40]
    latest = (r["latest"] or "")[:40]
    print(f"{r['key']:<{name_w}}  {r['mode']:<7}  {current:<40}  {latest:<40}  {label}", flush=True)


def apply_updates(results):
    to_write = [r for r in results if r["status"] in (UPDATE_AVAILABLE, NO_BASELINE)]
    if not to_write:
        print("\n--apply: nothing to write")
        return

    def patch(node):
        for r in to_write:
            entry = node[r["key"]]
            if entry["mode"] == "semver":
                entry["tag"] = r["latest"]
            elif entry["mode"] == "digest":
                entry["last_digest"] = r["latest"]

    if HAVE_RUAMEL:
        ruamel = YAML()
        ruamel.preserve_quotes = True
        ruamel.width = 4096
        ruamel.explicit_start = True
        doc = ruamel.load(VERSIONS_FILE.read_text())
        patch(doc["versions"])
        with open(VERSIONS_FILE, "w") as f:
            ruamel.dump(doc, f)
        print(f"\n--apply: versions.yml updated, comments preserved ({VERSIONS_FILE})")
    else:
        doc = yaml.safe_load(VERSIONS_FILE.read_text())
        patch(doc["versions"])
        with open(VERSIONS_FILE, "w") as f:
            yaml.dump(doc, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
        print(f"\n--apply: versions.yml updated ({VERSIONS_FILE})")
        print("WARNING: ruamel.yaml not installed, file comments were lost "
              "(see scripts/requirements.txt).")

    print("versions.yml was only written to disk: no container was touched.")
    print("To deploy the new images: ansible-playbook deploy.yml --diff --ask-vault-pass")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--apply", action="store_true", help="write updates to versions.yml")
    parser.add_argument("--only", metavar="KEY", help="check only this versions.yml key")
    parser.add_argument("--refresh", action="store_true",
                        help=f"ignore the cached tag lists (kept {CACHE_TTL // 3600}h in {CACHE_DIR})")
    parser.add_argument("--jobs", type=int, default=DEFAULT_JOBS,
                        help=f"parallel skopeo calls (default: {DEFAULT_JOBS})")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                        help=f"per-call skopeo timeout in seconds (default: {DEFAULT_TIMEOUT})")
    args = parser.parse_args()

    global REFRESH
    REFRESH = args.refresh

    versions = yaml.safe_load(VERSIONS_FILE.read_text())["versions"]

    if args.only:
        if args.only not in versions:
            print(f"ERROR: unknown key '{args.only}'", file=sys.stderr)
            sys.exit(2)
        keys = [args.only]
    else:
        keys = sorted(versions)

    name_w = max((len(k) for k in keys), default=10)
    header = f"{'IMAGE':<{name_w}}  {'MODE':<7}  {'CURRENT':<40}  {'LATEST':<40}  STATUS"
    if not args.json:
        print(header)
        print("-" * len(header))

    order = {k: i for i, k in enumerate(keys)}
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = [pool.submit(check_one, k, versions[k], args.timeout) for k in keys]
        for fut in concurrent.futures.as_completed(futures):
            r = fut.result()
            results.append(r)
            if not args.json:
                print_row(r, name_w)
    results.sort(key=lambda r: order[r["key"]])

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        n_up = sum(r["status"] == UPDATE_AVAILABLE for r in results)
        n_base = sum(r["status"] == NO_BASELINE for r in results)
        n_err = sum(r["status"] == ERROR for r in results)
        print("-" * len(header))
        print(f"{len(results)} images checked: {n_up} updates, {n_base} without baseline, {n_err} errors")

    if args.apply:
        apply_updates(results)

    sys.exit(1 if any(r["status"] == ERROR for r in results) else 0)


if __name__ == "__main__":
    main()
