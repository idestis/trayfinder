#!/usr/bin/env python3
"""Prepend a release to the Sparkle appcast (landing/appcast.xml).

Sparkle's generate_appcast wants every old DMG on disk; we keep the appcast in git as
the source of truth and splice the new <item> in instead. Re-running for a version
that is already listed replaces that item. Standard library only.

Usage (see `task app:appcast`):
  prepend_appcast.py --version 0.2.0 --build 7 --url https://.../Trayfinder.dmg \
    --sig-line "$(sign_update Trayfinder.dmg)" --notes "<h3>...</h3>" ../landing/appcast.xml
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr


def parse_sig_line(line: str) -> tuple[str, str]:
    sig = re.search(r'sparkle:edSignature="([^"]+)"', line)
    length = re.search(r'length="(\d+)"', line)
    if not sig or not length:
        sys.exit(f"could not parse sign_update output: {line!r}")
    return sig.group(1), length.group(1)


def build_item(args: argparse.Namespace, signature: str, length: str) -> str:
    pubdate = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    notes = args.notes.strip().replace("]]>", "]]]]><![CDATA[>")
    description = f"      <description><![CDATA[\n{notes}\n]]></description>\n" if notes else ""
    return (
        "    <item>\n"
        f"      <title>{escape(args.version)}</title>\n"
        f"      <pubDate>{pubdate}</pubDate>\n"
        f"      <sparkle:version>{escape(args.build)}</sparkle:version>\n"
        f"      <sparkle:shortVersionString>{escape(args.version)}</sparkle:shortVersionString>\n"
        f"      <sparkle:minimumSystemVersion>{escape(args.min_system_version)}</sparkle:minimumSystemVersion>\n"
        f"{description}"
        f"      <enclosure url={quoteattr(args.url)} sparkle:edSignature=\"{signature}\" length=\"{length}\""
        ' type="application/x-apple-diskimage"/>\n'
        "    </item>\n"
    )


def splice(text: str, version: str, item: str) -> str:
    # Same version already listed: replace it in place.
    same = re.compile(r"[ \t]*<item>\s*<title>" + re.escape(version) + r"</title>.*?</item>[ \t]*\n?", re.DOTALL)
    if same.search(text):
        return same.sub(lambda _: item, text, count=1)
    # Newest first: before the first existing item, else right before </channel>.
    first = re.search(r"[ \t]*<item>", text)
    if first:
        return text[: first.start()] + item + text[first.start() :]
    close = re.search(r"[ \t]*</channel>", text)
    if not close:
        sys.exit("could not find <channel> in the appcast")
    return text[: close.start()] + item + text[close.start() :]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", required=True, help="marketing version, e.g. 0.2.0")
    ap.add_argument("--build", required=True, help="CURRENT_PROJECT_VERSION, e.g. 7")
    ap.add_argument("--url", required=True, help="enclosure URL of the DMG")
    ap.add_argument("--sig-line", required=True, help="output of Sparkle's sign_update")
    ap.add_argument("--notes", default="", help="HTML release notes")
    ap.add_argument("--min-system-version", default="14.0")
    ap.add_argument("appcast", type=Path)
    args = ap.parse_args()

    if not args.appcast.is_file():
        sys.exit(f"appcast not found: {args.appcast}")
    signature, length = parse_sig_line(args.sig_line)
    item = build_item(args, signature, length)
    text = args.appcast.read_text(encoding="utf-8")
    args.appcast.write_text(splice(text, args.version, item), encoding="utf-8")
    print(f"{args.appcast}: {args.version} ({args.build})")


if __name__ == "__main__":
    main()
