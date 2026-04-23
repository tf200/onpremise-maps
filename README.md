# Shared Map Stack

This setup keeps your original architecture but consolidates the heavy services:

- `martin` serves vector tiles to MapLibre
- `valhalla_shared` exposes one routing API for Morocco, Tunisia, and Italy
- `photon_shared` exposes one search API for all supported countries
- `npm` sits in front of those services and exposes the admin UI on `8443`

The backend services do not expose their own UIs. They stay internal to Docker and are reached through NPM proxy hosts.

## Ports

- `NPM admin`: `http://localhost:8443`
- `NPM HTTP entrypoint`: `http://localhost:8080`
- `NPM HTTPS entrypoint`: `https://localhost:4443`

## NPM Setup

Create these proxy hosts in the NPM admin UI:

- `martin.localhost` -> `martin:3000`
- `valhalla.localhost` -> `valhalla_shared:8002`
- `photon.localhost` -> `photon_shared:2322`

If you want HTTPS for the proxied APIs, attach an SSL certificate in NPM and serve them through the `4443` entrypoint.

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
- starts `npm`, `martin`, `valhalla_shared`, and `photon_shared`

Photon still downloads and extracts the shared `planet` index into `photon/shared/` on first boot if it is missing.

## Operational Notes

- `Valhalla` routing works only for the countries in the shared routing graph: Morocco, Tunisia, and Italy.
- `Photon` search is broader than app support because it uses `planet`.
- If you later need Photon to return only Morocco, Tunisia, and Italy, you will need a custom Photon import/build instead of the ready-made `REGION` download.

## App Integration

Keep MapLibre and the app pointed at NPM proxy hosts instead of the raw backend containers:

- Tiles: `http://martin.localhost:8080` or `https://martin.localhost:4443`
- Routing: `http://valhalla.localhost:8080` or `https://valhalla.localhost:4443`
- Search: `http://photon.localhost:8080` or `https://photon.localhost:4443`

This keeps the backend containers off the host network and makes NPM the only public entrypoint for the APIs.

## Verification

Check NPM admin is up:

```bash
curl -I http://localhost:8443
```

Check Martin catalog through NPM:

```bash
curl http://martin.localhost:8080/catalog
```

Check Valhalla status through NPM:

```bash
curl -X POST http://valhalla.localhost:8080/status
```
