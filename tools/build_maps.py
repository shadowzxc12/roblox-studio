"""Generates the stud-style world as Rojo JSON models in generated/:

  Lobby.model.json  -> Workspace.Lobby   (waiting plaza with SpawnLocations + 3D MenuScene)
  Map1.model.json   -> ServerStorage.Maps.Map1  "Sunny Meadow"  (open field, trees, rocks)
  Map2.model.json   -> ServerStorage.Maps.Map2  "Block Hills"   (terraced hill with ramps)
  Map3.model.json   -> ServerStorage.Maps.Map3  "Hedge Garden"  (hedge loops, no dead ends)

Simple on purpose: open spaces to run, a few things to run around. Plastic + Studs everywhere.
Run:  python3 tools/build_maps.py  &&  rojo build -o StudChase.rbxlx
"""

import json
import math
import random
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "generated"
OUT.mkdir(exist_ok=True)

INK = "#1b1530"
C = {
    "grass": "#5cc34a", "grass2": "#4fb041", "grass3": "#6fd65a", "path": "#d9b27a", "sand": "#f2d98a",
    "water": "#4cb6ff", "trunk": "#8b5a2b", "plank": "#c58b4b", "plankDark": "#9c6a35",
    "leaf1": "#3fbf4f", "leaf2": "#2ea043", "leaf3": "#7ad957", "pine": "#2f8f4f", "hedge": "#2e9e46",
    "rock": "#9aa3b5", "rock2": "#7d879b", "white": "#ffffff", "plaza": "#e9e1d0", "stone": "#c9cfe0",
    "orange": "#ffbb22", "red": "#ff4f6d", "blue": "#4cc3ff", "purple": "#9b4dff", "yellow": "#ffd23f",
}


def hex3(h):
    h = h.lstrip("#")
    return [round(int(h[i:i + 2], 16) / 255, 4) for i in (0, 2, 4)]


def rot(yaw=0, roll=0):
    """Rotation matrix for yaw (around Y) then roll (around X), degrees."""
    a, b = math.radians(yaw), math.radians(roll)
    cy, sy, cr, sr = math.cos(a), math.sin(a), math.cos(b), math.sin(b)
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rx = [[1, 0, 0], [0, cr, -sr], [0, sr, cr]]
    m = [[sum(ry[i][k] * rx[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return [[round(v, 5) for v in row] for row in m]


def cf(pos, yaw=0, roll=0):
    return {"CFrame": {"position": [round(v, 3) for v in pos], "orientation": rot(yaw, roll)}}


def part(name, size, pos, color, shape=None, yaw=0, cls="Part", roll=0, **props):
    p = {
        "Anchored": True,
        "Size": [round(v, 3) for v in size],
        "CFrame": cf(pos, yaw, roll),
        "Color": hex3(color),
        "Material": "Plastic",
        "TopSurface": "Studs",
        "BottomSurface": "Inlet",
    }
    if shape:
        p["Shape"] = shape
    p.update(props)
    return {"Name": name, "ClassName": cls, "Properties": p}


def model(name, children, attrs=None):
    m = {"Name": name, "ClassName": "Model", "Children": children}
    if attrs:
        typed = {k: ({"String": v} if isinstance(v, str) else {"Float64": float(v)}) for k, v in attrs.items()}
        m["Properties"] = {"Attributes": {"Attributes": typed}}
    return m


def folder(name, children):
    return {"Name": name, "ClassName": "Folder", "Children": children}


def label_gui(text, color, face="Front", size=50):
    return {
        "Name": "SignGui", "ClassName": "SurfaceGui",
        "Properties": {"Face": face, "SizingMode": "PixelsPerStud", "PixelsPerStud": size},
        "Children": [{
            "Name": "Label", "ClassName": "TextLabel",
            "Properties": {"Size": {"UDim2": [[1, 0], [1, 0]]}, "BackgroundTransparency": 1, "Text": text,
                           "TextScaled": True, "Font": "FredokaOne", "TextColor3": hex3(color)},
            "Children": [{"Name": "Outline", "ClassName": "UIStroke", "Properties": {"Thickness": 6, "Color": hex3(INK)}}],
        }],
    }


# ---------- reusable props --------------------------------------------------------------

def tree_round(x, z, y=0, rng=random):
    h, s = rng.uniform(7, 10), rng.uniform(10, 13)
    leaf = rng.choice([C["leaf1"], C["leaf2"], C["leaf3"]])
    return model("Tree", [
        part("Trunk", [2.4, h, 2.4], [x, y + h / 2, z], C["trunk"]),
        part("Leaves", [s, s, s], [x, y + h + s * 0.25, z], leaf, shape="Ball"),
    ])


def tree_block(x, z, y=0, rng=random):
    h = rng.uniform(6, 8)
    yaw = rng.uniform(0, 90)
    leaf = rng.choice([C["leaf1"], C["leaf2"]])
    return model("Tree", [
        part("Trunk", [3, h, 3], [x, y + h / 2, z], C["trunk"], yaw=yaw),
        part("Leaves", [11, 5, 11], [x, y + h + 1.5, z], leaf, yaw=yaw),
        part("Leaves", [7, 4, 7], [x, y + h + 6, z], leaf, yaw=yaw),
    ])


def tree_pine(x, z, y=0, rng=random):
    yaw = rng.uniform(0, 90)
    ps = [part("Trunk", [2, 5, 2], [x, y + 2.5, z], C["trunk"], yaw=yaw)]
    yy = y + 5
    for w in (10, 7.5, 5, 2.5):
        ps.append(part("Needles", [w, 3.5, w], [x, yy + 1.75, z], C["pine"], yaw=yaw))
        yy += 3
    return model("PineTree", ps)


def rock(x, z, y=0, rng=random):
    w = rng.uniform(4, 7)
    return part("Rock", [w, w * 0.7, w * 0.85], [x, y + w * 0.35, z], rng.choice([C["rock"], C["rock2"]]), yaw=rng.uniform(0, 90))


def bush(x, z, y=0, rng=random):
    s = rng.uniform(4, 6)
    return part("Bush", [s, s, s], [x, y + s * 0.35, z], rng.choice([C["leaf1"], C["leaf3"]]), shape="Ball")


def flowers(x, z, y=0, rng=random):
    color = rng.choice([C["red"], C["yellow"], "#ff7ab6", "#b98cff", C["white"]])
    ps = []
    for _ in range(5):
        fx, fz = x + rng.uniform(-3, 3), z + rng.uniform(-3, 3)
        ps.append(part("Stem", [0.4, 1.4, 0.4], [fx, y + 0.7, fz], "#2a9d4b", CanCollide=False))
        ps.append(part("Petals", [1.4, 0.6, 1.4], [fx, y + 1.6, fz], color, yaw=rng.uniform(0, 90), CanCollide=False))
    return model("Flowers", ps)


def arena_walls(cx, cz, size, color="#9c6a35", height=4):
    """Low visible wooden fence + tall invisible wall so nobody leaves the arena."""
    half = size / 2
    out = []
    for dx, dz, w, d in [(0, -half, size + 2, 1.5), (0, half, size + 2, 1.5), (-half, 0, 1.5, size + 2), (half, 0, 1.5, size + 2)]:
        out.append(part("Fence", [w, height, d], [cx + dx, height / 2, cz + dz], color))
        out.append(part("InvisibleWall", [w, 60, d], [cx + dx, 30, cz + dz], C["white"], Transparency=1, TopSurface="Smooth", BottomSurface="Smooth"))
    return out


def spawns(cx, cz, radius, count, chaser_spots, obstacles=()):
    """Spawn points on a circle; each one slides along the circle until it is clear of obstacles."""
    out = []
    for i in range(count):
        a = i / count * math.tau
        for _ in range(40):
            x, z = cx + math.cos(a) * radius, cz + math.sin(a) * radius
            if all(math.hypot(x - ox, z - oz) > 9 for ox, oz in obstacles):
                break
            a += 0.03
        out.append(part("Spawn", [4, 1, 4], [x, 0.5, z], C["white"],
                        Transparency=1, CanCollide=False, CanQuery=False, CanTouch=False))
    for (x, z) in chaser_spots:
        out.append(part("ChaserSpawn", [4, 1, 4], [cx + x, 0.5, cz + z], C["red"],
                        Transparency=1, CanCollide=False, CanQuery=False, CanTouch=False))
    return folder("Spawns", out)


def write(name, root):
    root = dict(root)
    root.pop("Name", None)  # Rojo names the instance after the project entry
    (OUT / f"{name}.model.json").write_text(json.dumps(root, indent=1))


def count_parts(n):
    return (1 if n.get("ClassName") in ("Part", "SpawnLocation", "WedgePart") else 0) + sum(count_parts(c) for c in n.get("Children", []))


# =========================================================================================
# LOBBY (+ 3D menu scene)
# =========================================================================================
def build_lobby():
    rng = random.Random(1)
    kids = []
    # waiting plaza where players stand between rounds
    kids.append(part("Ground", [140, 4, 140], [0, -2, 0], C["grass"]))
    kids.append(part("Plaza", [60, 0.6, 60], [0, 0.3, 0], C["plaza"]))
    for i, (x, z) in enumerate([(-10, -10), (10, -10), (-10, 10), (10, 10)]):
        kids.append({
            "Name": "SpawnLocation", "ClassName": "SpawnLocation",
            "Properties": {"Anchored": True, "Size": [8, 1, 8], "CFrame": cf([x, 0.8, z]), "Color": hex3(["#6a3df0", "#ff6a3d", "#6ad13a", "#4cc3ff"][i]),
                           "Material": "Plastic", "TopSurface": "Studs", "BottomSurface": "Inlet", "Neutral": True, "Duration": 0},
        })
    # big sign
    sign = part("Sign", [36, 9, 1], [0, 9, -28], C["white"])
    sign["Children"] = [label_gui("STUD CHASE", C["yellow"], face="Back")]
    kids += [sign, part("SignPostL", [1.5, 6, 1.5], [-15, 3, -28], C["plankDark"]), part("SignPostR", [1.5, 6, 1.5], [15, 3, -28], C["plankDark"])]
    for x in (-30, 30):
        for z in range(-30, 31, 6):
            kids.append(part("Post", [1, 3, 1], [x, 1.5, z], C["plankDark"]))
    for z in (-30, 30):
        for x in range(-30, 31, 6):
            kids.append(part("Post", [1, 3, 1], [x, 1.5, z], C["plankDark"]))
    for x, z in [(-50, -50), (50, -50), (-50, 50), (50, 50), (-55, 0), (55, 0), (0, 55)]:
        kids.append(rng.choice([tree_round, tree_block, tree_pine])(x, z, rng=rng))
    for _ in range(10):
        kids.append(flowers(rng.uniform(-60, 60), rng.choice([-1, 1]) * rng.uniform(38, 62), rng=rng))
    # benches
    for x in (-20, 20):
        kids.append(model("Bench", [part("Seat", [8, 1, 3], [x, 1.5, 22], C["plank"]),
                                    part("LegL", [1, 1.5, 3], [x - 3, 0.75, 22], C["plankDark"]),
                                    part("LegR", [1, 1.5, 3], [x + 3, 0.75, 22], C["plankDark"])]))
    kids.append(part("InvisibleWalls", [140, 60, 1], [0, 30, -70], C["white"], Transparency=1))
    kids.append(part("InvisibleWalls", [140, 60, 1], [0, 30, 70], C["white"], Transparency=1))
    kids.append(part("InvisibleWalls", [1, 60, 140], [-70, 30, 0], C["white"], Transparency=1))
    kids.append(part("InvisibleWalls", [1, 60, 140], [70, 30, 0], C["white"], Transparency=1))

    # ---- 3D menu scene: an island far away that only the menu camera looks at ----
    mz = -260
    scene = []
    scene.append(part("Island", [70, 6, 70], [0, -3, mz], C["grass"]))
    scene.append(part("IslandEdge", [74, 4, 74], [0, -6, mz], "#8b5a2b"))
    for i in range(28):  # running track (ring of path tiles)
        a = i / 28 * math.tau
        scene.append(part("Track", [4.2, 0.3, 3.5], [math.cos(a) * 13, 0.15, mz + math.sin(a) * 13], C["path"], yaw=-math.degrees(a), CanCollide=False))
    for x, z in [(-26, -20), (24, -24), (-22, 24), (27, 18), (0, -30), (-30, 2)]:
        scene.append(rng.choice([tree_round, tree_block, tree_pine])(x, mz + z, rng=rng))
    scene.append(part("Mound", [12, 1, 12], [0, 0.5, mz], C["grass3"]))  # low centre so the runners stay visible
    for x, z in [(-3, -2), (3, 2)]:
        scene.append(flowers(x, mz + z, y=1, rng=rng))
    for _ in range(8):
        a = rng.uniform(0, math.tau)
        scene.append(flowers(math.cos(a) * rng.uniform(19, 28), mz + math.sin(a) * rng.uniform(19, 28), rng=rng))
    scene.append(part("CameraFocus", [1, 1, 1], [0, 2, mz], C["white"], Transparency=1, CanCollide=False, CanQuery=False, CanTouch=False))
    sparkle = part("SparkleEmitter", [40, 1, 40], [0, 6, mz], C["white"], Transparency=1, CanCollide=False, CanQuery=False, CanTouch=False)
    sparkle["Children"] = [{"Name": "Sparkles", "ClassName": "ParticleEmitter",
                            "Properties": {"Rate": 6, "LightEmission": 0.6,
                                           "Lifetime": {"NumberRange": [2, 4]}, "Speed": {"NumberRange": [1, 3]},
                                           "Color": {"ColorSequence": {"keypoints": [{"time": 0, "color": hex3(C["yellow"])}, {"time": 1, "color": hex3(C["white"])}]}}}}]
    scene.append(sparkle)

    # blocky characters chasing each other around the track (animated by the client)
    chars = []
    shirts = [("Chaser", "#ff4a2e", "#7a1d10"), ("Runner1", "#4cc3ff", "#1b5fd1"), ("Runner2", "#ffd23f", "#9c6a35"), ("Runner3", "#b98cff", "#5b2bb8")]
    for lane, (name, shirt, pants) in enumerate(shirts):
        x, z = 13, mz + lane * 4
        body = [
            part("Torso", [2, 2, 1], [x, 3, z], shirt, CanCollide=False),
            part("Head", [1.4, 1.4, 1.4], [x, 4.75, z], "#ffd9a0", CanCollide=False),
            part("LeftArm", [1, 2, 1], [x - 1.5, 3, z], shirt, CanCollide=False),
            part("RightArm", [1, 2, 1], [x + 1.5, 3, z], shirt, CanCollide=False),
            part("LeftLeg", [1, 2, 1], [x - 0.5, 1, z], pants, CanCollide=False),
            part("RightLeg", [1, 2, 1], [x + 0.5, 1, z], pants, CanCollide=False),
        ]
        if lane == 0:
            body[1]["Children"] = [{
                "Name": "Label", "ClassName": "BillboardGui",
                "Properties": {"Size": {"UDim2": [[5, 0], [1.2, 0]]}, "StudsOffset": [0, 2.2, 0], "AlwaysOnTop": False, "LightInfluence": 0},
                "Children": [{"Name": "Text", "ClassName": "TextLabel",
                              "Properties": {"Size": {"UDim2": [[1, 0], [1, 0]]}, "BackgroundTransparency": 1, "Text": "CHASER", "TextScaled": True,
                                             "Font": "FredokaOne", "TextColor3": hex3("#ff4a2e")},
                              "Children": [{"Name": "Stroke", "ClassName": "UIStroke", "Properties": {"Thickness": 2, "Color": hex3(INK)}}]}],
            }]
        m = model(name, body, attrs={"Lane": lane})
        if lane == 0:
            m["Children"].append({"Name": "Glow", "ClassName": "Highlight",
                                  "Properties": {"FillColor": hex3("#ff4a2e"), "FillTransparency": 0.75, "OutlineColor": hex3("#ffb21c")}})
        chars.append(m)
    scene.append(folder("Characters", chars))
    kids.append(model("MenuScene", scene))

    root = model("Lobby", kids)
    write("Lobby", root)
    return root


# =========================================================================================
# MAP 1: Sunny Meadow - open field, a few trees and rocks to run around
# =========================================================================================
MAP_Z = 500  # maps live far from the lobby


def build_map1():
    rng = random.Random(11)
    cx, cz, size = 0, MAP_Z, 130
    kids = [part("Ground", [size + 10, 4, size + 10], [cx, -2, cz], C["grass"])]
    for _ in range(14):
        kids.append(part("GrassPatch", [rng.choice([12, 18, 24]), 0.2, rng.choice([12, 18, 24])],
                         [cx + rng.uniform(-55, 55), 0.1, cz + rng.uniform(-55, 55)], rng.choice([C["grass2"], C["grass3"]]), CanCollide=False))
    spots = [(-35, -35), (35, -30), (-30, 30), (32, 36), (0, -48), (-50, 0), (50, 5), (5, 48), (-15, 10), (18, -12)]
    for i, (x, z) in enumerate(spots):
        kids.append((tree_round if i % 2 else tree_block)(cx + x, cz + z, rng=rng))
    for x, z in [(-20, -20), (22, 20), (-45, 40), (44, -45), (0, 25), (-5, -28)]:
        kids.append(rock(cx + x, cz + z, rng=rng))
    for x, z in [(-28, 8), (28, -2), (10, 38), (-12, -45)]:
        kids.append(bush(cx + x, cz + z, rng=rng))
    # small pond with a sand rim (water is walkable/shallow)
    kids.append(part("Sand", [26, 0.4, 18], [cx + 30, 0.2, cz + 20], C["sand"]))
    kids.append(part("Water", [22, 0.3, 14], [cx + 30, 0.45, cz + 20], C["water"], Transparency=0.25, Material="SmoothPlastic", TopSurface="Smooth", CanCollide=False))
    # crates to jump on
    for x, z, h in [(-8, 0, 3), (-4, 0, 3), (-6, 0, 6)]:
        kids.append(part("Crate", [4, 3, 4], [cx + x, h - 1.5, cz + z - 30], C["plank"]))
    kids += arena_walls(cx, cz, size)
    for _ in range(8):
        kids.append(flowers(cx + rng.uniform(-58, 58), cz + rng.uniform(-58, 58), rng=rng))
    obstacles = [(cx + x, cz + z) for x, z in spots] + [(cx + x, cz + z) for x, z in [(-20, -20), (22, 20), (-45, 40), (44, -45), (0, 25), (-5, -28), (-28, 8), (28, -2), (10, 38), (-12, -45), (30, 20), (-6, -30)]]
    kids.append(spawns(cx, cz, 50, 12, [(0, 0)], obstacles))
    root = model("Map1", kids, attrs={"DisplayName": "Sunny Meadow"})
    write("Map1", root)
    return root


# =========================================================================================
# MAP 2: Block Hills - a big terraced hill in the middle with ramps, smaller hills around
# =========================================================================================
def build_map2():
    rng = random.Random(22)
    cx, cz, size = 0, MAP_Z, 140
    kids = [part("Ground", [size + 10, 4, size + 10], [cx, -2, cz], C["grass"])]
    # central hill: two levels, ramps (WedgeParts) on all four sides
    kids.append(part("HillLow", [44, 4, 44], [cx, 2, cz], C["grass2"]))
    kids.append(part("HillHigh", [22, 4, 22], [cx, 6, cz], C["grass"]))
    for yaw, (dx, dz) in [(0, (0, 28)), (180, (0, -28)), (90, (28, 0)), (270, (-28, 0))]:
        # low ramp: wedge rising toward the hill
        kids.append(part("Ramp", [8, 4, 12], [cx + dx, 2, cz + dz], C["path"], cls="WedgePart", yaw=yaw + 180, TopSurface="Smooth"))
    for yaw, (dx, dz) in [(0, (0, 17)), (180, (0, -17))]:
        kids.append(part("RampHigh", [6, 4, 8], [cx + dx, 6, cz + dz], C["path"], cls="WedgePart", yaw=yaw + 180, TopSurface="Smooth"))
    kids.append(tree_pine(cx, cz, y=8, rng=rng))
    # corner hills (one step, jumpable)
    for x, z in [(-45, -45), (45, -45), (-45, 45), (45, 45)]:
        kids.append(part("SmallHill", [20, 3, 20], [cx + x, 1.5, cz + z], C["grass3"]))
        kids.append(rng.choice([tree_round, tree_block])(cx + x + 4, cz + z + 4, y=3, rng=rng))
    for x, z in [(-25, -50), (25, 50), (-55, 15), (55, -15)]:
        kids.append(rock(cx + x, cz + z, rng=rng))
    for x, z in [(0, -55), (0, 55), (-58, -10), (58, 10)]:
        kids.append(tree_round(cx + x, cz + z, rng=rng))
    kids += arena_walls(cx, cz, size)
    obstacles = [(cx + x, cz + z) for x, z in [(-25, -50), (25, 50), (-55, 15), (55, -15), (0, -55), (0, 55), (-58, -10), (58, 10)]]
    obstacles += [(cx + x, cz + z) for x in (-45, 45) for z in (-45, 45)]
    kids.append(spawns(cx, cz, 55, 12, [(0, 0)], obstacles))
    # the chaser spawn is on top of the hill
    kids[-1]["Children"][-1]["Properties"]["CFrame"] = cf([cx, 8.5, cz])
    root = model("Map2", kids, attrs={"DisplayName": "Block Hills"})
    write("Map2", root)
    return root


# =========================================================================================
# MAP 3: Hedge Garden - hedges form loops around a fountain (always two ways to run)
# =========================================================================================
def build_map3():
    rng = random.Random(33)
    cx, cz, size = 0, MAP_Z, 120
    kids = [part("Ground", [size + 10, 4, size + 10], [cx, -2, cz], C["grass"])]
    H = 8  # hedges are taller than a jump
    hedges = [
        # inner ring around the fountain with 4 gaps
        (-12, -18, 16, 2), (12, -18, 16, 2), (-12, 18, 16, 2), (12, 18, 16, 2),
        (-18, -10, 2, 12), (-18, 10, 2, 12), (18, -10, 2, 12), (18, 10, 2, 12),
        # outer blocks (islands you can circle around)
        (-38, -38, 18, 2), (38, -38, 18, 2), (-38, 38, 18, 2), (38, 38, 18, 2),
        (-38, 0, 2, 22), (38, 0, 2, 22), (0, -40, 22, 2), (0, 40, 22, 2),
    ]
    for x, z, w, d in hedges:
        kids.append(part("Hedge", [w, H, d], [cx + x, H / 2, cz + z], C["hedge"]))
    # fountain
    kids.append(part("FountainBase", [12, 1.5, 12], [cx, 0.75, cz], C["stone"]))
    kids.append(part("FountainWater", [10, 0.3, 10], [cx, 1.55, cz], C["water"], Transparency=0.2, Material="SmoothPlastic", TopSurface="Smooth", CanCollide=False))
    kids.append(part("FountainPillar", [2, 5, 2], [cx, 3, cz], C["stone"]))
    kids.append(part("FountainTop", [5, 1, 5], [cx, 5.5, cz], C["stone"]))
    # paths
    for x, z, w, d in [(0, 0, 4, 100), (0, 0, 100, 4)]:
        kids.append(part("Path", [w, 0.2, d], [cx + x, 0.1, cz + z], C["path"], CanCollide=False))
    for _ in range(12):
        kids.append(flowers(cx + rng.uniform(-52, 52), cz + rng.uniform(-52, 52), rng=rng))
    for x, z in [(-50, -50), (50, -50), (-50, 50), (50, 50)]:
        kids.append(tree_round(cx + x, cz + z, rng=rng))
    kids += arena_walls(cx, cz, size, color=C["hedge"], height=H)
    kids.append(spawns(cx, cz, 48, 12, [(0, 8)], [(cx + x, cz + z) for x, z in [(-50, -50), (50, -50), (-50, 50), (50, 50)]]))
    root = model("Map3", kids, attrs={"DisplayName": "Hedge Garden"})
    write("Map3", root)
    return root


if __name__ == "__main__":
    for fn in (build_lobby, build_map1, build_map2, build_map3):
        r = fn()
        print(f"{fn.__name__}: {count_parts(r)} parts")
