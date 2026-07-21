#!/bin/bash
# 逐州下载 Geofabrik OSM 数据，离线匹配步道路线写入 Resources/trails.sqlite。
# 用法: build_routes.sh <工作目录> [起始州名]
set -u
WORK="${1:?work dir}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DB="$REPO/data/trails.sqlite"
cd "$WORK"

sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS trail_routes(trail_id TEXT PRIMARY KEY, coords TEXT NOT NULL, updated_at REAL NOT NULL);"

sqlite3 "$DB" "SELECT DISTINCT state FROM trails ORDER BY state;" | while IFS= read -r STATE; do
  SLUG=$(echo "$STATE" | tr 'A-Z' 'a-z' | tr ' ' '-')
  echo "BEGIN $STATE"
  # 缓存各州抽取好的全部徒步路径（含无名 way，用于路网连接），重跑时免下载
  if [ ! -s "${SLUG}-all.geojsonl" ]; then
    if ! curl -sL --retry 3 --max-time 1200 -o s.pbf \
        "https://download.geofabrik.de/north-america/us/${SLUG}-latest.osm.pbf"; then
      echo "ERROR download $STATE"
      continue
    fi
    if ! osmium tags-filter s.pbf w/highway=path,footway,track,steps -o f1.pbf --overwrite >/dev/null 2>&1; then
      echo "ERROR filter $STATE"
      rm -f s.pbf
      continue
    fi
    osmium export f1.pbf -f geojsonseq -o "${SLUG}-all.geojsonl" --overwrite >/dev/null 2>&1
    rm -f s.pbf f1.pbf
  fi
  python3 "$REPO/scripts/match_routes.py" "${SLUG}-all.geojsonl" "$STATE" "$DB" || echo "ERROR match $STATE"
done
echo PIPELINE_DONE
