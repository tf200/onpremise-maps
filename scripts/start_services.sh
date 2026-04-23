#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARTIN_RAW_DIR="$ROOT_DIR/martin/raw"
MARTIN_SERVE_DIR="$ROOT_DIR/martin/data"
MERGED_MBTILES_NAME="basemap.mbtiles"
MERGED_MBTILES_PATH="$MARTIN_SERVE_DIR/$MERGED_MBTILES_NAME"
MARTIN_INPUTS_DIGEST="$MARTIN_SERVE_DIR/.basemap.inputs.sha256"
TIPPECANOE_IMAGE="${TIPPECANOE_IMAGE:-klokantech/tippecanoe:latest}"

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
    "$MARTIN_RAW_DIR" \
    "$MARTIN_SERVE_DIR" \
    "$ROOT_DIR/photon/shared" \
    "$ROOT_DIR/valhalla/shared"
}

prepare_martin_data() {
  local country
  for country in "${!MBTILES_URLS[@]}"; do
    download_if_missing "${MBTILES_URLS[$country]}" "$MARTIN_RAW_DIR/${country}.mbtiles"
  done

  local item url filename
  for item in "${ITALY_MBTILES[@]}"; do
    url="${item% *}"
    filename="${item##* }"
    download_if_missing "$url" "$MARTIN_RAW_DIR/$filename"
  done
}

migrate_legacy_martin_data() {
  shopt -s nullglob
  local legacy_file
  for legacy_file in "$MARTIN_SERVE_DIR"/*.mbtiles; do
    if [[ "$(basename "$legacy_file")" == "$MERGED_MBTILES_NAME" ]]; then
      continue
    fi
    echo "Moving legacy Martin source $(basename "$legacy_file") to martin/raw"
    mv "$legacy_file" "$MARTIN_RAW_DIR/"
  done
  shopt -u nullglob
}

compute_martin_inputs_digest() {
  find "$MARTIN_RAW_DIR" -maxdepth 1 -type f -name '*.mbtiles' -printf '%f|%s|%T@\n' \
    | sort \
    | sha256sum \
    | awk '{print $1}'
}

merge_martin_tiles_if_needed() {
  local source_files=()
  while IFS= read -r -d '' file; do
    source_files+=("$file")
  done < <(find "$MARTIN_RAW_DIR" -maxdepth 1 -type f -name '*.mbtiles' -print0 | sort -z)

  if (( ${#source_files[@]} == 0 )); then
    echo "No source MBTiles found in martin/raw; cannot build $MERGED_MBTILES_NAME" >&2
    exit 1
  fi

  local current_digest previous_digest=""
  current_digest="$(compute_martin_inputs_digest)"
  if [[ -f "$MARTIN_INPUTS_DIGEST" ]]; then
    previous_digest="$(<"$MARTIN_INPUTS_DIGEST")"
  fi

  if [[ -s "$MERGED_MBTILES_PATH" && "$current_digest" == "$previous_digest" ]]; then
    echo "Using existing $MERGED_MBTILES_NAME"
    return
  fi

  local container_inputs=()
  local source_file
  for source_file in "${source_files[@]}"; do
    container_inputs+=("/input/$(basename "$source_file")")
  done

  local temp_basename=".basemap.tmp.$$.$RANDOM.mbtiles"
  local temp_output="$MARTIN_SERVE_DIR/$temp_basename"
  rm -f "$temp_output"

  echo "Merging ${#source_files[@]} MBTiles files into $MERGED_MBTILES_NAME"
  if ! docker run --rm \
    -v "$MARTIN_RAW_DIR:/input:ro" \
    -v "$MARTIN_SERVE_DIR:/output" \
    "$TIPPECANOE_IMAGE" \
    tile-join -f -pk -o "/output/$temp_basename" "${container_inputs[@]}"; then
    rm -f "$temp_output"
    echo "Failed to merge MBTiles with tile-join" >&2
    exit 1
  fi

  mv -f "$temp_output" "$MERGED_MBTILES_PATH"
  printf '%s\n' "$current_digest" >"$MARTIN_INPUTS_DIGEST"
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
- npm admin UI is available on http://localhost:8443
- npm proxy entrypoints are available on http://localhost:8080 and https://localhost:4443
- martin serves a single merged source from martin/data/basemap.mbtiles
- martin/raw stores country/subregion source MBTiles used for merge
- valhalla_shared builds from local PBF files in valhalla/shared
- photon_shared downloads its own REGION=planet index into photon/shared on first boot if missing

First photon boot can take a long time and needs substantial disk space.
EOF
}

main() {
  ensure_command curl
  ensure_command docker
  ensure_command sha256sum

  prepare_directories
  migrate_legacy_martin_data
  prepare_martin_data
  merge_martin_tiles_if_needed
  prepare_valhalla_data
  print_notes

  docker compose -f "$ROOT_DIR/docker-compose.yml" up -d npm martin valhalla_shared photon_shared
}

main "$@"
