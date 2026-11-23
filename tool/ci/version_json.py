"""Erzeugt version.json (wie tool/build_release.ps1) – für GitHub Actions und lokale Image-Builds.

    python tool/ci/version_json.py [--apk Darts_3.1.0.apk] > ci/version.json
    python tool/ci/version_json.py --print-version        -> nur "3.1.0"

Quelle: pubspec.yaml (version x.y.z+build), packages/darts_protocol (relayProtocol),
lib/ui/about_screen.dart (Änderungsliste der Version).
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", default="", help="Dateiname der APK unter /apk/ (leer = keine APK)")
    ap.add_argument("--print-version", action="store_true")
    a = ap.parse_args()

    m = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", read("pubspec.yaml"), re.M)
    if not m:
        sys.exit('Keine Zeile "version: x.y.z+n" in pubspec.yaml')
    version, build = m.group(1), int(m.group(2))
    if a.print_version:
        print(version)
        return

    min_protocol = 3
    pm = re.search(r"const relayProtocol = (\d+);", read("packages/darts_protocol/lib/src/frames.dart"))
    if pm:
        min_protocol = int(pm.group(1))

    notes = []
    about = read("lib/ui/about_screen.dart")
    start = about.find(f"'{version}': [")
    if start >= 0:
        end = about.find("],", start)
        block = about[start : end if end >= 0 else len(about)]
        rx = re.compile(r"\(\s*Icons\.\w+\s*,\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'\s*,?\s*\)")
        for t, d in rx.findall(block):
            notes.append(f"{t.replace(chr(92) + chr(39), chr(39))}: {d.replace(chr(92) + chr(39), chr(39))}")

    info = {"version": version, "build": build, "minProtocol": min_protocol}
    if a.apk:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._\-]{0,150}\.apk", a.apk):
            sys.exit(f"Ungültiger APK-Name: {a.apk}")
        info["apk"] = f"/apk/{a.apk}"
    info["notes"] = notes
    # immer UTF-8 (auch unter Windows, wo die Konsole sonst cp1252 nimmt)
    sys.stdout.buffer.write((json.dumps(info, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


if __name__ == "__main__":
    main()
