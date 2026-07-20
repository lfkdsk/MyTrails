#!/usr/bin/env python3
"""从 AllTrails 全量 CSV 预构建与 App 同构的 SQLite 数据库（含 FTS5）。"""
import csv
import sqlite3
import sys

src, dst = sys.argv[1], sys.argv[2]

conn = sqlite3.connect(dst)
conn.executescript("""
PRAGMA journal_mode=DELETE;
CREATE TABLE IF NOT EXISTS trails(
  id TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  distance REAL NOT NULL DEFAULT 0,
  elevation_gain REAL NOT NULL DEFAULT 0,
  highest_point REAL NOT NULL DEFAULT 0,
  difficulty INTEGER NOT NULL DEFAULT 1,
  duration REAL NOT NULL DEFAULT 0,
  route_type TEXT NOT NULL DEFAULT '',
  rating REAL NOT NULL DEFAULT 0,
  review_count INTEGER NOT NULL DEFAULT 0,
  area TEXT NOT NULL DEFAULT '',
  state TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT '',
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  url TEXT NOT NULL DEFAULT '',
  photo TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_trails_lat ON trails(lat);
CREATE INDEX IF NOT EXISTS idx_trails_state ON trails(state);
CREATE INDEX IF NOT EXISTS idx_trails_reviews ON trails(review_count DESC);
CREATE VIRTUAL TABLE IF NOT EXISTS trails_fts USING fts5(name, area, state);
""")

def num(s, default=0.0):
    try:
        return float(s)
    except (ValueError, TypeError):
        return default

count = 0
cur = conn.cursor()
with open(src, encoding="utf-8-sig", newline="") as f:
    for row in csv.DictReader(f):
        lat, lng = num(row["Latitude"], None), num(row["Longitude"], None)
        if not row["Unique_Id"] or lat is None or lng is None:
            continue
        if abs(lat) > 90 or abs(lng) > 180:
            continue
        cur.execute(
            "INSERT OR IGNORE INTO trails(id,name,distance,elevation_gain,highest_point,"
            "difficulty,duration,route_type,rating,review_count,area,state,country,lat,lng,url,photo) "
            "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                row["Unique_Id"], row["Trail_Name"], num(row["Distance"]),
                num(row["Elevation_Gain"]), num(row["Highest_Point"]),
                int(num(row["Difficulty"], 1)), num(row["Est_Hike_Duration"]),
                row["Trail_Type"], num(row["Rating"]), int(num(row["Review_Count"])),
                row["Area"], row["State"], row["Country"], lat, lng,
                row["Url"], row.get("Cover_Photo", ""),
            ),
        )
        if cur.rowcount > 0:
            cur.execute(
                "INSERT INTO trails_fts(rowid,name,area,state) VALUES(?,?,?,?)",
                (cur.lastrowid, row["Trail_Name"], row["Area"], row["State"]),
            )
            count += 1

conn.commit()
conn.execute("INSERT INTO trails_fts(trails_fts) VALUES('optimize')")
conn.commit()
conn.execute("VACUUM")
conn.close()
print(f"imported {count} trails -> {dst}")
