# Credits

The three monsters are derived from free models. The shipped `.glb` files are build products of `tools/build_monsters.py` (Blender, headless) from the sources in `art-src/base/`: the script re-colours, wounds, adds ribs, spurs, teeth and glowing eyes, and decimates for the web.

| Monster | Base model | Author | Licence | Source |
| --- | --- | --- | --- | --- |
| T-Rex | "T-Rex" | Quaternius | CC0 1.0 | https://poly.pizza/m/UYtneO5FpF |
| Tiger | "Tiger" | Poly by Google | CC-BY 3.0 | https://poly.pizza/m/5A3w06FXUup |
| Bear | "Bear" (black bear) | Poly by Google | CC-BY 3.0 | https://poly.pizza/m/56ym_pyVnel |

The Poly by Google models are CC-BY 3.0: credit is required and is given here and in the README. The modifications (infected skin, torn wound cavities with wet flesh, exposed ribs and spine, intestines, hanging skin strips, sunken eye sockets, ruined jaw, spurs, teeth, eyes, local mesh refinement) are in `tools/build_monsters.py`. Change note 2026-10-21: the bases were re-coloured, cut open and added to procedurally; no texture of the Poly by Google models ships, only colours baked into vertices.

The bear's page ("Black bear", Poly by Google) was found 2026-10-21 in the Poly Pizza bear search through an archived copy of it; its file here is `art-src/base/bear_polygoogle.glb` with the "BlackBear" texture.

Change note 2026-10-21 (round 2, infected look): wound colour is now a wide per-vertex ramp (bruised rim, dead lip, raw edge, muscle, cavity) with muscle-fibre streaks, pale fat, clotted blood and a wetness value in the vertex alpha that `view/zhm_view.gd`'s shader turns into gloss (dry hide is matte, only wet flesh and gut shine), instead of a second glossy material chosen per triangle; the body is smooth-shaded; intestines are thinner, curved, tapered and segmented; hanging strips have thickness, ragged width, taper and twist; the bear's hide is lifted and the tiger's pale muzzle capped. Still procedural, still no texture.
