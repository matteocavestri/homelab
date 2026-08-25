#!/usr/bin/env python3
"""
Checks for newer versions of the container images listed in
ansible/group_vars/all/versions.yml. Requires skopeo (dnf install skopeo).

Usage:
    python3 scripts/check_updates.py                 # readable table
    python3 scripts/check_updates.py --json           # machine-readable output
    python3 scripts/check_updates.py --apply          # write updates to versions.yml
    python3 scripts/check_updates.py --only jellyfin  # check a single key
    python3 scripts/check_updates.py --jobs 4         # fewer parallel skopeo calls
    python3 scripts/check_updates.py --timeout 30     # per-call skopeo timeout

Logic:
    mode: semver  -> `skopeo list-tags`, filtered by `tag_pattern` (or a numeric
                      default), sorted with packaging.version, compared to the
                      pinned tag.
    mode: digest  -> `skopeo inspect`, compares the digest to `last_digest`. If
                      `last_digest` is still empty (first run), reports "no
                      baseline" instead of "up to date": needs a first --apply.

skopeo calls run in parallel and each result prints as soon as it's ready, so a
slow or unreachable registry doesn't silently block the whole run.

--apply only writes versions.yml: it never touches the Ansible roles and never
runs the playbook. The actual deploy stays a separate, explicit step.
"""
import argparse
import concurrent.futures
import json
import re
import subprocess
import sys
from pathlib import Path

import yaml
from packaging.version import InvalidVersion, Version

try:
    from ruamel.yaml import YAML
    HAVE_RUAMEL = True
except ImportError:
    HAVE_RUAMEL = False

REPO_ROOT = Path(__file__).resolve().parent.parent
VERSIONS_FILE = REPO_ROOT / "ansible" / "group_vars" / "all" / "versions.yml"

DEFAULT_SEMVER_PATTERN = r"^v?\d+(\.\d+){1,3}$"  # optional "v", common GitHub releases convention
DEFAULT_TIMEOUT = 60
DEFAULT_JOBS = 8

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


def run_skopeo(args, timeout):
    try:
        result = subprocess.run(
            ["skopeo", *args],
            capture_output=True, text=True, timeout=timeout, check=True,
        )
    except FileNotFoundError:
        raise RuntimeError("'skopeo' not found on this system (dnf install skopeo)")
    except subprocess.CalledProcessError as e:
        raise RuntimeError((e.stderr or str(e)).strip().splitlines()[-1] if e.stderr else str(e))
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"timed out after {timeout}s (slow or unreachable registry)")
    return result.stdout


def check_semver(key, entry, timeout):
    repo = entry["image"]
    pinned = str(entry["tag"])
    pattern = entry.get("tag_pattern", DEFAULT_SEMVER_PATTERN)
    regex = re.compile(pattern)

    raw = run_skopeo(["list-tags", f"docker://{repo}"], timeout)
    tags = [t for t in json.loads(raw).get("Tags", []) if regex.match(t)]

    def parse(t):
        m = regex.match(t)
        return m.group("version") if m and "version" in (m.groupdict() or {}) else t

    versions = []
    for t in tags:
        try:
            versions.append((Version(parse(t)), t))
        except InvalidVersion:
            continue

    if versions:
        versions.sort()
        latest_version, latest_tag = versions[-1]
        try:
            newer = latest_version > Version(parse(pinned))
        except InvalidVersion:
            newer = latest_tag != pinned
        status = UPDATE_AVAILABLE if newer else UP_TO_DATE
        return {"key": key, "current": pinned, "latest": latest_tag, "status": status, "detail": None}

    if not tags:
        return {"key": key, "current": pinned, "latest": None, "status": ERROR,
                "detail": "no tag matched the configured pattern (tag_pattern?)"}

    # Composite tag format (e.g. "14-vectorchord0.4.3-pgvectors0.2.0",
    # "5.1.4-r3-ls453") that isn't valid PEP440: text comparison, not real semver -
    # only flags a difference if the lexicographically latest tag changed.
    latest_tag = sorted(tags)[-1]
    status = UPDATE_AVAILABLE if latest_tag != pinned else UP_TO_DATE
    return {"key": key, "current": pinned, "latest": latest_tag, "status": status,
            "detail": "text comparison (non-PEP440 tag), verify manually"}


def check_digest(key, entry, timeout):
    repo = entry["image"]
    tag = str(entry["tag"])
    last_digest = entry.get("last_digest") or ""

    raw = run_skopeo(["inspect", f"docker://{repo}:{tag}"], timeout)
    current_digest = json.loads(raw).get("Digest", "")

    if not last_digest:
        return {"key": key, "current": "(no baseline)", "latest": current_digest,
                "status": NO_BASELINE, "detail": None}

    status = UPDATE_AVAILABLE if current_digest != last_digest else UP_TO_DATE
    return {"key": key, "current": last_digest, "latest": current_digest, "status": status, "detail": None}


def check_one(key, entry, timeout):
    mode = entry.get("mode")
    try:
        if mode == "semver":
            res = check_semver(key, entry, timeout)
        elif mode == "digest":
            res = check_digest(key, entry, timeout)
        else:
            res = {"key": key, "current": entry.get("tag"), "latest": None,
                   "status": ERROR, "detail": f"unknown mode: {mode!r}"}
    except RuntimeError as e:
        res = {"key": key, "current": entry.get("tag"), "latest": None, "status": ERROR, "detail": str(e)}
    res["mode"] = mode

    if entry.get("pin_digest"):
        # Image= in the quadlet uses pin_digest, not tag: --apply on this entry
        # only updates the informational label, not what's actually running.
        note = "pinned on pin_digest, --apply does not update it"
        res["detail"] = f"{res['detail']}; {note}" if res["detail"] else note
    return res


def print_row(r, name_w):
    label = STATUS_LABELS[r["status"]]
    if r["detail"]:
        label += f"  ({r['detail']})"
    current = (r["current"] or "")[:40]
    latest = (r["latest"] or "")[:40]
    print(f"{r['key']:<{name_w}}  {r['mode']:<7}  {current:<40}  {latest:<40}  {label}", flush=True)


def apply_entries(versions_node, to_write):
    for r in to_write:
        entry = versions_node[r["key"]]
        if entry["mode"] == "semver":
            entry["tag"] = r["latest"]
        elif entry["mode"] == "digest":
            entry["last_digest"] = r["latest"]


def apply_updates(results):
    to_write = [r for r in results if r["status"] in (UPDATE_AVAILABLE, NO_BASELINE)]
    if not to_write:
        print("\n--apply: nothing to write")
        return

    if HAVE_RUAMEL:
        yaml_rt = YAML()
        yaml_rt.preserve_quotes = True
        yaml_rt.width = 4096
        yaml_rt.explicit_start = True
        with open(VERSIONS_FILE) as f:
            doc = yaml_rt.load(f)
        apply_entries(doc["versions"], to_write)
        with open(VERSIONS_FILE, "w") as f:
            yaml_rt.dump(doc, f)
        print(f"\n--apply: versions.yml updated, comments preserved ({VERSIONS_FILE})")
    else:
        with open(VERSIONS_FILE) as f:
            doc = yaml.safe_load(f)
        apply_entries(doc["versions"], to_write)
        with open(VERSIONS_FILE, "w") as f:
            yaml.dump(doc, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
        print(f"\n--apply: versions.yml updated ({VERSIONS_FILE})")
        print("WARNING: ruamel.yaml not installed, comments in the file were lost "
              "(see scripts/requirements.txt).")

    print("versions.yml was only written to disk: no container was touched.")
    print("To deploy the new images: ansible-playbook site.yml --diff --ask-vault-pass")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", action="store_true", help="machine-readable output (printed after the scan)")
    parser.add_argument("--apply", action="store_true", help="write updates to versions.yml")
    parser.add_argument("--only", metavar="KEY", help="check only this versions.yml key")
    parser.add_argument("--jobs", type=int, default=DEFAULT_JOBS,
                         help=f"parallel skopeo calls (default: {DEFAULT_JOBS})")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                         help=f"per-call skopeo timeout, in seconds (default: {DEFAULT_TIMEOUT})")
    args = parser.parse_args()

    with open(VERSIONS_FILE) as f:
        versions = yaml.safe_load(f)["versions"]

    if args.only:
        if args.only not in versions:
            print(f"ERROR: unknown key '{args.only}'", file=sys.stderr)
            sys.exit(1)
        keys = [args.only]
    else:
        keys = sorted(versions.keys())

    name_w = max((len(k) for k in keys), default=10)
    if not args.json:
        header = f"{'IMAGE':<{name_w}}  {'MODE':<7}  {'CURRENT':<40}  {'LATEST':<40}  STATUS"
        print(header)
        print("-" * len(header))

    order = {k: i for i, k in enumerate(keys)}
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = {pool.submit(check_one, k, versions[k], args.timeout): k for k in keys}
        for fut in concurrent.futures.as_completed(futures):
            r = fut.result()
            results.append(r)
            if not args.json:
                print_row(r, name_w)
    results.sort(key=lambda r: order[r["key"]])

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        n_updates = sum(1 for r in results if r["status"] == UPDATE_AVAILABLE)
        n_baseline = sum(1 for r in results if r["status"] == NO_BASELINE)
        n_errors = sum(1 for r in results if r["status"] == ERROR)
        print("-" * len(header))
        print(f"{len(results)} images checked: {n_updates} updates available, "
              f"{n_baseline} without baseline, {n_errors} errors")

    if args.apply:
        apply_updates(results)

    sys.exit(1 if any(r["status"] == ERROR for r in results) else 0)


if __name__ == "__main__":
    main()
