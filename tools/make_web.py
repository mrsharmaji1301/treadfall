"""Builds the browser version of TREADFALL into ../ONLINE (next to the
project folder), small enough for web game sites.

It copies the project to a build folder, makes every picture smaller for
the web (lossy WebP; menu pictures at most 1024 px, the rest 512 px), imports,
and exports with the "Web" preset. The project itself is not changed.

Run from the project folder:
    python tools/make_web.py <path to Godot 4.7.2> [build folder]
Needs the Godot 4.7.2 web export templates installed.
"""
import os, re, shutil, subprocess, sys

proj = os.path.abspath(os.getcwd())
godot = sys.argv[1]
build = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else os.path.join(proj, '..', '_web_build'))
out = os.path.abspath(os.path.join(proj, '..', 'ONLINE'))

SKIP_DIRS = {'.godot', '_preview', '__pycache__', 'node_modules', 'server', '.git'}
## Largest side in pixels: menu and HUD pictures stay sharp, the ground,
## paint and plant textures in the 3D world go smaller.
LIMIT_UI = 1024
LIMIT = 512
QUALITY = 0.75

if os.path.isdir(build):
    shutil.rmtree(build)
for here, dirs, files in os.walk(proj):
    dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
    rel = os.path.relpath(here, proj)
    os.makedirs(os.path.join(build, rel), exist_ok=True)
    for f in files:
        shutil.copy2(os.path.join(here, f), os.path.join(build, rel, f))

changed = 0
for here, _dirs, files in os.walk(build):
    for f in files:
        if not f.endswith('.import'):
            continue
        p = os.path.join(here, f)
        s = open(p, encoding='utf-8').read()
        if 'importer="texture"' not in s:
            continue
        s = re.sub(r'compress/mode=\d+', 'compress/mode=1', s)
        s = re.sub(r'compress/lossy_quality=[\d.]+', 'compress/lossy_quality=%s' % QUALITY, s)
        ui = os.sep + 'ui' + os.sep in p
        s = re.sub(r'process/size_limit=\d+', 'process/size_limit=%d' % (LIMIT_UI if ui else LIMIT), s)
        s = re.sub(r'detect_3d/compress_to=\d+', 'detect_3d/compress_to=0', s)
        open(p, 'w', encoding='utf-8').write(s)
        changed += 1
print('pictures made smaller:', changed)

os.makedirs(out, exist_ok=True)
subprocess.run([godot, '--headless', '--path', build, '--import'], check=False)
r = subprocess.run([godot, '--headless', '--path', build, '--export-release', 'Web',
                    os.path.join(out, 'index.html')])
if r.returncode != 0:
    sys.exit('export failed')
total = 0
for f in sorted(os.listdir(out)):
    size = os.path.getsize(os.path.join(out, f))
    total += size
    print('%-34s %8.1f MB' % (f, size / 1e6))
print('%-34s %8.1f MB' % ('total', total / 1e6))
