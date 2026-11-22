#!/usr/bin/env python3
"""Writes Sparkle's update feed for one version of Simmer.

  appcast.py appcast.xml VERSION BUILD DMG_URL 'sparkle:edSignature="…" length="…"' notes.md

The feed is attached to each GitHub release, and Simmer reads the one on
the latest release, so it only ever needs to describe that version.
"""
import html
import re
import sys
from email.utils import formatdate

path, version, build, url, signature, notes_path = sys.argv[1:7]


def inline(text):
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return text


def markdown(source):
    """Just enough Markdown for release notes: headings, bullets and
    paragraphs."""
    out, items, para = [], [], []

    def flush():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items.clear()

    for line in source.splitlines():
        stripped = line.strip()
        if not stripped:
            flush()
        elif stripped.startswith("#"):
            flush()
            out.append("<h3>" + inline(stripped.lstrip("#").strip()) + "</h3>")
        elif stripped[:2] in ("- ", "* "):
            if para:
                flush()
            items.append(stripped[2:])
        elif items and line.startswith(" "):
            items[-1] += " " + stripped
        else:
            if items:
                flush()
            para.append(stripped)
    flush()
    return "\n".join(out)


notes = markdown(open(notes_path).read())
feed = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Simmer</title>
    <link>https://github.com/mattbirchler/Simmer</link>
    <description>Updates to Simmer.</description>
    <language>en</language>
    <item>
      <title>Simmer {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <link>https://github.com/mattbirchler/Simmer/releases/tag/v{version}</link>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
{notes}
      ]]></description>
      <enclosure url="{url}" type="application/octet-stream" {signature.strip()}/>
    </item>
  </channel>
</rss>
"""
open(path, "w").write(feed)
