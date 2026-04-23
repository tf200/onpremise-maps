#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

declare -A PBF_URLS=(
  [morocco]="https://download.geofabrik.de/africa/morocco-latest.osm.pbf"
  [tunisia]="https://download.geofabrik.de/africa/tunisia-latest.osm.pbf"
  [italy]="https://download.geofabrik.de/europe/italy-latest.osm.pbf"
)

declare -A MBTILES_URLS=(
  [morocco]="https://download.geofabrik.de/africa/morocco-shortbread-1.0.mbtiles"
  [tunisia]="https://download.geofabrik.de/africa/tunisia-shortbread-1.0.mbtiles"
)

ITALY_MBTILES=(
  "https://download.geofabrik.de/europe/italy/centro-shortbread-1.0.mbtiles italy-centro.mbtiles"
  "https://download.geofabrik.de/europe/italy/isole-shortbread-1.0.mbtiles italy-isole.mbtiles"
  "https://download.geofabrik.de/europe/italy/nord-est-shortbread-1.0.mbtiles italy-nord-est.mbtiles"
  "https://download.geofabrik.de/europe/italy/nord-ovest-shortbread-1.0.mbtiles italy-nord-ovest.mbtiles"
  "https://download.geofabrik.de/europe/italy/sud-shortbread-1.0.mbtiles italy-sud.mbtiles"
)

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

download_if_missing() {
  local url="$1"
  local target="$2"

  if [[ -f "$target" && -s "$target" ]]; then
    echo "Using existing $(basename "$target")"
    return
  fi

  mkdir -p "$(dirname "$target")"
  echo "Downloading $(basename "$target")"
  curl -fL --retry 3 --retry-delay 2 -o "$target" "$url"
}

prepare_directories() {
  mkdir -p \
    "$ROOT_DIR/martin/data" \
    "$ROOT_DIR/photon/shared" \
    "$ROOT_DIR/valhalla/shared"
}

prepare_martin_data() {
  local country
  for country in "${!MBTILES_URLS[@]}"; do
    download_if_missing "${MBTILES_URLS[$country]}" "$ROOT_DIR/martin/data/${country}.mbtiles"
  done

  local item url filename
  for item in "${ITALY_MBTILES[@]}"; do
    url="${item% *}"
    filename="${item##* }"
    download_if_missing "$url" "$ROOT_DIR/martin/data/$filename"
  done
}

prepare_valhalla_data() {
  local country
  for country in "${!PBF_URLS[@]}"; do
    download_if_missing "${PBF_URLS[$country]}" "$ROOT_DIR/valhalla/shared/${country}-latest.osm.pbf"
  done
}

print_notes() {
  cat <<'EOF'
Startup requested:
- martin uses local MBTiles from martin/data
- valhalla_shared builds from local PBF files in valhalla/shared
- photon_shared downloads its own REGION=planet index into photon/shared on first boot if missing

First photon boot can take a long time and needs substantial disk space.
EOF
}

main() {
  ensure_command curl
  ensure_command docker

  prepare_directories
  prepare_martin_data
  prepare_valhalla_data
  print_notes

  docker compose -f "$ROOT_DIR/docker-compose.yml" up -d martin valhalla_shared photon_shared
}

main "$@"
