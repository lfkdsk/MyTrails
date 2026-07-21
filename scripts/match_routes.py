#!/usr/bin/env python3
"""把一个州的 OSM 徒步路径（geojsonseq，含无名 way）匹配到该州全部步道，写入 trail_routes 表。

v3 路网级组装：
1. 同名 way 匹配出"骨架"（词元子集匹配，同 App 内逻辑）
2. 骨架按连通分量聚类，保留靠近步道口 / 占比大的分量，剔除远处同名孤岛
3. 在真实路网图（含无名 way，按 OSM 共享节点建邻接）上用 Dijkstra 把
   步道口与各骨架分量、分量与分量之间用实际路径连起来（无名段预算 2.5km）
4. 组装结果对照步道已知长度截流，缝合成尽量少的连续折线
"""
import heapq
import json
import math
import re
import sqlite3
import sys
import time
from array import array

STOP = {"trail", "trails", "via", "and", "the", "to", "of", "a",
        "loop", "road", "rd", "route", "path", "way", "jmt"}
CELL = 0.05          # 网格索引单元（约 5km）
GAP_M = 120          # 缝合容差
ISLAND_NEAR_M = 1000  # 距步道口 1km 内的骨架分量保留
MAJOR_SHARE = 0.25   # 占骨架总长 25% 以上的分量保留
ANCHOR_M = 300       # 步道口吸附到路网的最大距离
CONNECT_BUDGET_M = 2500   # 单次连接允许穿过的无名路段总长
LENGTH_STOP_FACTOR = 1.8  # 组装长度达到步道标称长度的 1.8 倍后停止吸收分量


def toks(name):
    return set(re.findall(r"[a-z0-9]+", name.lower())) - STOP


def dist_m(a, b):
    dlat = (a[0] - b[0]) * 111320
    dlng = (a[1] - b[1]) * 111320 * math.cos(math.radians(a[0]))
    return math.hypot(dlat, dlng)


class Ways:
    """州级路网：紧凑存储 + 网格索引 + 共享节点邻接。"""

    def __init__(self):
        self.tokens = []     # frozenset（无名/无效名为空集）
        self.coords = []     # array('d') 扁平 lat,lng
        self.bbox = []
        self.grid = {}
        self.adj = {}        # way idx -> set(way idx)，OSM 共享节点推导
        self._len_cache = {}

    def load(self, path):
        node_owner = {}
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip().lstrip("\x1e")
                if not line:
                    continue
                try:
                    feat = json.loads(line)
                except json.JSONDecodeError:
                    continue
                geom = feat.get("geometry") or {}
                if geom.get("type") != "LineString":
                    continue
                raw = geom["coordinates"]
                if len(raw) < 2:
                    continue
                idx = len(self.coords)
                flat = array("d")
                lats, lngs = [], []
                for c in raw:
                    flat.append(c[1])
                    flat.append(c[0])
                    lats.append(c[1])
                    lngs.append(c[0])
                props = feat.get("properties") or {}
                self.tokens.append(frozenset(toks(props.get("name") or "")))
                self.coords.append(flat)
                self.bbox.append((min(lats), min(lngs), max(lats), max(lngs)))
                bb = self.bbox[idx]
                for gy in range(int(bb[0] // CELL), int(bb[2] // CELL) + 1):
                    for gx in range(int(bb[1] // CELL), int(bb[3] // CELL) + 1):
                        self.grid.setdefault((gy, gx), []).append(idx)
                # 共享节点 → 邻接（OSM 相连的 way 复用同一节点坐标）
                for k in range(0, len(flat), 2):
                    key = (round(flat[k] * 1e6), round(flat[k + 1] * 1e6))
                    other = node_owner.get(key)
                    if other is None:
                        node_owner[key] = idx
                    elif other != idx:
                        self.adj.setdefault(idx, set()).add(other)
                        self.adj.setdefault(other, set()).add(idx)

    def pts(self, i):
        a = self.coords[i]
        return [(a[k], a[k + 1]) for k in range(0, len(a), 2)]

    def length(self, i):
        if i not in self._len_cache:
            p = self.pts(i)
            self._len_cache[i] = sum(dist_m(p[k], p[k + 1]) for k in range(len(p) - 1))
        return self._len_cache[i]

    def candidates(self, lat0, lat1, lng0, lng1):
        out = set()
        for gy in range(int(lat0 // CELL), int(lat1 // CELL) + 1):
            for gx in range(int(lng0 // CELL), int(lng1 // CELL) + 1):
                out.update(self.grid.get((gy, gx), ()))
        return out


def union_find_components(ways, idxs):
    idxs = list(idxs)
    parent = {i: i for i in idxs}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    ends = {i: (ways.pts(i)[0], ways.pts(i)[-1]) for i in idxs}
    for a in range(len(idxs)):
        for b in range(a + 1, len(idxs)):
            i, j = idxs[a], idxs[b]
            if min(dist_m(pa, pb) for pa in ends[i] for pb in ends[j]) <= GAP_M \
                    or find(i) == find(j) \
                    or j in ways.adj.get(i, ()):
                parent[find(i)] = find(j)
    comps = {}
    for i in idxs:
        comps.setdefault(find(i), set()).add(i)
    return list(comps.values())


def dijkstra_ways(ways, allowed, matched, sources, targets):
    """way 粒度最短路。代价 = 沿途 way 长度，骨架段打 0.25 折。
    返回 (无名段总长, 路径 way 列表)；不可达返回 (inf, [])."""
    dist = {}
    prev = {}
    heap = []
    for s in sources:
        dist[s] = 0.0
        heapq.heappush(heap, (0.0, s))
    seen = set()
    while heap:
        d, u = heapq.heappop(heap)
        if u in seen:
            continue
        seen.add(u)
        if u in targets:
            path = [u]
            while path[-1] in prev:
                path.append(prev[path[-1]])
            raw = sum(ways.length(w) for w in path if w not in matched and w not in sources)
            return raw, path
        for v in ways.adj.get(u, ()):
            if v not in allowed or v in seen:
                continue
            step = ways.length(v) * (0.25 if v in matched else 1.0)
            nd = d + step
            if nd < dist.get(v, 1e18):
                dist[v] = nd
                prev[v] = u
                heapq.heappush(heap, (nd, v))
    return 1e18, []


def merge_chains(seg_list):
    """把首尾相接（≤GAP_M）的折线贪心缝合成长线。"""
    remaining = [list(s) for s in seg_list]
    merged = []
    while remaining:
        cur = remaining.pop(0)
        extended = True
        while extended:
            extended = False
            for k, seg in enumerate(remaining):
                pairs = [
                    (dist_m(cur[-1], seg[0]), "th"),
                    (dist_m(cur[-1], seg[-1]), "tt"),
                    (dist_m(cur[0], seg[0]), "hh"),
                    (dist_m(cur[0], seg[-1]), "ht"),
                ]
                gap, mode = min(pairs)
                if gap > GAP_M:
                    continue
                if mode == "th":
                    cur = cur + seg
                elif mode == "tt":
                    cur = cur + seg[::-1]
                elif mode == "hh":
                    cur = cur[::-1] + seg
                else:
                    cur = seg + cur
                remaining.pop(k)
                extended = True
                break
        merged.append(cur)
    return merged


def assemble(ways, trail, cand):
    """返回该步道的折线列表（组装失败/无骨架返回 []）。"""
    tid, name, dist_mi, lat, lng = trail
    tt = toks(name)
    if not tt:
        return []
    matched = {i for i in cand if ways.tokens[i] and ways.tokens[i] <= tt}
    if not matched:
        return []

    comps = union_find_components(ways, matched)
    near = {}
    length = {}
    for ci, comp in enumerate(comps):
        near[ci] = min(dist_m(p, (lat, lng)) for i in comp for p in (ways.pts(i)[0], ways.pts(i)[-1]))
        length[ci] = sum(ways.length(i) for i in comp)
    total = sum(length.values()) or 1.0
    kept = [ci for ci in range(len(comps))
            if near[ci] <= ISLAND_NEAR_M or length[ci] >= MAJOR_SHARE * total]
    if not kept:
        kept = [min(near, key=near.get)]
    kept.sort(key=lambda ci: near[ci])

    # 步道口吸附到路网
    anchor = None
    best = ANCHOR_M
    for i in cand:
        bb = ways.bbox[i]
        if bb[0] - 0.005 > lat or bb[2] + 0.005 < lat \
                or bb[1] - 0.005 > lng or bb[3] + 0.005 < lng:
            continue
        for p in ways.pts(i)[::3]:
            d = dist_m(p, (lat, lng))
            if d < best:
                best = d
                anchor = i

    expected = max(dist_mi * 1609.34, 1000.0)
    assembled = set(comps[kept[0]])
    if anchor is not None and anchor not in assembled:
        raw, path = dijkstra_ways(ways, cand, matched, {anchor}, assembled)
        if raw <= CONNECT_BUDGET_M:
            assembled.update(path)

    def assembled_len():
        return sum(ways.length(i) for i in assembled)

    for ci in kept[1:]:
        if assembled_len() >= LENGTH_STOP_FACTOR * expected:
            break
        comp = comps[ci]
        if comp & assembled:
            assembled.update(comp)
            continue
        raw, path = dijkstra_ways(ways, cand, matched, assembled, comp)
        if raw <= CONNECT_BUDGET_M:
            assembled.update(path)
            assembled.update(comp)

    return merge_chains([ways.pts(i) for i in assembled])


def main():
    geojsonl, state, dbpath = sys.argv[1], sys.argv[2], sys.argv[3]

    ways = Ways()
    ways.load(geojsonl)

    con = sqlite3.connect(dbpath)
    con.execute("""CREATE TABLE IF NOT EXISTS trail_routes(
        trail_id TEXT PRIMARY KEY, coords TEXT NOT NULL, updated_at REAL NOT NULL)""")
    trails = con.execute(
        "SELECT id, name, distance, lat, lng FROM trails WHERE state = ?", (state,)).fetchall()

    now = time.time()
    rows = []
    for trail in trails:
        tid, name, dist_mi, lat, lng = trail
        r = min(max(dist_mi * 1609.34 * 0.6, 2500), 12000)
        dlat = r / 111320
        dlng = r / (111320 * max(0.2, math.cos(math.radians(lat))))
        cand = ways.candidates(lat - dlat, lat + dlat, lng - dlng, lng + dlng)
        segs = assemble(ways, trail, cand)
        if not segs:
            continue
        payload = json.dumps(
            [[[round(a, 6), round(b, 6)] for a, b in seg] for seg in segs],
            separators=(",", ":"))
        rows.append((tid, payload, now))

    con.executemany(
        "INSERT OR REPLACE INTO trail_routes(trail_id, coords, updated_at) VALUES(?,?,?)", rows)
    con.commit()
    con.close()
    print(f"{state}: matched {len(rows)}/{len(trails)} (osm ways: {len(ways.coords)})", flush=True)


if __name__ == "__main__":
    main()
