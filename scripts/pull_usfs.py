#!/usr/bin/env python3
"""拉取 USFS National Forest System Trails 全国数据集（公有领域）为 geojsonl。

来源: USDA Forest Service FSGeodata / EDW（美国联邦政府作品，公有领域）。
只保留有名字、且对徒步开放的步道段。
"""
import json
import sys
import time
import urllib.parse
import urllib.request

BASE = ("https://apps.fs.usda.gov/arcx/rest/services/EDW/"
        "EDW_TrailNFSPublish_01/MapServer/0/query")
PAGE = 2000
OUT = sys.argv[1]


def fetch(offset):
    params = {
        "where": "trail_name IS NOT NULL",
        "outFields": "trail_name,trail_no,hiker_pedestrian_managed",
        "returnGeometry": "true",
        "outSR": "4326",
        "orderByFields": "objectid",
        "resultOffset": str(offset),
        "resultRecordCount": str(PAGE),
        "f": "geojson",
    }
    url = BASE + "?" + urllib.parse.urlencode(params)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                return json.load(r)
        except Exception as e:
            if attempt == 3:
                raise
            time.sleep(5 * (attempt + 1))
    return None


def hikeable(props):
    # hiker_pedestrian_managed 有值（如 "01/01-12/31"）= 对徒步开放
    return bool(props.get("hiker_pedestrian_managed"))


def main():
    offset = 0
    kept = 0
    with open(OUT, "w", encoding="utf-8") as f:
        while True:
            data = fetch(offset)
            feats = data.get("features", [])
            if not feats:
                break
            for ft in feats:
                p = ft.get("properties") or {}
                g = ft.get("geometry") or {}
                if not p.get("trail_name") or not hikeable(p):
                    continue
                if g.get("type") not in ("LineString", "MultiLineString"):
                    continue
                f.write(json.dumps(ft, separators=(",", ":")) + "\n")
                kept += 1
            print(f"offset {offset}: +{len(feats)} (kept total {kept})", flush=True)
            if len(feats) < PAGE:
                break
            offset += PAGE
            time.sleep(1)
    print(f"DONE kept {kept} hikeable named segments -> {OUT}", flush=True)


if __name__ == "__main__":
    main()
