#!/usr/bin/env python3
"""Run the Godot regressions and optionally package the two desktop builds."""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2-stable"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}"
EDITOR = f"Godot_v{VERSION}_linux.x86_64"
EDITOR_HASH = "cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4"
TEMPLATES_HASH = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
TARGETS = (
    ("Linux", "linux-x86_64", "Eve-Offline.x86_64", "linux_release.x86_64"),
    ("Windows Desktop", "windows-x86_64", "Eve-Offline.exe", "windows_release_x86_64.exe"),
)


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download(cache, filename, expected):
    target = cache / filename
    if target.exists() and sha256(target) == expected:
        return target
    partial = cache / f"{filename}.part"
    print(f"Downloading {filename}", flush=True)
    request = urllib.request.Request(f"{BASE}/{filename}", headers={"User-Agent": "Eve-Offline-build"})
    with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as stream:
        shutil.copyfileobj(response, stream)
    if sha256(partial) != expected:
        raise RuntimeError(f"SHA-256 mismatch for {filename}")
    partial.replace(target)
    return target


def run_checks(editor, env):
    invoke = [str(editor), "--headless", "--path", str(ROOT)]
    subprocess.run([*invoke, "--editor", "--import"], env=env, check=True, timeout=180)
    for suite in ("deck", "combat", "voyage"):
        subprocess.run(
            [*invoke, "--fixed-fps", "60", "--script", f"res://tests/{suite}_regression.gd"],
            env=env, check=True, timeout=60,
        )


def build_archives(editor, env, templates_zip):
    data = Path(env["XDG_DATA_HOME"])
    template_dir = data / "godot" / "export_templates" / VERSION.replace("-", ".")
    template_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(templates_zip) as archive:
        for _, _, _, template in TARGETS:
            with archive.open(f"templates/{template}") as source, (template_dir / template).open("wb") as dest:
                shutil.copyfileobj(source, dest)

    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    checksums = []
    with tempfile.TemporaryDirectory(prefix="eve-release-") as workspace:
        for preset, platform, binary, _ in TARGETS:
            output = Path(workspace) / platform
            output.mkdir()
            subprocess.run(
                [str(editor), "--headless", "--path", str(ROOT), "--export-release", preset, str(output / binary)],
                env=env, check=True, timeout=180,
            )
            executable = output / binary
            pack = executable.with_suffix(".pck")
            if not executable.is_file() or not pack.is_file():
                raise RuntimeError(f"Missing export files for {preset}")
            if preset == "Linux":
                executable.chmod(0o755)
                subprocess.run([str(executable), "--headless", "--quit"], env=env, check=True, timeout=30)

            bundle = dist / f"Eve-Offline-{platform}.zip"
            with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.write(executable, binary)
                archive.write(pack, pack.name)
                archive.write(ROOT / "README.md", "README.md")
                for filename in ("LICENSE.txt", "COPYRIGHT.txt"):
                    archive.write(ROOT / "third_party" / "godot" / filename, f"Godot-{filename}")
            checksums.append(f"{sha256(bundle)}  {bundle.name}")
    (dist / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--build", action="store_true")
    args = parser.parse_args()
    cache = args.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    editor_zip = download(cache, f"{EDITOR}.zip", EDITOR_HASH)
    with zipfile.ZipFile(editor_zip) as archive:
        editor = Path(archive.extract(EDITOR, cache))
    editor.chmod(0o755)
    env = dict(os.environ, XDG_DATA_HOME=str(cache / "data"), XDG_CONFIG_HOME=str(cache / "config"),
               XDG_CACHE_HOME=str(cache / "cache"))
    run_checks(editor, env)
    if args.build:
        templates = download(cache, f"Godot_v{VERSION}_export_templates.tpz", TEMPLATES_HASH)
        build_archives(editor, env, templates)


if __name__ == "__main__":
    main()
