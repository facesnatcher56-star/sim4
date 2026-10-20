from: reviewer
to: builder
type: task
re: 2026-10-23T0100-reviewer-40-housing-ladder-rough-districts.md
status: open

**41: Art direction is too light-hearted (owner).** "Our visuals should represent this as well in these areas. Right now our entire game is too light-hearted looking, in my opinion."

What I see in the current shots (`coord/shots/act33-review/`, `docs/act33/`): candy pastel floors (lilac, peach), mint-green grass, pure white walls, flat even lighting, everything spotless. It reads as a toy town, which clashes with the 36, 39 and 40 direction (broke, rent, gangs, eviction).

**Please do a look test first, before changing the whole game:**
1. **Three palettes and lighting looks on the same 4 scenes** (the bare starter flat interior, a suburb street by day, a rough-district block at night, the town centre at dusk):
   - **A, "grounded":** desaturated real-world colours (worn wood, grey-beige plaster, tired lino, darker asphalt), softer warm interior light, real night;
   - **B, "gritty":** A plus more contrast, colder street light, dirt and wear;
   - **C, "today's" style kept as the reference.**

   Post the 12 screenshots to `coord/shots/art41/` and I'll take them to the owner to choose. Stay in the current low-poly style (no new art pipeline); this is palette, materials, lighting, wear and set dressing.
2. **District identity** (with 40 and later 30), each district with its own look table in data (wall and floor sets, roof colours, street furniture, props, light colour, litter and wear level):
   - **rough district:**
     - boarded and barred windows, graffiti decals, broken or flickering street lamps (sodium orange), chain-link fences;
     - litter, overturned bins, cracked pavement, burnt-out or abandoned cars;
     - corner-shop shutters, stained mattresses by bins, dark alleys;
     - fewer trees, and stains or patched paint on the buildings;
     - at night, mostly dark except a few lit windows and a corner-shop sign;
   - **the low-income housing** (rooming house, council block): tired interiors, peeling paint, mismatched cheap furniture, a shared bathroom with grime;
   - **suburbs:** tidy but lived-in (some mess, cars in drives, garden variety);
   - **the town centre:** busier signage, shop windows lit at night.
3. **State shows in the visuals (33-style):** a dirty home looks dirty (dishes, stains, clutter that builds up), broken things look broken, a poor player's flat looks poor. A rough block can visibly improve (gentrification, cleanup) or decline with events.
4. **Lighting and weather mood:** real night darkness (indoor lights matter), dusk and dawn colour, rain making streets wet and darker, winter greyer.
5. **UI tone:** less bubbly. Keep it readable, but with fewer bright mint accents and more neutral, sober panels. Include one UI screenshot per palette in the look test.
6. **Performance:** decals and props through the existing chunk and tier systems; no frame budget regression (`docs/PERFORMANCE.md`).

Effort estimate first (the look test alone is probably 1 session; the full pass is several). It can run alongside 36 since it's mostly data and materials, but the rough-district dressing needs 40's district.
