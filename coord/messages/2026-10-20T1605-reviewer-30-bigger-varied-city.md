from: reviewer
to: builder
type: task
re: -
status: open

**30: A much bigger, varied city with curved roads and districts (owner request). Please post a design and cost estimate first, before building.** The owner: "We're probably going to expand the city to be a lot bigger. Do the roads have to be square like now, or can we have curves, a city with districts, suburbs and so on, so it's not all the same?"

**Today:**
- `MapBuilder` + `data/map_layout.json`: a 160×154 tile grid, a lattice of 6-wide straight roads, and 32×24 block slots (one lot template each);
- `NavGraph` built from straight sidewalk runs and crosswalks;
- `lot_chunks` floor meshes with road markings baked per tile;
- regions as rectangles.

**What I suggest (please confirm or counter):** keep the tile grid for the sim (walls, rooms, objects, A*, tiers, determinism all depend on it), and change how the city is laid out and drawn.
1. **A procedural city generator** (seeded, data-driven) with districts:
   - downtown (a dense grid, towers, plazas);
   - an old town (irregular streets);
   - suburbs (curved streets, cul-de-sacs, varied lot sizes, front gardens);
   - industrial (big lots, a rail line, warehouses);
   - a waterfront (a river or coast, a port, a bridge);
   - parks, woods and countryside at the edges (farms, a lake, a highway out).

   A road hierarchy: highway, avenue, street, lane, plus roundabouts and T-junctions.
2. **Curves on the tile grid:** roads are splines in data, rasterised to road tiles for the sim (any angle, including diagonals and curves), and drawn with a smooth road mesh from the spline (lanes, kerbs, centre lines, crosswalks, smooth sidewalks), so they look curved while the sim walks tiles. Rebuild `NavGraph` from the road centrelines and sidewalk polylines instead of straight runs. Vehicles (12b) follow the lane polylines.
3. **Lots of any shape facing any road:**
   - lots become polygons clipped to the tile grid, with the house footprint axis-aligned on tiles inside (rotate it in 90° steps to face the street, and maybe 45° later);
   - the yard, driveway and path fill the rest;
   - the house generator gets lot-size bands (a small terrace, a suburban plot, a big estate);
   - venues and towers get downtown plots.
4. **Scale:** a city several times today's area (aim for 4–10×) with chunk streaming and the 17.3 tiers. Statistical townies far away, full detail near anchors. Keep the perf budgets (frame avg 4 ms, minute 20 ms) on the big-town benchmark, plus a new "city" benchmark.
5. **Growth (12.6) uses real empty land:** zoned empty plots in the suburbs and outskirts get built over time, so the town visibly grows outward.
6. **Variety:**
   - per-district style tables: house styles, colours, roofs, trees and street furniture;
   - sidewalks only where they make sense (none on country lanes);
   - hills or terraces later (optional).

**Please reply with:** whether the tile-grid-plus-splines approach works with your code; what breaks (lot templates, `world_regions` as rects, the nav graph, `lot_chunks`, saves, co-op snapshots, share files); a stage plan (generator and districts; spline roads, meshes and nav; irregular lots; scale and streaming; growth); and rough time and risk. Then the owner decides. This shouldn't start before 12b and 29 are merged, since they touch the same view, map and story code.
