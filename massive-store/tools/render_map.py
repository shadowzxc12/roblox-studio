"""Renders a top-down preview of a generated store (needs Pillow).

  python3 tools/render_map.py [seed]   -> docs/map_main.png, docs/map_basement.png
"""
import math, os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
seed = int(sys.argv[1]) if len(sys.argv) > 1 else 2024
luau = os.environ.get('LUAU_BIN', os.path.join(ROOT, '.luau')) + '/luau'
with tempfile.TemporaryDirectory() as tmp:
    test = os.path.join(tmp, 'dump.lua')
    open(test, 'w').write('SEED = %d\n' % seed + open(os.path.join(ROOT, 'tools', 'dump_plan.lua')).read())
    bundle = subprocess.run(['python3', os.path.join(ROOT, 'tests', 'bundle.py'), test], capture_output=True, text=True, check=True).stdout
    path = os.path.join(tmp, 'b.lua')
    open(path, 'w').write(bundle)
    out = subprocess.run([luau, path], capture_output=True, text=True, check=True).stdout

lines = [l.split() for l in out.splitlines() if l.strip()]
plan = next(l for l in lines if l[0] == 'PLAN')
cols, rows, S = int(plan[1]), int(plan[2]), int(plan[3])
ox, oz = float(plan[4]), float(plan[5])
SCALE = 0.75  # pixels per stud
PAD = 30

def hexc(h, f=1.0):
    h = h.lstrip('#')
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return (int(r * f), int(g * f), int(b * f))

def render(level, name):
    W, H = int(cols * S * SCALE) + PAD * 2, int(rows * S * SCALE) + PAD * 2
    img = Image.new('RGB', (W, H), (12, 13, 16))
    d = ImageDraw.Draw(img)
    def px(x, z):
        return PAD + (x - ox) * SCALE, PAD + (z - oz) * SCALE
    for l in lines:
        if l[0] == 'CELL' and int(l[1]) == level and l[4] != 'Solid':
            c, r = int(l[2]), int(l[3])
            x0, y0 = PAD + (c - 1) * S * SCALE, PAD + (r - 1) * S * SCALE
            d.rectangle([x0, y0, x0 + S * SCALE, y0 + S * SCALE], fill=hexc(l[6], 0.55))
    for l in lines:
        if l[0] == 'PROP' and int(l[1]) == level:
            x, z, w, dd, yaw = map(float, l[2:7])
            a = math.radians(yaw)
            ca, sa = math.cos(a), math.sin(a)
            pts = []
            for lx, lz in [(-w/2, -dd/2), (w/2, -dd/2), (w/2, dd/2), (-w/2, dd/2)]:
                wx = x + lx * ca + lz * sa
                wz = z - lx * sa + lz * ca
                pts.append(px(wx, wz))
            d.polygon(pts, fill=hexc(l[7], 0.9))
    for l in lines:
        if l[0] == 'WALL' and int(l[1]) == level:
            x, z = float(l[2]), float(l[3])
            vertical = l[4] == 'EW'
            opening = l[5] == '1'
            gate = l[6] != '-'
            half = S / 2
            segs = [(-half, -8), (8, half)] if opening else [(-half, half)]
            for a0, a1 in segs:
                if vertical:
                    d.line([px(x, z + a0), px(x, z + a1)], fill=(235, 235, 235), width=3)
                else:
                    d.line([px(x + a0, z), px(x + a1, z)], fill=(235, 235, 235), width=3)
            if gate:
                if vertical:
                    d.line([px(x, z - 8), px(x, z + 8)], fill=(255, 59, 59), width=4)
                else:
                    d.line([px(x - 8, z), px(x + 8, z)], fill=(255, 59, 59), width=4)
    for l in lines:
        if l[0] == 'LOOT' and int(l[1]) == level and float(l[4]) >= 2.5:
            x, z = px(float(l[2]), float(l[3]))
            d.ellipse([x - 2, z - 2, x + 2, z + 2], fill=(183, 107, 255))
        if l[0] == 'CART' and int(l[1]) == level:
            x, z = px(float(l[2]), float(l[3]))
            d.rectangle([x - 2, z - 2, x + 2, z + 2], fill=(90, 180, 255))
        if l[0] == 'SPAWN' and level == 0:
            x, z = px(float(l[1]), float(l[2]))
            d.ellipse([x - 4, z - 4, x + 4, z + 4], fill=(255, 198, 26))
    try:
        font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 13)
    except Exception:
        font = ImageFont.load_default()
    for l in lines:
        if l[0] == 'ZONE' and int(l[1]) == level and len(l) > 4:
            x, z = px(float(l[2]), float(l[3]))
            text = l[4].replace('_', ' ')
            tw = d.textlength(text, font=font)
            d.rectangle([x - tw / 2 - 4, z - 9, x + tw / 2 + 4, z + 9], fill=(10, 10, 12))
            d.text((x - tw / 2, z - 8), text, fill=(255, 198, 26), font=font)
    out_path = os.path.join(ROOT, 'docs', name)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    img.save(out_path)
    print('wrote', out_path, img.size)

render(0, 'map_main.png')
render(-1, 'map_basement.png')
