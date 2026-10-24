#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}

cd "$project_dir"

required_files=(
    AGENTS.md
    CLAUDE.md
    README.md
    docs/README.md
    docs/development.md
    docs/architecture.md
    .agents/skills/lerro-development/SKILL.md
    .claude/skills/lerro-development/SKILL.md
)

for relative in "${required_files[@]}"; do
    [[ -f "$project_dir/$relative" && ! -L "$project_dir/$relative" ]] || {
        print -u2 "Missing regular agent-workspace file: $relative"
        exit 1
    }
done

# .claude/worktrees holds other sessions' git worktrees (with .build symlinks).
if find .agents .claude -path .claude/worktrees -prune -o -type l -print -quit | grep -q .; then
    print -u2 "Project agent entrypoints must use regular files."
    exit 1
fi

python3 - "$project_dir" <<'PY'
from __future__ import annotations

import pathlib
import re
import subprocess
import sys
import urllib.parse

root = pathlib.Path(sys.argv[1]).resolve()
errors: list[str] = []


def read(relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


def frontmatter(relative: str) -> tuple[dict[str, str], str]:
    text = read(relative)
    if not text.startswith("---\n"):
        errors.append(f"missing YAML frontmatter: {relative}")
        return {}, text
    marker = text.find("\n---\n", 4)
    if marker < 0:
        errors.append(f"unterminated YAML frontmatter: {relative}")
        return {}, text
    fields: dict[str, str] = {}
    for raw in text[4:marker].splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if ":" not in raw:
            errors.append(f"invalid frontmatter line in {relative}: {raw}")
            continue
        key, value = raw.split(":", 1)
        fields[key.strip()] = value.strip().strip('"').strip("'")
    return fields, text[marker + 5 :]


canonical = ".agents/skills/lerro-development/SKILL.md"
bridge = ".claude/skills/lerro-development/SKILL.md"
for relative in (canonical, bridge):
    fields, body = frontmatter(relative)
    if fields.get("name") != "lerro-development":
        errors.append(f"unexpected skill name: {relative}")
    description = fields.get("description", "")
    if len(description) < 40 or "Lerro" not in description:
        errors.append(f"skill description is too weak: {relative}")
    if "TODO" in body:
        errors.append(f"unfinished skill content: {relative}")

bridge_text = read(bridge)
canonical_reference = "../../../.agents/skills/lerro-development/SKILL.md"
if canonical_reference not in bridge_text:
    errors.append("Claude skill does not delegate to the canonical skill")

claude_lines = [line.strip() for line in read("CLAUDE.md").splitlines() if line.strip()]
if not claude_lines or claude_lines[0] != "@AGENTS.md":
    errors.append("CLAUDE.md must import @AGENTS.md as its first non-empty line")

agents_text = read("AGENTS.md")
for marker in (
    "docs/development.md",
    ".agents/skills/lerro-development/SKILL.md",
    "script/validate_agent_workspace.sh",
):
    if marker not in agents_text:
        errors.append(f"AGENTS.md is missing bootstrap marker: {marker}")

adr_status = re.compile(r"^- 状态：(proposed|accepted|superseded|rejected)\b", re.MULTILINE)
for adr in sorted((root / "docs" / "decisions").glob("[0-9][0-9][0-9][0-9]-*.md")):
    text = adr.read_text(encoding="utf-8")
    name = adr.relative_to(root)
    if not adr_status.search(text):
        errors.append(f"ADR is missing a valid status line: {name}")
    for section in ("背景", "决策", "后果"):
        if not re.search(rf"^## {section}\s*$", text, re.MULTILINE):
            errors.append(f"ADR is missing section ## {section}: {name}")

# Every Markdown file Git tracks or would track.
listed = subprocess.run(
    ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.md"],
    cwd=root,
    check=True,
    capture_output=True,
).stdout.decode("utf-8")
markdown_files = [
    root / relative
    for relative in sorted(set(listed.split("\0")))
    if relative and (root / relative).is_file()
]
checked_links = 0
for source in markdown_files:
    text = source.read_text(encoding="utf-8")
    for raw in re.findall(r"\[[^]]+\]\(([^)]+)\)", text):
        target = urllib.parse.unquote(raw.split("#", 1)[0])
        if not target or "://" in target or target.startswith("mailto:"):
            continue
        checked_links += 1
        resolved = (source.parent / target).resolve()
        if not resolved.exists():
            errors.append(
                f"missing Markdown link: {source.relative_to(root)} -> {raw}"
            )

if errors:
    raise SystemExit("Agent workspace validation failed:\n" + "\n".join(sorted(set(errors))))

print(
    f"Agent workspace validation passed: {len(markdown_files)} Markdown files, "
    f"{checked_links} local links, canonical Claude skill entry."
)
PY
