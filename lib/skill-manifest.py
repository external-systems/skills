"""Package skills for claude.ai and detect drift between the repo and an account.

package SKILLS_DIR OUT_DIR REV
    One ZIP per skill plus manifest.json (name, content hash, rev). The
    packaged SKILL.md gets a metadata block (source-rev, content-hash) so an
    uploaded copy says which repo state it came from; the source tree is
    never stamped.

drift SKILLS_DIR [--synced DIR]... [--skip NAME]...
    Compare the repo skills with a copy of the account's skills. By default
    that copy is a cloud session's synced cache (~/.claude/skills/synced/*/).
    Exits 1 when a repo skill is missing or stale.
"""

import argparse
import glob
import hashlib
import json
import os
import pathlib
import re
import sys
import zipfile

FRONTMATTER = re.compile(r"^---\r?\n(.*?)\r?\n---\r?\n", re.DOTALL)
STAMPED_HASH = re.compile(r"^  content-hash: \"([^\"]+)\"$", re.MULTILINE)
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)


def skill_dirs(root):
    return sorted(p.parent for p in pathlib.Path(root).glob("*/SKILL.md"))


def files_of(skill):
    return sorted(p for p in skill.rglob("*") if p.is_file())


def content_hash(skill):
    digest = hashlib.sha256()
    for path in files_of(skill):
        digest.update(path.relative_to(skill).as_posix().encode() + b"\0")
        digest.update(path.read_bytes() + b"\0")
    return "sha256-" + digest.hexdigest()


def stamp(text, rev, digest):
    match = FRONTMATTER.match(text)
    if re.search(r"^metadata:", match.group(1), re.MULTILINE):
        raise SystemExit("package-skills: frontmatter already sets metadata; merge the stamp by hand")
    block = f'metadata:\n  source-rev: "{rev}"\n  content-hash: "{digest}"'
    return text[: match.end(1)] + "\n" + block + text[match.end(1) :]


def package(args):
    out = pathlib.Path(args.out)
    manifest = {"rev": args.rev, "skills": {}}
    for skill in skill_dirs(args.skills):
        digest = content_hash(skill)
        manifest["skills"][skill.name] = digest
        with zipfile.ZipFile(out / f"{skill.name}.zip", "w", zipfile.ZIP_DEFLATED) as archive:
            for path in files_of(skill):
                data = path.read_bytes()
                if path == skill / "SKILL.md":
                    data = stamp(data.decode("utf-8"), args.rev, digest).encode("utf-8")
                info = zipfile.ZipInfo(f"{skill.name}/{path.relative_to(skill).as_posix()}", ZIP_EPOCH)
                mode = 0o755 if os.access(path, os.X_OK) else 0o644
                info.external_attr = (0o100000 | mode) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, data)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return 0


def synced_hash(skill):
    # An upload made from package-skills carries its source hash; an older
    # upload of the raw directory is hashed as it is.
    match = FRONTMATTER.match((skill / "SKILL.md").read_text(encoding="utf-8"))
    stamped = match and STAMPED_HASH.search(match.group(1))
    return stamped.group(1) if stamped else content_hash(skill)


def drift(args):
    roots = args.synced or glob.glob(os.path.expanduser("~/.claude/skills/synced/*/"))
    if not roots:
        print("skills-drift: no synced account skills found; pass --synced DIR", file=sys.stderr)
        return 2

    account, uploaded = {}, set()
    for root in roots:
        account.update({skill.name: skill for skill in skill_dirs(root)})
        manifest = pathlib.Path(root) / "manifest.json"
        if manifest.is_file():
            entries = json.loads(manifest.read_text()).get("skills", [])
            uploaded |= {e["name"] for e in entries if e.get("source") == "plugin"}

    repo = {skill.name: skill for skill in skill_dirs(args.skills)}
    missing, stale = [], []
    for name, skill in repo.items():
        if name in args.skip:
            continue
        if name not in account:
            missing.append(name)
        elif synced_hash(account[name]) != content_hash(skill):
            stale.append(name)
    extra = sorted(uploaded - repo.keys())

    for label, names in (("missing", missing), ("stale", stale), ("not in repo", extra)):
        for name in names:
            print(f"{label}: {name}")
    if not (missing or stale):
        print(f"in sync: {len(repo) - len(args.skip & repo.keys())} repo skills")
    return 1 if missing or stale else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    pack = commands.add_parser("package")
    pack.add_argument("skills")
    pack.add_argument("out")
    pack.add_argument("rev")
    pack.set_defaults(run=package)

    check = commands.add_parser("drift")
    check.add_argument("skills")
    check.add_argument("--synced", action="append", default=[], metavar="DIR")
    check.add_argument("--skip", action="append", default=[], metavar="NAME")
    check.set_defaults(run=drift)

    args = parser.parse_args()
    if args.command == "drift":
        args.skip = set(args.skip)
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
