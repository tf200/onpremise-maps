# Shared Map Stack

This setup keeps your original architecture but consolidates the heavy services:

- `martin` serves vector tiles to MapLibre
- `valhalla_shared` exposes one routing API for Morocco, Tunisia, and Italy
- `photon_shared` exposes one search API for all supported countries

There is no gateway or extra backend layer. Your app keeps calling each service API directly, but routing and search now use one shared endpoint each.

## Ports

- `martin`: `http://localhost:3000`
- `valhalla_shared`: `http://localhost:8002`
- `photon_shared`: `http://localhost:2322`

## Data Layout

### Martin

Put one tile archive per country in `martin/data/`:

```text
martin/data/
  morocco.mbtiles
  tunisia.mbtiles
  italy-centro.mbtiles
  italy-isole.mbtiles
  italy-nord-est.mbtiles
  italy-nord-ovest.mbtiles
  italy-sud.mbtiles
```

`martin` will discover all files in that directory automatically.

Geofabrik does not publish a single Italy shortbread MBTiles file. Italy is split into five subregion MBTiles downloads, and the bootstrap script downloads all five.

### Valhalla

The shared Valhalla service stores one combined graph in `valhalla/shared/`.

On startup, `docker-valhalla` downloads and builds from these three source extracts:

- Morocco: `https://download.geofabrik.de/africa/morocco-latest.osm.pbf`
- Tunisia: `https://download.geofabrik.de/africa/tunisia-latest.osm.pbf`
- Italy: `https://download.geofabrik.de/europe/italy-latest.osm.pbf`

This produces one shared routing graph for the currently supported countries.

### Photon

The shared Photon service stores one search index under `photon/shared/`.

`photon-docker` does not provide a ready-made Morocco+Tunisia+Italy combined index, so the shared setup uses:

- `REGION=planet`

That gives you one search endpoint, but it also means Photon can return results outside the countries you currently support.

## Bootstrap

Use the bootstrap script:

```bash
./scripts/start_services.sh
```

The script:

- downloads missing Morocco and Tunisia `.mbtiles` files, plus the five Italy subregion `.mbtiles` files, into `martin/data/`
- downloads missing Morocco, Tunisia, and Italy `.osm.pbf` files into `valhalla/shared/`
- starts `martin`, `valhalla_shared`, and `photon_shared`

Photon still downloads and extracts the shared `planet` index into `photon/shared/` on first boot if it is missing.

## Operational Notes

- `Valhalla` routing works only for the countries in the shared routing graph: Morocco, Tunisia, and Italy.
- `Photon` search is broader than app support because it uses `planet`.
- If you later need Photon to return only Morocco, Tunisia, and Italy, you will need a custom Photon import/build instead of the ready-made `REGION` download.

## App Integration

Keep MapLibre pointed at `martin`, and point all supported countries to the same routing and search endpoints:

- Routing: `:8002`
- Search: `:2322`

This removes per-country endpoint switching from the app.

## Verification

Check Martin catalog:

```bash
curl http://localhost:3000/catalog
```

Check Valhalla status:

```bash
curl -X POST http://localhost:8002/status
```

Check Photon:

```bash
curl "http://localhost:2322/api?q=casablanca"
curl "http://localhost:2322/api?q=tunis"
curl "http://localhost:2322/api?q=rome"
```
