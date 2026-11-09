#!/usr/bin/env python3
#
# Light OS (festomanolo): rebrand the user-visible text of the Porteus GUI tools.
#
# Reads the Porteus base modules (.xzm squashfs) of an ISO and writes rebranded
# copies of the GUI scripts and launchers into rootcopy/, which overlays them at
# boot. Only on-screen strings change: window titles, labels, dialog text.
# Untouched on purpose: comments, file/script names and paths (Porteus-FAQ/,
# porteus-scripts, ...), code identifiers (PorteusDialog), links to the Porteus
# website/forum, and strings other code matches on ("Porteus data found").
#
# Needs PySquashfsImage:  pip install --target <dir> PySquashfsImage
# Usage:  python3 tools/rebrand-ui.py /path/to/porteus/base  rootcopy/
################################################################################
import os, re, sys

try:
    from PySquashfsImage import SquashFsImage
except ImportError:
    sys.exit("PySquashfsImage is required: pip install PySquashfsImage")

WORD = re.compile(r'(?<![/_.\-A-Za-z0-9])Porteus(?![\-_/A-Za-z0-9])(?!\.[a-z])')
SKIP = re.compile(r'forum|porteus\.org|www\.|https?:|fanthom\.|data found|3ox|'
                  r'Porteus Save File Manager', re.I)
EXTRA = [("The porteus installer", "The Light OS installer"),
         ("PORTEUS WILL BOOT", "LIGHT OS WILL BOOT")]

def is_target(path):
    return (path.startswith("opt/porteus-scripts/")
            or path.startswith("usr/share/porteus/"))

def desktop_target(path):
    return path.endswith(".desktop") and (
        path.startswith("usr/share/applications/")
        or path.startswith("etc/xdg/autostart/"))

def rebrand_script(text):
    out, n = [], 0
    for line in text.split("\n"):
        new = line
        if "orteus" in line.lower() and not line.lstrip().startswith("#") \
                and not SKIP.search(line):
            for a, b in EXTRA:
                new = new.replace(a, b)
            new = WORD.sub("Light OS", new)
        n += new != line
        out.append(new)
    return "\n".join(out), n

def rebrand_desktop(text):
    out, n = [], 0
    for line in text.split("\n"):
        new = line
        if re.match(r'^(Name|Comment|GenericName|X-GNOME-FullName)(\[[^\]]+\])?=', line):
            new = line.replace("Porteus", "Light OS")
        n += new != line
        out.append(new)
    return "\n".join(out), n

def main(base_dir, rootcopy):
    total = 0
    for mod in sorted(os.listdir(base_dir)):
        if not mod.endswith(".xzm"):
            continue
        for f in SquashFsImage.from_file(os.path.join(base_dir, mod)):
            path = f.path.lstrip("/")
            if not f.is_file or not (is_target(path) or desktop_target(path)):
                continue
            data = f.read_bytes()
            if b"\0" in data[:4096]:
                continue
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                continue
            new, n = (rebrand_desktop if desktop_target(path) else rebrand_script)(text)
            if not n:
                continue
            dst = os.path.join(rootcopy, path)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w", encoding="utf-8") as fh:
                fh.write(new)
            os.chmod(dst, f.mode & 0o777)
            total += n
            print(f"{n:3d}  {path}")
    print(f"rebranded {total} lines")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__ or "usage: rebrand-ui.py <porteus/base dir> <rootcopy dir>")
    main(sys.argv[1], sys.argv[2])
