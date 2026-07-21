#!/usr/bin/env python3
"""用官方数据集（USFS 等，公有领域）按名字对齐增补步道路线。

对每条步道：在其周边收集官方 way，用与 App 一致的词元子集匹配挑出同名官方段，
按端点缝合成连续折线；若长度与标称吻合，则以官方几何覆盖 OSM 结果，
并将 confidence 置为最高档 'official'。
"""
import json
import math
import re
import sqlite3
import sys

STOP = {"trail", "trails", "via", "and", "the", "to", "of", "a",
        "loop", "road", "rd", "route", "path", "way", "jmt"}
CELL = 0.05
GAP_M = 200          # 官方数据分段较规整，容差可略大
MAX_RADIUS_DEG = 0.12


def toks(name):
    return set(re.findall(r"[a-z0-9]+", name.lower())) - STOP


def dist_m(a, b):
    dlat = (a[0] - b[0]) * 111320
    dlng = (a[1] - b[1]) * 111320 * math.cos(math.radians(a[0]))
    return math.hypot(dlat, dlng)


def seg_len(seg):
    return sum(dist_m(seg[i], seg[i + 1]) for i in range(len(seg) - 1))


def merge_chains(seg_list):
    remaining = [list(s) for s in seg_list]
    merged = []
    while remaining:
        cur = remaining.pop(0)
        extended = True
        while extended:
            extended = False
            for k, seg in enumerate(remaining):
                pairs = [(dist_m(cur[-1], seg[0]), "th"), (dist_m(cur[-1], seg[-1]), "tt"),
                         (dist_m(cur[0], seg[0]), "hh"), (dist_m(cur[0], seg[-1]), "ht")]
                gap, mode = min(pairs)
                if gap > GAP_M:
                    continue
                cur = {"th": cur + seg, "tt": cur + seg[::-1],
                       "hh": cur[::-1] + seg, "ht": seg + cur}[mode]
                remaining.pop(k)
                extended = True
                break
        merged.append(cur)
    return merged


def load_official(path):
    """返回 (ways, grid)。ways[i] = (tokens, coords[(lat,lng)], bbox)。"""
    ways = []
    grid = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ft = json.loads(line)
            except json.JSONDecodeError:
                continue
            p = ft.get("properties") or {}
            t = toks(p.get("trail_name") or "")
            if not t:
                continue
            g = ft.get("geometry") or {}
            parts = []
            if g.get("type") == "LineString":
                parts = [g["coordinates"]]
            elif g.get("type") == "MultiLineString":
                parts = g["coordinates"]
            for raw in parts:
                if len(raw) < 2:
                    continue
                coords = [(c[1], c[0]) for c in raw]
                lats = [c[0] for c in coords]
                lngs = [c[1] for c in coords]
                bb = (min(lats), min(lngs), max(lats), max(lngs))
                idx = len(ways)
                ways.append((t, coords, bb))
                for gy in range(int(bb[0] // CELL), int(bb[2] // CELL) + 1):
                    for gx in range(int(bb[1] // CELL), int(bb[3] // CELL) + 1):
                        grid.setdefault((gy, gx), []).append(idx)
    return ways, grid


def match_trail(ways, grid, name, dist_mi, rtype, lat, lng):
    tt = toks(name)
    if not tt:
        return None
    r = min(max(dist_mi * 1609.34 * 0.6, 3000), 15000)
    dlat = min(r / 111320, MAX_RADIUS_DEG)
    dlng = min(r / (111320 * max(0.2, math.cos(math.radians(lat)))), MAX_RADIUS_DEG * 1.3)
    cand = set()
    for gy in range(int((lat - dlat) // CELL), int((lat + dlat) // CELL) + 1):
        for gx in range(int((lng - dlng) // CELL), int((lng + dlng) // CELL) + 1):
            cand.update(grid.get((gy, gx), ()))

    segs = []
    for i in cand:
        wt, coords, bb = ways[i]
        if not (wt <= tt):
            continue
        # 必须在合理范围内（防同名异地）
        if bb[2] < lat - dlat or bb[0] > lat + dlat or bb[3] < lng - dlng or bb[1] > lng + dlng:
            continue
        segs.append(coords)
    if not segs:
        return None

    merged = merge_chains(segs)
    geom_m = sum(seg_len(s) for s in merged)
    nominal_m = dist_mi * 1609.34
    expected = nominal_m / 2 if "back" in (rtype or "").lower() else nominal_m
    ratio = geom_m / expected if expected > 0 else 0
    # 官方数据只在长度合理时采用（过短=只匹配到一截；过长=吞了别的）
    if not (0.55 <= ratio <= 1.7):
        return None
    return merged


def main():
    official_path, dbpath = sys.argv[1], sys.argv[2]
    ways, grid = load_official(official_path)
    print(f"官方 way 段: {len(ways)}", flush=True)

    con = sqlite3.connect(dbpath)
    con.execute("""CREATE TABLE IF NOT EXISTS trail_routes(
        trail_id TEXT PRIMARY KEY, coords TEXT NOT NULL, updated_at REAL NOT NULL,
        confidence TEXT NOT NULL DEFAULT 'medium')""")
    trails = con.execute("SELECT id, name, distance, route_type, lat, lng FROM trails").fetchall()

    import time
    now = time.time()
    upgraded = 0
    rows = []
    for tid, name, dist_mi, rtype, lat, lng in trails:
        merged = match_trail(ways, grid, name, dist_mi, rtype, lat, lng)
        if not merged:
            continue
        payload = json.dumps(
            [[[round(a, 6), round(b, 6)] for a, b in seg] for seg in merged],
            separators=(",", ":"))
        rows.append((tid, payload, now, "official"))
        upgraded += 1

    con.executemany(
        "INSERT OR REPLACE INTO trail_routes(trail_id, coords, updated_at, confidence) VALUES(?,?,?,?)",
        rows)
    con.commit()
    con.close()
    print(f"官方增补/覆盖: {upgraded} 条 -> confidence=official", flush=True)


if __name__ == "__main__":
    main()
