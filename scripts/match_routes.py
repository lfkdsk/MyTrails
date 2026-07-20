#!/usr/bin/env python3
"""把一个州的 OSM 徒步路径（geojsonseq）离线匹配到该州全部步道，写入 trail_routes 表。

匹配算法与 App 内 TrailPathLoader 一致：OSM 路径名的有效词元是步道名词元子集即命中；
半径按步道长度自适应（2.5–12km）。结果经 Douglas-Peucker 简化（≈13m）并限制 800 点。
"""
import json
import math
import re
import sqlite3
import sys
import time

STOP = {"trail", "trails", "via", "and", "the", "to", "of", "a",
        "loop", "road", "rd", "route", "path", "way", "jmt"}
CELL = 0.05  # 网格索引单元（约 5km）


def toks(name):
    return set(re.findall(r"[a-z0-9]+", name.lower())) - STOP


def simplify(pts, eps=0.00012):
    if len(pts) <= 2:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        s, e = stack.pop()
        if e <= s + 1:
            continue
        ax, ay = pts[s]
        bx, by = pts[e]
        dx, dy = bx - ax, by - ay
        den = math.hypot(dx, dy)
        best, bi = -1.0, None
        for i in range(s + 1, e):
            px, py = pts[i]
            d = abs(dy * (px - ax) - dx * (py - ay)) / den if den > 0 else math.hypot(px - ax, py - ay)
            if d > best:
                best, bi = d, i
        if best > eps:
            keep[bi] = True
            stack.append((s, bi))
            stack.append((bi, e))
    return [p for p, k in zip(pts, keep) if k]


def main():
    geojsonl, state, dbpath = sys.argv[1], sys.argv[2], sys.argv[3]

    ways = []  # (tokens, coords[(lat,lng)], bbox)
    with open(geojsonl, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip().lstrip("\x1e")
            if not line:
                continue
            try:
                feat = json.loads(line)
            except json.JSONDecodeError:
                continue
            props = feat.get("properties") or {}
            t = toks(props.get("name") or "")
            if not t:
                continue
            geom = feat.get("geometry") or {}
            if geom.get("type") != "LineString":
                continue
            coords = [(c[1], c[0]) for c in geom["coordinates"]]
            if len(coords) < 2:
                continue
            lats = [c[0] for c in coords]
            lngs = [c[1] for c in coords]
            ways.append((t, coords, (min(lats), min(lngs), max(lats), max(lngs))))

    grid = {}
    for i, (_, _, bb) in enumerate(ways):
        for gy in range(int(bb[0] // CELL), int(bb[2] // CELL) + 1):
            for gx in range(int(bb[1] // CELL), int(bb[3] // CELL) + 1):
                grid.setdefault((gy, gx), []).append(i)

    con = sqlite3.connect(dbpath)
    con.execute("""CREATE TABLE IF NOT EXISTS trail_routes(
        trail_id TEXT PRIMARY KEY, coords TEXT NOT NULL, updated_at REAL NOT NULL)""")
    trails = con.execute(
        "SELECT id, name, distance, lat, lng FROM trails WHERE state = ?", (state,)).fetchall()

    now = time.time()
    rows = []
    for tid, name, dist, lat, lng in trails:
        tt = toks(name)
        if not tt:
            continue
        r = min(max(dist * 1609.34 * 0.6, 2500), 12000)
        dlat = r / 111320
        dlng = r / (111320 * max(0.2, math.cos(math.radians(lat))))
        qlat0, qlat1 = lat - dlat, lat + dlat
        qlng0, qlng1 = lng - dlng, lng + dlng

        cand = set()
        for gy in range(int(qlat0 // CELL), int(qlat1 // CELL) + 1):
            for gx in range(int(qlng0 // CELL), int(qlng1 // CELL) + 1):
                cand.update(grid.get((gy, gx), ()))

        segs = []
        for i in cand:
            wt, coords, bb = ways[i]
            if not wt <= tt:
                continue
            if bb[2] < qlat0 or bb[0] > qlat1 or bb[3] < qlng0 or bb[1] > qlng1:
                continue
            segs.append(coords)
        if not segs:
            continue

        # 全精度：保留 OSM 原始几何，不做简化；仅设一个防病态的宽松上限
        segs.sort(key=lambda s: (s[0][0] - lat) ** 2 + (s[0][1] - lng) ** 2)
        out, total = [], 0
        for seg in segs:
            if total + len(seg) > 20000:
                break
            out.append(seg)
            total += len(seg)
        payload = json.dumps(
            [[[round(a, 6), round(b, 6)] for a, b in seg] for seg in out],
            separators=(",", ":"))
        rows.append((tid, payload, now))

    con.executemany(
        "INSERT OR REPLACE INTO trail_routes(trail_id, coords, updated_at) VALUES(?,?,?)", rows)
    con.commit()
    con.close()
    print(f"{state}: matched {len(rows)}/{len(trails)} (osm named ways: {len(ways)})", flush=True)


if __name__ == "__main__":
    main()
