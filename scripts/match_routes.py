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


def _dist_m(a, b):
    dlat = (a[0] - b[0]) * 111320
    dlng = (a[1] - b[1]) * 111320 * math.cos(math.radians(a[0]))
    return math.hypot(dlat, dlng)


def _seg_len(seg):
    return sum(_dist_m(seg[i], seg[i + 1]) for i in range(len(seg) - 1))


GAP_M = 120        # 缝合/桥接容差
ISLAND_NEAR_M = 1000   # 距步道口 1km 内的组件保留
CHAIN_M = 500      # 与已保留组件相距 500m 内的组件保留
MAJOR_SHARE = 0.25  # 占总长 25% 以上的组件保留


def postprocess(segs, trailhead):
    """缝合破碎路段：合并相接的段、桥接小缺口、剔除远处同名孤岛。"""
    n = len(segs)
    if n <= 1:
        return segs

    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        parent[find(a)] = find(b)

    ends = [(s[0], s[-1]) for s in segs]
    for i in range(n):
        for j in range(i + 1, n):
            gap = min(_dist_m(pa, pb) for pa in ends[i] for pb in ends[j])
            if gap <= GAP_M:
                union(i, j)

    comps = {}
    for i in range(n):
        comps.setdefault(find(i), []).append(i)

    lengths = {r: sum(_seg_len(segs[i]) for i in members) for r, members in comps.items()}
    total_len = sum(lengths.values()) or 1.0
    near = {r: min(_dist_m(p, trailhead) for i in members for p in segs[i])
            for r, members in comps.items()}

    keep = {r for r in comps
            if near[r] <= ISLAND_NEAR_M or lengths[r] >= MAJOR_SHARE * total_len}
    if not keep:
        keep = {min(comps, key=lambda r: near[r])}
    changed = True
    while changed:
        changed = False
        for r in comps:
            if r in keep:
                continue
            gap = min(
                (min(_dist_m(pa, pb)
                     for i in comps[r] for pa in ends[i]
                     for j in comps[k] for pb in ends[j])
                 for k in keep), default=1e18)
            if gap <= CHAIN_M:
                keep.add(r)
                changed = True

    # 组件内贪心缝合：首尾相接（≤GAP_M）的段拼成长线，小缺口直接连过去
    merged = []
    for r in keep:
        remaining = [list(segs[i]) for i in comps[r]]
        while remaining:
            cur = remaining.pop(0)
            extended = True
            while extended:
                extended = False
                for k, seg in enumerate(remaining):
                    pairs = [
                        (_dist_m(cur[-1], seg[0]), "tail-head"),
                        (_dist_m(cur[-1], seg[-1]), "tail-tail"),
                        (_dist_m(cur[0], seg[0]), "head-head"),
                        (_dist_m(cur[0], seg[-1]), "head-tail"),
                    ]
                    gap, mode = min(pairs)
                    if gap > GAP_M:
                        continue
                    if mode == "tail-head":
                        cur = cur + seg
                    elif mode == "tail-tail":
                        cur = cur + seg[::-1]
                    elif mode == "head-head":
                        cur = cur[::-1] + seg
                    else:
                        cur = seg + cur
                    remaining.pop(k)
                    extended = True
                    break
            merged.append(cur)
    return merged


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

        # 缝合破碎路段并剔除远处孤岛
        segs = postprocess(segs, (lat, lng))
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
