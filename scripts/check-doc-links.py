#!/usr/bin/env python3
"""Check repository Markdown links, HTML image paths and Markdown anchors without network access."""

from html.parser import HTMLParser
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent


def prose(source, keep_inline=False):
    """Ignore fenced/inline code while retaining line numbers for diagnostics."""
    lines = []
    fence = None
    for line in source.splitlines(keepends=True):
        marker = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker and fence is None:
            fence = marker.group(1)
            lines.append("\n")
        elif fence is not None:
            if re.match(r"^\s*" + re.escape(fence[0]) + "{" + str(len(fence)) + r",}\s*$", line):
                fence = None
            lines.append("\n")
        else:
            lines.append(re.sub(r"(`+)(.*?)\1", r"\2" if keep_inline else "", line))
    return "".join(lines)


def anchors(path):
    result = set()
    counts = {}
    source = prose(path.read_text(encoding="utf-8"), keep_inline=True)
    for heading in re.findall(r"^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$", source, re.M):
        heading = re.sub(r"<[^>]+>", "", heading)
        slug = re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        result.add(slug if count == 0 else f"{slug}-{count}")
    result.update(re.findall(r'\bid=["\']([^"\']+)["\']', source))
    return result


class HTMLLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if not value:
                continue
            if key in {"src", "href"}:
                self.links.append((self.getpos()[0], value))
            elif key == "srcset":
                for candidate in value.split(","):
                    self.links.append((self.getpos()[0], candidate.strip().split()[0]))


def links(source):
    source = prose(source)
    found = []
    # Inline links/images, including both destinations in linked badge images.
    for match in re.finditer(r"\]\(\s*(?:<([^>]+)>|([^\s)]+))(?:\s+[^)]*)?\)", source):
        found.append((source.count("\n", 0, match.start()) + 1, match.group(1) or match.group(2)))
    # Reference-link destinations are checked even if their label is currently unused.
    for match in re.finditer(r"^ {0,3}\[[^\]\n]+\]:\s*(?:<([^>]+)>|(\S+))", source, re.M):
        found.append((source.count("\n", 0, match.start()) + 1, match.group(1) or match.group(2)))
    parser = HTMLLinks()
    parser.feed(source)
    return found + parser.links


def main():
    files = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.md"], cwd=ROOT
    ).decode().split("\0")
    errors = []
    local_count = external_count = 0
    for filename in sorted(set(filter(None, files))):
        path = ROOT / filename
        for line, destination in links(path.read_text(encoding="utf-8")):
            url = urlsplit(destination)
            if url.scheme in {"https", "http", "mailto"} or url.netloc:
                external_count += 1
                continue
            target = (path.parent / unquote(url.path)).resolve() if url.path else path
            problem = None
            if url.scheme or url.path.startswith("/") or not target.is_relative_to(ROOT):
                problem = "expected a repository-relative path"
            elif not target.exists():
                problem = "missing target"
            elif url.fragment and target.suffix == ".md" and unquote(url.fragment) not in anchors(target):
                problem = "missing heading/anchor"
            local_count += 1
            if problem:
                errors.append(f"{filename}:{line}: {problem}: {destination}")
    for error in errors:
        print(error, file=sys.stderr)
    print(f"Checked {local_count} relative links/images; skipped {external_count} external URLs (offline).")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
