#!/usr/bin/env python3
"""Generates the destination maps and the cruise ship (data/destinations/*.json, data/cruise_ship.json).
Run:  python tools/vacation_gen.py     (from the repo root; output is committed, the game never runs this)
Templates use the lot template format (LotLoader) in a 32 x 22 zone; the ship is a multi-floor `levels` template.
Coordinates: tiles; walls on vertex lines (rect tiles x0..x1, y0..y1 inclusive -> vertices x0..x1+1, y0..y1+1).
Object rot: 0 = front faces south (+y), 1 west, 2 north, 3 east. Doors / windows sit on the edge named by rot (0 N, 1 E, 2 S, 3 W)."""
import json
import os

W, H = 32, 22
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class T:
    def __init__(self):
        self.floors = []
        self.walls = []
        self.objects = []
        self.levels = {}

    def _lv(self, level):
        if level == 0:
            return self.floors, self.walls
        d = self.levels.setdefault(str(level), {"floors": [], "walls": []})
        return d["floors"], d["walls"]

    def floor(self, x0, y0, x1, y1, kind, level=0):
        self._lv(level)[0].append({"rect": [x0, y0, x1, y1], "type": kind})

    def wall(self, a, b, level=0, kind="wall"):
        self._lv(level)[1].append({"a": list(a), "b": list(b), "type": kind})

    def room(self, x0, y0, x1, y1, level=0, kind="wall"):
        self.wall((x0, y0), (x1 + 1, y0), level, kind)
        self.wall((x0, y1 + 1), (x1 + 1, y1 + 1), level, kind)
        self.wall((x0, y0), (x0, y1 + 1), level, kind)
        self.wall((x1 + 1, y0), (x1 + 1, y1 + 1), level, kind)

    def obj(self, d, x, y, rot=0, level=0):
        o = {"def": d, "tile": [x, y], "rot": rot}
        if level:
            o["level"] = level
        self.objects.append(o)

    def door(self, x, y, rot, level=0):
        self.obj("door", x, y, rot, level)

    def window(self, x, y, rot, level=0):
        self.obj("window", x, y, rot, level)

    def base(self, label, desc, kind="venue"):
        return {"label": label, "description": desc, "kind": kind, "floors": self.floors, "walls": self.walls, "objects": self.objects}


def put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as fh:
        json.dump(data, fh, indent=1)
        fh.write("\n")


# ---------------------------------------------------------------- destinations
def beach():
    t = T()
    t.floor(0, 0, 31, 2, "water")
    t.floor(0, 3, 31, 12, "sand")
    t.floor(0, 13, 31, 21, "lawn")
    t.floor(14, 20, 16, 21, "concrete")
    t.floor(5, 14, 26, 19, "carpet")
    t.floor(5, 14, 10, 19, "tile")
    t.room(5, 14, 26, 19)
    t.wall((5, 17), (11, 17))                    # two guest rooms west of the lobby
    t.wall((11, 14), (11, 20))
    t.door(15, 19, 2)
    t.door(10, 15, 1)
    t.door(10, 18, 1)
    for x in (8, 13, 20, 24):
        t.window(x, 14, 0)
    t.window(26, 16, 1)
    # guest rooms
    t.obj("bed", 5, 14)
    t.obj("wardrobe", 9, 14)
    t.obj("toilet", 10, 14)
    t.obj("bed", 5, 18)
    t.obj("wardrobe", 9, 17)
    t.obj("sink", 10, 17)
    t.obj("shower", 9, 19, 2)
    t.obj("toilet", 10, 19, 2)
    # lobby
    t.obj("sofa", 13, 14)
    t.obj("tv", 16, 14)
    t.obj("computer", 18, 14)
    t.obj("plant", 20, 14)
    t.obj("travel_desk", 22, 14)
    t.obj("table", 14, 17)
    t.obj("vending_machine", 24, 14)
    t.obj("plant", 26, 19, 2)
    t.obj("lamp", 12, 19, 2)
    # beach
    for i, x in enumerate((2, 5, 8, 11)):
        t.obj("sunbed", x, 5)
    for x in (3, 9):
        t.obj("beach_umbrella", x, 4)
    t.obj("swimming_pool", 14, 7)
    t.obj("sunbed", 14, 10)
    t.obj("sunbed", 17, 10)
    t.obj("surf_rack", 21, 4)
    t.obj("surf_rack", 23, 4)
    t.obj("bar_counter", 25, 8)
    t.obj("table", 26, 6)
    t.obj("souvenir_stand", 28, 10)
    t.obj("sunbed", 29, 5)
    t.obj("hot_tub", 2, 9)
    t.obj("plant", 1, 13)
    t.obj("plant", 30, 13)
    d = t.base("Sunny Cove Resort", "A beach resort: sun, surf, a pool and a beach bar.")
    d["spawn"] = [[14, 20], [15, 20], [16, 20]]
    d["entry"] = [15, 21]
    return d


def mountain():
    t = T()
    t.floor(0, 0, 31, 21, "grass")
    t.floor(20, 0, 31, 6, "water")
    t.floor(19, 7, 31, 8, "sand")
    t.floor(14, 15, 16, 21, "dirt")
    t.floor(4, 5, 17, 12, "wood")
    t.room(4, 5, 17, 12)
    t.door(10, 12, 2)
    t.window(6, 12, 2)
    t.window(14, 12, 2)
    t.window(4, 8, 3)
    t.window(17, 8, 1)
    t.obj("fridge", 5, 5)
    t.obj("stove", 6, 5)
    t.obj("counter", 7, 5)
    t.obj("sink", 8, 5)
    t.obj("fireplace", 10, 5)
    t.obj("tv", 13, 5)
    t.obj("bed", 15, 5)
    t.obj("wardrobe", 15, 8)
    t.obj("sofa", 6, 9)
    t.obj("table", 10, 9)
    t.obj("toilet", 5, 11, 2)
    t.obj("shower", 16, 11, 2)
    t.obj("lamp", 12, 11, 2)
    t.obj("campfire", 22, 13)
    t.obj("log_bench", 20, 15)
    t.obj("log_bench", 24, 15)
    t.obj("fishing_spot", 22, 8)
    t.obj("fishing_spot", 26, 8)
    t.obj("hiking_trail", 10, 15)
    t.obj("hiking_trail", 5, 16)
    t.obj("telescope", 12, 16)
    t.obj("ski_rack", 28, 13)
    t.obj("grill", 20, 12)
    t.obj("hot_tub", 18, 3)
    t.obj("souvenir_stand", 28, 17)
    t.obj("plant", 3, 3)
    t.obj("plant", 12, 3)
    d = t.base("Pinecrest Cabin", "A cabin by a lake in the mountains: hiking, fishing, a campfire and, in winter, skiing.")
    d["spawn"] = [[14, 20], [15, 20], [16, 20]]
    d["entry"] = [15, 21]
    return d


def city():
    t = T()
    t.floor(0, 0, 31, 21, "concrete")
    t.floor(0, 9, 31, 12, "stone")
    t.floor(14, 20, 16, 21, "stone")
    # four buildings along the north side
    spec = [(1, 8, "museum", "carpet"), (9, 16, "restaurant", "wood"), (17, 23, "hotel", "carpet"), (24, 30, "club", "wood")]
    for x0, x1, name, fl in spec:
        t.floor(x0, 2, x1, 7, fl)
        t.room(x0, 2, x1, 7)
        t.door((x0 + x1) // 2, 7, 2)
        t.window(x0 + 1, 2, 0)
        t.window(x1 - 1, 2, 0)
    # museum
    t.obj("exhibit", 2, 3)
    t.obj("exhibit", 4, 3)
    t.obj("exhibit", 6, 3)
    t.obj("bookshelf", 7, 3)
    # restaurant
    t.obj("table", 10, 3)
    t.obj("table", 13, 3)
    t.obj("table", 10, 5)
    t.obj("table", 13, 5)
    t.obj("bar_counter", 15, 3)
    t.obj("fridge", 9, 3)
    # hotel
    t.obj("bed", 18, 3)
    t.obj("wardrobe", 22, 3)
    t.obj("toilet", 22, 5)
    t.obj("sink", 22, 6, 2)
    t.obj("shower", 18, 6, 2)
    t.obj("computer", 20, 6, 2)
    # club
    t.obj("stereo", 25, 3)
    t.obj("bar_counter", 27, 3)
    t.obj("bar_stool", 25, 6)
    t.obj("pool_table", 28, 5)
    # shops (bottom left) and plaza
    t.floor(1, 14, 12, 19, "tile")
    t.room(1, 14, 12, 19)
    t.door(6, 14, 0)
    t.obj("shop_stall", 2, 15)
    t.obj("shop_stall", 4, 15)
    t.obj("shop_stall", 8, 15)
    t.obj("souvenir_stand", 10, 15)
    t.obj("vending_machine", 11, 18, 2)
    t.floor(14, 14, 17, 17, "water")                 # fountain
    t.obj("sofa", 18, 14)
    t.obj("sofa", 20, 17)
    t.obj("plant", 13, 13)
    t.obj("plant", 18, 12)
    t.obj("travel_desk", 25, 15)
    t.obj("shop_stall", 27, 17)
    t.obj("souvenir_stand", 29, 15)
    d = t.base("Harbour City", "A big city: museum, restaurants, shopping, nightlife - and pickpockets.")
    d["spawn"] = [[14, 20], [15, 20], [16, 20]]
    d["entry"] = [15, 21]
    return d


def camping():
    t = T()
    t.floor(0, 0, 31, 21, "grass")
    t.floor(0, 0, 8, 5, "water")
    t.floor(14, 15, 16, 21, "dirt")
    for i, x in enumerate((4, 8, 12)):
        t.obj("tent", x, 8)
    t.obj("campfire", 18, 10)
    t.obj("log_bench", 16, 12)
    t.obj("log_bench", 20, 12)
    t.obj("cooler", 24, 9)
    t.obj("grill", 24, 12)
    t.obj("fishing_spot", 2, 6)
    t.obj("hiking_trail", 28, 5)
    t.obj("telescope", 26, 15)
    t.obj("plant", 1, 12)
    t.obj("plant", 30, 3)
    t.obj("plant", 20, 3)
    t.floor(27, 17, 29, 19, "tile")                  # wash house
    t.room(27, 17, 29, 19)
    t.door(28, 19, 2)
    t.obj("toilet", 27, 17)
    t.obj("sink", 29, 17)
    t.obj("shower", 28, 17)
    d = t.base("Fernhollow Campsite", "A cheap camping trip: tents, a campfire, stories, bugs and rain.")
    d["spawn"] = [[14, 20], [15, 20], [16, 20]]
    d["entry"] = [15, 21]
    return d


# ---------------------------------------------------------------- the ship
HX0, HX1, HY0, HY1 = 4, 27, 4, 17                     # hull interior (tiles)


def cabin(t, level, x0, x1, north, kind, cabins, cid):
    """6 (suite 8) wide, 6 tall room, door on the corridor side; bed in the far corner, bathroom fittings along the hull wall."""
    if north:
        y0, y1 = HY0, 9
        door_y, door_rot, wy, rot = 9, 2, y0, 0
        bed_y = y0
    else:
        y0, y1 = 12, HY1
        door_y, door_rot, wy, rot = 12, 0, y1, 2
        bed_y = y1 - 1
    xm = (x0 + x1) // 2
    t.door(xm, door_y, door_rot, level)
    t.obj("bed", x0, bed_y, 0, level)
    t.obj("wardrobe", x1, wy, rot, level)
    t.obj("toilet", x1 - 1, wy, rot, level)
    t.obj("sink", x1 - 2, wy, rot, level)
    t.obj("lamp", x0 + 3, (y0 + 2) if north else (y1 - 2), 0 if north else 2, level)
    cabins.append({"id": cid, "class": kind, "level": level, "tile": [x0 + 2, (y0 + 2) if north else (y1 - 2)]})
    if kind != "inside":
        t.window(xm - 1, HY0 if north else HY1, 0 if north else 2, level)
    if kind == "suite":
        t.obj("shower", x1 - 3, wy, rot, level)
        t.obj("sofa", x0 + 3, (y0 + 4) if north else (y1 - 4), 0, level)
        t.obj("tv", x1, (y0 + 4) if north else (y1 - 4), 0, level)
        t.obj("armchair", x0 + 6, (y0 + 4) if north else (y1 - 4), 0, level)


def deck_shell(t, level, floor_kind, north_rooms, south_rooms, open_south=False):
    t.floor(HX0, HY0, HX1, HY1, floor_kind, level)
    t.room(HX0, HY0, HX1, HY1, level)
    t.wall((HX0, 10), (HX1 + 1, 10), level)
    if not open_south:
        t.wall((HX0, 12), (HX1 + 1, 12), level)
    for (a, b) in north_rooms:
        if b < HX1:
            t.wall((b + 1, HY0), (b + 1, 10), level)
    if not open_south:
        for (a, b) in south_rooms:
            if b < HX1:
                t.wall((b + 1, 12), (b + 1, HY1 + 1), level)


def ship():
    t = T()
    cabins = []
    posts = []
    t.floor(0, 0, 31, 3, "water")
    t.floor(0, 4, 3, 18, "water")
    t.floor(28, 4, 31, 18, "water")
    t.floor(4, 18, 13, 18, "water")
    t.floor(17, 18, 27, 18, "water")
    t.floor(14, 18, 16, 18, "wood")
    t.floor(0, 19, 31, 21, "concrete")
    rooms_n = {0: [(4, 9), (10, 21), (22, 27)], 1: [(4, 9), (10, 21), (22, 27)], 2: [(4, 9), (10, 21), (22, 27)],
               3: [(4, 15), (16, 27)], -1: [(4, 9), (10, 15), (16, 21), (22, 27)]}
    rooms_s = {0: [(4, 9), (10, 21), (22, 27)], 1: [(4, 9), (10, 21), (22, 27)], 2: [],
               3: [(4, 9), (10, 15), (16, 21), (22, 27)], -1: [(4, 11), (12, 19), (20, 27)]}
    floors = {-1: "concrete", 0: "wood", 1: "carpet", 2: "tile", 3: "carpet"}
    for lv in (0, 1, 2, 3, -1):
        deck_shell(t, lv, floors[lv], rooms_n[lv], rooms_s[lv], open_south=(lv == 2))
    t.obj("elevator", 4, 10, 0, 0)                     # lifts start on the ground deck and serve it and everything above
    t.obj("elevator", 27, 10, 0, 0)
    t.obj("stairs_down", 7, 11, 0, 0)                  # stairs to the crew deck below (lifts cannot pass the ground deck downwards)
    t.obj("stairs_down", 20, 11, 0, 0)
    t.door(15, 17, 2)                                 # gangway door (south hull wall, ground deck)

    def n_door(level, a, b):
        t.door((a + b) // 2, 9, 2, level)

    def s_door(level, a, b):
        t.door((a + b) // 2, 12, 0, level)

    # ---- level 0: reception, dining hall, buffet / shops, atrium, medical bay
    for (a, b) in rooms_n[0]:
        n_door(0, a, b)
    for (a, b) in rooms_s[0]:
        s_door(0, a, b)
    t.obj("souvenir_stand", 5, 4); t.obj("computer", 7, 4); t.obj("vending_machine", 9, 4); t.obj("plant", 4, 8, 2)
    for x in (11, 14, 17, 20):
        t.obj("table", x, 6); t.obj("table", x, 8)
    t.obj("bar_counter", 11, 4); t.obj("fridge", 20, 4)
    t.obj("buffet_table", 23, 4); t.obj("buffet_table", 25, 4); t.obj("table", 23, 7); t.obj("table", 25, 7)
    t.obj("shop_stall", 5, 13); t.obj("shop_stall", 7, 13); t.obj("souvenir_stand", 9, 13)
    t.obj("sofa", 11, 13); t.obj("sofa", 18, 13); t.obj("piano", 14, 13); t.obj("tv", 20, 13)
    t.obj("bar_counter", 12, 16); t.obj("plant", 10, 16, 2); t.obj("plant", 21, 16, 2)
    t.obj("bed", 23, 13); t.obj("bed", 23, 16); t.obj("sink", 27, 13); t.obj("medical_cabinet", 26, 13); t.obj("lamp", 27, 16, 2)
    posts += [{"role": "waiter", "tile": [13, 7], "level": 0}, {"role": "waiter", "tile": [19, 7], "level": 0},
              {"role": "bartender", "tile": [14, 16], "level": 0}, {"role": "medical", "tile": [25, 15], "level": 0},
              {"role": "security", "tile": [16, 14], "level": 0}]
    # ---- level 1: kids' club, theatre, casino / nightclub, bar, library
    for (a, b) in rooms_n[1]:
        n_door(1, a, b)
    for (a, b) in rooms_s[1]:
        s_door(1, a, b)
    t.obj("play_mat", 5, 5, 0, 1); t.obj("play_mat", 7, 5, 0, 1); t.obj("bookshelf", 4, 4, 0, 1); t.obj("table", 7, 8, 0, 1)
    t.obj("stage", 12, 4, 0, 1); t.obj("stage", 14, 4, 0, 1)
    for x in (11, 13, 15, 17, 19):
        t.obj("theatre_seat", x, 7, 0, 1)
    for x in (12, 16, 20):
        t.obj("theatre_seat", x, 8, 0, 1)
    for x in (23, 25, 27):
        t.obj("slot_machine", x, 4, 0, 1)
    t.obj("table", 23, 7, 0, 1)
    t.obj("stereo", 5, 13, 0, 1); t.obj("stereo", 8, 13, 0, 1); t.obj("bar_counter", 6, 16, 0, 1)
    t.obj("bar_counter", 12, 13, 0, 1); t.obj("bar_counter", 15, 13, 0, 1); t.obj("pool_table", 17, 16, 0, 1); t.obj("sofa", 11, 16, 0, 1)
    t.obj("bookshelf", 23, 13, 0, 1); t.obj("bookshelf", 25, 13, 0, 1); t.obj("armchair", 24, 16, 2, 1); t.obj("armchair", 26, 16, 2, 1)
    posts += [{"role": "entertainer", "tile": [13, 6], "level": 1}, {"role": "bartender", "tile": [13, 15], "level": 1},
              {"role": "waiter", "tile": [14, 9], "level": 1}]
    # ---- level 2: bridge, spa, gym / open sun deck with the pool
    for (a, b) in rooms_n[2]:
        n_door(2, a, b)
    t.obj("captain_wheel", 6, 4, 0, 2); t.obj("desk", 8, 4, 0, 2); t.obj("telescope", 4, 4, 0, 2); t.obj("computer", 9, 4, 0, 2)
    t.obj("hot_tub", 11, 4, 0, 2); t.obj("hot_tub", 14, 4, 0, 2); t.obj("spa_bed", 18, 4, 0, 2); t.obj("spa_bed", 20, 4, 0, 2); t.obj("plant", 10, 8, 2, 2)
    t.obj("treadmill", 23, 4, 0, 2); t.obj("treadmill", 25, 4, 0, 2); t.obj("dumbbell_rack", 27, 4, 0, 2); t.obj("dumbbell_rack", 23, 8, 0, 2)
    t.obj("swimming_pool", 8, 13, 0, 2)
    for x in (5, 8, 11, 14):
        t.obj("deck_chair", x, 17, 2, 2)
    t.obj("hot_tub", 18, 13, 0, 2); t.obj("bar_counter", 23, 16, 0, 2); t.obj("table", 21, 13, 0, 2); t.obj("plant", 27, 13, 0, 2)
    posts += [{"role": "captain", "tile": [7, 6], "level": 2}, {"role": "lifeguard", "tile": [13, 14], "level": 2},
              {"role": "cleaner", "tile": [20, 16], "level": 2}]
    # ---- level 3: suites and ocean-view cabins
    ci = 0
    for (a, b) in rooms_n[3]:
        ci += 1
        cabin(t, 3, a, b, True, "suite", cabins, "c3n%d" % ci)
    for (a, b) in rooms_s[3]:
        ci += 1
        cabin(t, 3, a, b, False, "ocean", cabins, "c3s%d" % ci)
    # ---- level -1: inside cabins and the crew decks
    ci = 0
    for (a, b) in rooms_n[-1]:
        ci += 1
        cabin(t, -1, a, b, True, "inside", cabins, "c1n%d" % ci)
    for (a, b) in rooms_s[-1]:
        s_door(-1, a, b)
    t.obj("stove", 5, 13, 0, -1); t.obj("counter", 6, 13, 0, -1); t.obj("fridge", 7, 13, 0, -1); t.obj("table", 6, 16, 0, -1); t.obj("table", 9, 16, 0, -1)
    t.obj("bunk_bed", 13, 13, 0, -1); t.obj("bunk_bed", 15, 13, 0, -1); t.obj("bunk_bed", 17, 13, 0, -1); t.obj("wardrobe", 13, 17, 2, -1)
    t.obj("terminal", 21, 13, 0, -1); t.obj("workbench", 23, 13, 0, -1); t.obj("desk", 26, 13, 0, -1); t.obj("single_bed", 26, 16, 0, -1)
    t.obj("fire_extinguisher", 20, 16, 2, -1)
    posts += [{"role": "waiter", "tile": [8, 14], "level": -1}, {"role": "security", "tile": [24, 15], "level": -1}]
    for lv in (0, 1, 2, 3):
        t.obj("fire_extinguisher", 5, 11, 2, lv)
        t.obj("smoke_alarm", 14, 11, 0, lv)
    for lv in (0, 1, 2):
        for x in (6, 13, 19, 24):
            t.window(x, HY0, 0, lv)
    for lv in (0, 1):
        for x in (6, 24):
            t.window(x, HY1, 2, lv)
    d = t.base("Starlight Voyager", "A cruise ship: five decks, dining, shows, a pool deck and a bridge.")
    d["spawn"] = [[14, 20], [15, 20], [16, 20]]
    d["entry"] = [15, 20]
    d["roof"] = "flat"
    d["levels"] = t.levels
    d["cabins"] = cabins
    d["posts"] = posts
    d["lobby"] = [15, 14, 0]
    return d


def main():
    put(os.path.join(ROOT, "data", "destinations", "beach.json"), {"id": "beach", "template": beach()})
    put(os.path.join(ROOT, "data", "destinations", "mountain.json"), {"id": "mountain", "template": mountain()})
    put(os.path.join(ROOT, "data", "destinations", "city.json"), {"id": "city", "template": city()})
    put(os.path.join(ROOT, "data", "destinations", "camping.json"), {"id": "camping", "template": camping()})
    put(os.path.join(ROOT, "data", "destinations", "ship.json"), {"id": "ship", "template": ship()})


if __name__ == "__main__":
    main()
