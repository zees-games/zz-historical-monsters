# Credits

The monsters are derived from free models. The shipped `.glb` files are build products of `tools/build_monsters.py` (Blender, headless) from the sources in `art-src/base/`: the script re-colours, wounds, adds ribs, spurs, teeth and glowing eyes, and decimates for the web.

| Monster | Base model | Author | Licence | Source |
| --- | --- | --- | --- | --- |
| T-Rex | "T-Rex" | Quaternius | CC0 1.0 | https://poly.pizza/m/UYtneO5FpF |
| Tiger | "Tiger" | Poly by Google | CC-BY 3.0 | https://poly.pizza/m/5A3w06FXUup |
| Bear | "Bear" (black bear) | Poly by Google | CC-BY 3.0 | https://poly.pizza/m/56ym_pyVnel |
| Raptor | "Velociraptor (reuploaded and retextured)" | seth the yutyrannus | CC-BY 4.0 | https://sketchfab.com/3d-models/velociraptor-reuploaded-and-retextured-def52bae17f749b0b911a695fdb05218 |
| Allosaurus | "Allosaurus" | seth the yutyrannus | CC-BY 4.0 | https://sketchfab.com/3d-models/allosaurus-02e651e39fed47bbaec0aa0546f17fd3 |
| Thylacine | "wolf" (a Tasmanian wolf, striped) | victory_mirosya | CC-BY 4.0 | https://sketchfab.com/3d-models/wolf-c5c2c9b77df94d758e732237a7d98af0 |

The Poly by Google models are CC-BY 3.0: credit is required and is given here and in the README. The modifications (infected skin, torn wound cavities with wet flesh, exposed ribs and spine, intestines, hanging skin strips, sunken eye sockets, ruined jaw, spurs, teeth, eyes, local mesh refinement) are in `tools/build_monsters.py`. Change note 2026-10-21: the bases were re-coloured, cut open and added to procedurally; no texture of the Poly by Google models ships, only colours baked into vertices.

The bear's page ("Black bear", Poly by Google) was found 2026-10-21 in the Poly Pizza bear search through an archived copy of it; its file here is `art-src/base/bear_polygoogle.glb` with the "BlackBear" texture.

Change note 2026-10-21 (round 2, infected look): wound colour is now a wide per-vertex ramp (bruised rim, dead lip, raw edge, muscle, cavity) with muscle-fibre streaks, pale fat, clotted blood and a wetness value in the vertex alpha that `view/zhm_view.gd`'s shader turns into gloss (dry hide is matte, only wet flesh and gut shine), instead of a second glossy material chosen per triangle; the body is smooth-shaded; intestines are thinner, curved, tapered and segmented; hanging strips have thickness, ragged width, taper and twist; the bear's hide is lifted and the tiger's pale muzzle capped. Still procedural, still no texture.

Change note 2026-10-21 (round 3, infected look): the detail moved from vertices to textures. `tools/bake_monsters.py` UV-unwraps each model (Blender, headless) and bakes a 1024 albedo (alpha is wetness) and a tangent-space normal map per species into `addons/zz_historical_monsters/monsters/textures/`, from the pack's own base models and procedural noise only: wound masks, muscle fibre streaks, fat, clotted blood, bruised rims, rotted patches, cracks, veins. The Poly by Google textures are sampled only as a base colour inside that baked image; no Sketchfab or other source was used. `view/zhm_view.gd` loads the PNGs by path beside the `.glb` (no texture dependency inside it), so they survive dot-cloud pack delivery. Vertex colour is no longer exported. Hanging strips and intestines were rebuilt (tapered, cupped, more segments; smooth-shaded tubes).

Change note 2026-10-22: the raptor, allosaurus and thylacine come from Sketchfab models (CC-BY 4.0, credited above). `tools/prep_base.py` bakes each rigged model to a static upright base (`art-src/base/*_sketchfab.glb`), then the same build and bake run as for the others. The raptor and allosaurus are decimated for the web and re-textured with the procedural infected skin; the thylacine's painted texture is replaced by a procedural dark coat with stripes, and it is decimated too. Limbs are shootable on every species (`docs/limb-hook-design.md`).
