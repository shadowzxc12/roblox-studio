"""Generates map/NatureMap.model.json: a simple, cartoon "stud style" nature map.

Everything is Plastic parts with Studs on top (classic Roblox look), no Terrain,
no realistic materials. Run:  python3 tools/build_map.py   then   rojo build -o KiddoShopGame.rbxlx
"""

import json
import math
import random
from pathlib import Path

random.seed(7)  # same map every time

OUT = Path(__file__).resolve().parent.parent / "map" / "NatureMap.model.json"
HALF = 200  # map is 400 x 400 studs


def hex3(h):
    h = h.lstrip("#")
    return [round(int(h[i : i + 2], 16) / 255, 4) for i in (0, 2, 4)]


C = {
    "grass": "#5cc34a",
    "grass2": "#4fb041",
    "grass3": "#6fd65a",
    "path": "#d9b27a",
    "sand": "#f2d98a",
    "water": "#4cb6ff",
    "trunk": "#8b5a2b",
    "plank": "#c58b4b",
    "plankDark": "#9c6a35",
    "leaf1": "#3fbf4f",
    "leaf2": "#2ea043",
    "leaf3": "#7ad957",
    "pine": "#2f8f4f",
    "rock": "#9aa3b5",
    "rock2": "#7d879b",
    "stem": "#2a9d4b",
    "cloud": "#ffffff",
    "plaza": "#e9e1d0",
    "orange": "#ffbb22",
    "orange2": "#ff9d00",
    "red": "#ff4f6d",
    "white": "#ffffff",
}
FLOWERS = ["#ff4f6d", "#ffd23f", "#ff7ab6", "#b98cff", "#ffffff", "#4cc3ff"]


def rot_y(deg):
    a = math.radians(deg)
    c, s = round(math.cos(a), 5), round(math.sin(a), 5)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def part(name, size, pos, color, shape=None, yaw=0, **props):
    p = {
        "Anchored": True,
        "Size": [round(v, 3) for v in size],
        "CFrame": {"CFrame": {"position": [round(v, 3) for v in pos], "orientation": rot_y(yaw)}},
        "Color": hex3(color),
        "Material": "Plastic",
        "TopSurface": "Studs",
        "BottomSurface": "Inlet",
    }
    if shape:
        p["Shape"] = shape
    p.update(props)
    return {"Name": name, "ClassName": "Part", "Properties": p}


def model(name, children):
    return {"Name": name, "ClassName": "Model", "Children": children}


def folder(name, children):
    return {"Name": name, "ClassName": "Folder", "Children": children}


# --- keep-out zones so things don't overlap -------------------------------------------

blocked = []  # (x, z, radius)


def free(x, z, r):
    if abs(x) > HALF - 8 or abs(z) > HALF - 8:
        return False
    return all(math.hypot(x - bx, z - bz) > r + br for bx, bz, br in blocked)


def block(x, z, r):
    blocked.append((x, z, r))


# --- ground, spawn, plaza ----------------------------------------------------------------

ground = [part("Baseplate", [HALF * 2 + 40, 8, HALF * 2 + 40], [0, -4, 0], C["grass"])]

# patchwork of slightly different greens so the big field isn't flat
for _ in range(40):
    w, d = random.choice([16, 24, 32]), random.choice([16, 24, 32])
    x, z = random.uniform(-HALF + 20, HALF - 20), random.uniform(-HALF + 20, HALF - 20)
    ground.append(part("GrassPatch", [w, 0.2, d], [x, 0.1, z], random.choice([C["grass2"], C["grass3"]]), CanCollide=False))

plaza = [part("Plaza", [44, 0.6, 44], [0, 0.3, 0], C["plaza"])]
block(0, 0, 30)
spawn = {
    "Name": "SpawnLocation",
    "ClassName": "SpawnLocation",
    "Properties": {
        "Anchored": True,
        "Size": [12, 1, 12],
        "CFrame": {"CFrame": {"position": [0, 0.8, 6], "orientation": rot_y(0)}},
        "Color": hex3("#6a3df0"),
        "Material": "Plastic",
        "TopSurface": "Studs",
        "BottomSurface": "Inlet",
        "Neutral": True,
        "Duration": 0,
    },
}
plaza.append(spawn)

# low fence around the plaza with gaps for the 4 paths
fence = []
for side in range(4):
    for i in range(-20, 21, 4):
        if abs(i) <= 6:
            continue
        x, z = (i, -22) if side == 0 else (i, 22) if side == 1 else (-22, i) if side == 2 else (22, i)
        fence.append(part("Post", [1, 3, 1], [x, 2.1, z], C["plankDark"]))
    for a, b in [(-20, -8), (8, 20)]:
        mid, ln = (a + b) / 2, b - a
        if side < 2:
            z = -22 if side == 0 else 22
            fence.append(part("Rail", [ln, 0.6, 0.6], [mid, 2.6, z], C["plank"]))
        else:
            x = -22 if side == 2 else 22
            fence.append(part("Rail", [0.6, 0.6, ln], [x, 2.6, mid], C["plank"]))
plaza.append(model("Fence", fence))

# --- shop stand (opens the shop UI with a ProximityPrompt) ---------------------------

shop = []
sx, sz = -12, -12
shop.append(part("Counter", [10, 3, 4], [sx, 2.1, sz], C["plank"]))
shop.append(part("PostL", [1, 8, 1], [sx - 4.5, 4.6, sz - 1.5], C["plankDark"]))
shop.append(part("PostR", [1, 8, 1], [sx + 4.5, 4.6, sz - 1.5], C["plankDark"]))
for i in range(6):  # orange striped roof
    shop.append(part("Roof", [2, 1, 7], [sx - 5 + i * 2, 9, sz - 0.5], C["orange"] if i % 2 == 0 else C["orange2"]))
sign = part("Sign", [8, 2.4, 0.4], [sx, 7.2, sz + 0.6], C["white"])
sign["Children"] = [
    {
        "Name": "SignGui",
        "ClassName": "SurfaceGui",
        "Properties": {"Face": "Back", "SizingMode": "PixelsPerStud", "PixelsPerStud": 50},
        "Children": [
            {
                "Name": "Label",
                "ClassName": "TextLabel",
                "Properties": {
                    "Size": {"UDim2": [[1, 0], [1, 0]]},
                    "BackgroundTransparency": 1,
                    "Text": "SHOP",
                    "TextScaled": True,
                    "Font": "FredokaOne",
                    "TextColor3": hex3("#ff9d00"),
                },
                "Children": [{"Name": "Outline", "ClassName": "UIStroke", "Properties": {"Thickness": 4, "Color": hex3("#1b1530")}}],
            }
        ],
    }
]
shop.append(sign)
counter = shop[0]
counter["Children"] = [
    {
        "Name": "OpenShop",
        "ClassName": "ProximityPrompt",
        "Properties": {"ActionText": "Open Shop", "ObjectText": "Shop", "HoldDuration": 0, "MaxActivationDistance": 12},
    }
]
plaza.append(model("ShopStand", shop))

# --- paths ---------------------------------------------------------------------------

paths = []
for dx, dz in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
    for step in range(26, 150, 8):
        x = dx * step + (random.uniform(-1.5, 1.5) if dx == 0 else 0)
        z = dz * step + (random.uniform(-1.5, 1.5) if dz == 0 else 0)
        paths.append(part("PathTile", [8, 0.3, 8], [x, 0.15, z], C["path"], yaw=random.uniform(-6, 6), CanCollide=False))
        block(x, z, 6)

# --- pond with sand rim and a bridge (north) -----------------------------------------

pond = []
px, pz = 0, -110
pond.append(part("Sand", [76, 0.4, 56], [px, 0.2, pz], C["sand"]))
pond.append(part("PondFloor", [64, 0.1, 44], [px, 0.45, pz], "#2f86d6"))
pond.append(
    part("Water", [64, 0.5, 44], [px, 0.75, pz], C["water"], Transparency=0.3, Material="SmoothPlastic", TopSurface="Smooth", CanCollide=False)
)
for x, z, w, d in [(0, -23, 68, 2), (0, 23, 68, 2), (-33, 0, 2, 44), (33, 0, 2, 44)]:  # sand rim
    pond.append(part("Rim", [w, 1.4, d], [px + x, 0.7, pz + z], C["sand"]))
for i in range(-12, 13):  # arched wooden bridge across the pond, along the path
    pond.append(part("Plank", [7, 0.6, 2], [px, 1.7 + math.cos(i / 12 * math.pi / 2) * 1.6, pz + i * 2.1], C["plank"] if i % 2 else C["plankDark"]))
for x in (-3.8, 3.8):
    for i in range(-12, 13, 4):
        pond.append(part("BridgePost", [0.6, 3, 0.6], [px + x, 3 + math.cos(i / 12 * math.pi / 2) * 1.6, pz + i * 2.1], C["plankDark"]))
for _ in range(8):  # lily pads
    a = random.uniform(0, math.tau)
    pond.append(part("LilyPad", [3, 0.2, 3], [px + 12 * (1 if math.cos(a) > 0 else -1) + math.cos(a) * random.uniform(0, 14), 1.1, pz + math.sin(a) * random.uniform(4, 16)], C["leaf1"], CanCollide=False))
block(px, pz, 40)

# --- terraced hills (east, north-east, south-west) -----------------------------------

hills = []


def hill(cx, cz, layers):
    w, d = layers
    y = 0
    k = 0
    while w > 10 and d > 10:
        hills.append(part("HillLayer", [w, 5, d], [cx + random.uniform(-3, 3), y + 2.5, cz + random.uniform(-3, 3)], [C["grass"], C["grass2"]][k % 2]))
        y += 5
        w -= random.choice([14, 18])
        d -= random.choice([14, 18])
        k += 1
    block(cx, cz, max(layers) / 2 + 4)


hill(120, 40, (84, 70))
hill(130, -120, (70, 90))
hill(-130, 120, (90, 76))
hill(-150, -60, (60, 60))

# --- trees, bushes, rocks, flowers, mushrooms -----------------------------------------

trees = []


def tree_round(x, z):
    h = random.uniform(8, 12)
    s = random.uniform(11, 15)
    leaf = random.choice([C["leaf1"], C["leaf2"], C["leaf3"]])
    return model("RoundTree", [
        part("Trunk", [2.4, h, 2.4], [x, h / 2, z], C["trunk"], yaw=random.uniform(0, 90)),
        part("Leaves", [s, s, s], [x, h + s * 0.3, z], leaf, shape="Ball"),
        part("Leaves", [s * 0.6] * 3, [x + s * 0.3, h + s * 0.55, z - s * 0.2], leaf, shape="Ball"),
    ])


def tree_block(x, z):
    h = random.uniform(7, 10)
    yaw = random.uniform(0, 90)
    leaf = random.choice([C["leaf1"], C["leaf2"]])
    return model("BlockTree", [
        part("Trunk", [3, h, 3], [x, h / 2, z], C["trunk"], yaw=yaw),
        part("Leaves", [13, 6, 13], [x, h + 2, z], leaf, yaw=yaw),
        part("Leaves", [9, 4, 9], [x, h + 7, z], leaf, yaw=yaw),
        part("Leaves", [5, 3, 5], [x, h + 10.5, z], leaf, yaw=yaw),
    ])


def tree_pine(x, z):
    yaw = random.uniform(0, 90)
    parts = [part("Trunk", [2, 6, 2], [x, 3, z], C["trunk"], yaw=yaw)]
    y = 6
    for w in (12, 9, 6, 3):
        parts.append(part("Needles", [w, 4, w], [x, y + 2, z], C["pine"], yaw=yaw))
        y += 3.5
    return model("PineTree", parts)


def place(n, r, fn, region=None, tries=4000):
    out = []
    for _ in range(tries):
        if len(out) >= n:
            break
        if region:
            x, z = random.uniform(*region[0]), random.uniform(*region[1])
        else:
            x, z = random.uniform(-HALF, HALF), random.uniform(-HALF, HALF)
        if free(x, z, r):
            block(x, z, r)
            out.append(fn(x, z))
    return out


# dense forest ring along the edge (hides the edge of the world)
for edge, check in ((HALF - 12, True), (HALF + 8, False)):  # inner ring + a ring outside the walls
    for i in range(-HALF - 8, HALF + 9, 11):
        for x, z in [(i, -edge), (i, edge), (-edge, i), (edge, i)]:
            x += random.uniform(-3, 3)
            z += random.uniform(-3, 3)
            if check and not free(x, z, 5):
                continue
            block(x, z, 5)
            trees.append(random.choice([tree_pine, tree_pine, tree_round, tree_block])(x, z))

trees += place(28, 7, tree_pine, region=((-60, 90), (60, 180)))  # south forest
trees += place(26, 7, lambda x, z: random.choice([tree_round, tree_block])(x, z))  # scattered
trees += place(10, 7, tree_round, region=((-190, -40), (-40, 60)))  # west meadow edge

nature = []


def bush(x, z):
    s = random.uniform(4, 7)
    return part("Bush", [s, s, s], [x, s * 0.35, z], random.choice([C["leaf1"], C["leaf3"]]), shape="Ball")


def rock(x, z):
    w = random.uniform(3, 8)
    parts = [part("Rock", [w, w * 0.7, w * 0.8], [x, w * 0.35, z], random.choice([C["rock"], C["rock2"]]), yaw=random.uniform(0, 90))]
    if w > 5:
        parts.append(part("Rock", [w * 0.5] * 3, [x + w * 0.4, w * 0.25, z + w * 0.3], C["rock"], yaw=random.uniform(0, 90)))
    return model("Rock", parts)


def mushroom(x, z):
    h = random.uniform(1.5, 3)
    cap = random.uniform(2.5, 4)
    parts = [
        part("Stem", [cap * 0.35, h, cap * 0.35], [x, h / 2, z], C["white"]),
        part("Cap", [cap, cap * 0.35, cap], [x, h + cap * 0.17, z], C["red"]),
    ]
    for dx, dz in [(-0.25, -0.2), (0.25, 0.1), (0, 0.3)]:
        parts.append(part("Dot", [0.5, 0.2, 0.5], [x + dx * cap, h + cap * 0.36, z + dz * cap], C["white"], CanCollide=False))
    return model("Mushroom", parts)


def flowers(x, z):
    parts = []
    color = random.choice(FLOWERS)
    for _ in range(random.randint(5, 9)):
        fx, fz = x + random.uniform(-4, 4), z + random.uniform(-4, 4)
        hgt = random.uniform(1.2, 2.2)
        parts.append(part("Stem", [0.4, hgt, 0.4], [fx, hgt / 2, fz], C["stem"], CanCollide=False))
        parts.append(part("Petals", [1.4, 0.6, 1.4], [fx, hgt + 0.2, fz], color, yaw=random.uniform(0, 90), CanCollide=False))
        parts.append(part("Middle", [0.6, 0.3, 0.6], [fx, hgt + 0.6, fz], "#ffd23f", CanCollide=False))
    return model("Flowers", parts)


nature += place(30, 4, bush)
nature += place(22, 5, rock)
nature += place(10, 3, mushroom, region=((-60, 90), (60, 180)))
nature += place(16, 5, flowers, region=((-190, -30), (-60, 90)))  # west flower meadow
nature += place(14, 5, flowers)

# --- clouds ----------------------------------------------------------------------------

clouds = []
for _ in range(14):
    x, z, y = random.uniform(-HALF, HALF), random.uniform(-HALF, HALF), random.uniform(80, 120)
    cl = []
    for _ in range(random.randint(3, 5)):
        w = random.uniform(12, 24)
        cl.append(
            part("Puff", [w, w * 0.45, w * 0.7], [x + random.uniform(-12, 12), y + random.uniform(-2, 3), z + random.uniform(-6, 6)], C["cloud"],
                 CanCollide=False, CastShadow=False)
        )
    clouds.append(model("Cloud", cl))

# --- invisible walls at the edge --------------------------------------------------------

walls = []
for x, z, sx_, sz_ in [(0, -HALF - 2, HALF * 2 + 8, 4), (0, HALF + 2, HALF * 2 + 8, 4), (-HALF - 2, 0, 4, HALF * 2 + 8), (HALF + 2, 0, 4, HALF * 2 + 8)]:
    walls.append(part("Wall", [sx_, 80, sz_], [x, 40, z], C["white"], Transparency=1, TopSurface="Smooth", BottomSurface="Smooth"))

root = model("NatureMap", [
    folder("Ground", ground),
    folder("Plaza", plaza),
    folder("Paths", paths),
    folder("Pond", pond),
    folder("Hills", hills),
    folder("Trees", trees),
    folder("Nature", nature),
    folder("Clouds", clouds),
    folder("Walls", walls),
])


def count(n):
    return (1 if n["ClassName"] in ("Part", "SpawnLocation") else 0) + sum(count(c) for c in n.get("Children", []))


OUT.parent.mkdir(parents=True, exist_ok=True)
root.pop("Name")  # Rojo names the model after the file
OUT.write_text(json.dumps(root, indent=1))
print(f"wrote {OUT} with {count(root)} parts")
