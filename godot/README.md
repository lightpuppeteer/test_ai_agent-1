# Our Little Island (Godot 4.7)

A cozy, Animal Crossing–style island holding a year of memories. This replaces the three.js prototype (kept in
the repo root for reference). Open this folder in **Godot 4.7** and press **F5**.

## Controls

| On foot | In the car |
|---|---|
| **WASD** walk (camera-relative), **Shift** run, **Space** jump | **W** throttle, **S** brake (hold at a standstill to reverse) |
| **E** sit on a bench, lie on a towel, drive, talk | **A/D** steer, **Space** handbrake, **E** get out (below ~9 km/h) |
| **Drag** orbit the camera, **Wheel** zoom (trackpad pinch and scroll work too) | |
| **O** her outfit, **Shift+O** his outfit, **T** time of day | **Q** quest log, **M** music on/off, **H** controls, **F12** photo, **F3** fps |

**N** cycles the mini-map zoom. Run with `-- --kenney` to see the original blocky Kenney props instead of the
round ones (`scripts/world/round_kit.gd`) and the KayKit furniture (CC0, `assets/kaykit/furniture`). While decorating the house: **Z/X** pick a piece, **R** rotate, **E** place,
**F** pick a piece back up, **Esc** finish. **Esc** also stands up or leaves the car.

**PlayStation (DualSense) controller**: left stick moves, right stick orbits, **✕** interact, **○** stand up / back,
**□** jump (handbrake in the car), **△** quest log, **R1** run, **R2/L2** throttle/brake, **L1** her outfit,
**D-pad** ← his outfit, ↑ time of day, ↓ music, → map zoom (↑/↓ also pick dialogue answers), **Options** controls,
**Create** photo. On-screen button hints switch to PlayStation glyphs as soon as the controller is touched, and it
rumbles on bumps and big moments.

## What's on the island

- **Town square**: a fountain, benches, lamps, market stalls, a café corner and the town hall.
- **Houses**: four houses with coloured roofs and little gardens.
- **Promenade**: a paved walk along the coast with benches facing the sea and lamps that light up in the evening.
- **Beach**: palms, towels in pairs, parasols, rocks and driftwood. A dock has a bench at the end, and boats, buoys,
  barrels and crates bob on the waves.
- **Lookout hill**: a plateau reached by a ramp, with a big oak, a bench, a picnic blanket and a fence along the cliff.
- **The two of you**: custom chibi avatars (`scripts/characters/avatar_looks.gd`). Her outfits: black jacket and
  wide trousers, silver dress, skirt and top, bikini. His: beige tee and cargo shorts, all black, beach shorts.
- **Partner**: walks beside you, sits next to you, lies on the towel beside yours and rides along in the car.
- **Villagers**: six animal neighbours (cat, dog, bunny, fox, penguin, koala) wander around and chat when you press E.
- **Places with interiors** (doors fade you inside a cut-away "dollhouse" room): Pizzeria Amore, Cinemas NOS
  (horror, comedy and drama on rotation, popcorn and drinks), our house (decorate it with the furniture inventory),
  the Hotel & Spa (an enormous bed inside; outside, a real swimming pool: wade in and you both swim, changing
  into swimwear and back automatically). Her place is the pink-roofed house where Yoggi lives.
- **The Island Arcade** (the pink building north of the plaza): **Yoggi Run** (endless runner: jump the pots
  and cucumbers, grab fish treats), **Pizza Rush** (top each pizza like its order ticket says: ↑ pepperoni,
  ← mushroom, → olive, ↓ basil) and the **Claw Crane** (a little 3D claw machine; plushes you win go on a shelf
  in the living room). High scores are saved, and Marco's are there to beat. Esc / ○ steps away from a cabinet.
- **The picnic garden** east of town, the **road across the sea** to the oasis island, and the **volcano** behind it.
- **Mini-map** (bottom left) with a heart for the current goal.

## The story

Eight quests in order, each with the dialogue trees from `scripts/story/story_data.gd` (pick her answers with
the mouse, ↑/↓ + E, or the D-pad + ✕): the first pizza date, flirting on the beach and the first kiss in the car
("boyfriend unlocked"), the picnic, the cinema, moving in (decorate, then catch Yoggi and bring him home), the spa
day, the road to the oasis and the ring under the erupting volcano, and the anniversary ending with fireworks and
"Happy 1st Year Anniversary, to more together!" (on their bench on the promenade, with fireworks over the sea, hearts
bubbling up and a little kiss). Each chapter starts with a little text from Marco: he heads off to
the place (the pizzeria door, the beach towels, the garden…) and waits there for her. After the ending the island
is free to wander together, keeping the ring, the decorated house and Yoggi.

**Island Treasures** (side quest from Biscuit the dog on the promenade): twelve minerals are buried around the
island under star-shaped cracks, from the meadows and the hill to the beach and the oasis. Press E to dig; each
one goes onto a little shelf in our living room (`scripts/quests/minerals.gd`, `scripts/quests/dig_spot.gd`).

## Writing quests

Quests live in `scripts/quests/quest_data.gd`. The comment at the top lists every step type: go somewhere, meet him
somewhere (`meet`), talk to someone, sit or lie down together, collect and deliver items, wait for a time of day, drive, take a photo, show a
memory, or wait. Each quest is a small dictionary. Progress is saved in `user://save.json`; run with
`-- --reset_save` to start over. A heart marker floats over the current goal, and **Q** opens the quest log.

## Music and sound

Everything in `assets/audio` is generated by `tools/audio_gen/synth.py` (`python3 tools/audio_gen/synth.py
assets/audio`). It writes three music loops (day, golden hour, night) plus a title theme, footsteps for grass, sand,
stone and wood, UI jingles, villager babble in the style of Animalese, waves, birds, crickets, the fountain and the car
engine. To use your own music, replace `music_*.ogg` and keep the names.

## Making chapters

Chapters live in `scripts/chapters/`. Copy `shore_chapter.gd`, then set a title, a time of day (`day`, `golden` or
`night`) and a spawn point, and call `add_memory(position, title, lines)` for each moment. Register the new script in
`ChapterManager.CHAPTERS`. Villager lines are in `scripts/core/main.gd`, and the partner's lines are in
`scripts/characters/partner.gd`.

## The look

- **Cozy toon shading + rolling world**: every material is converted at runtime by `scripts/core/stylizer.gd` to the
  shaders in `shaders/cozy*.gdshader` (soft cel light, rim light, and the Animal Crossing–style curve of the world
  away from the camera; strength in `[shader_globals] curve_amount`). Run with `-- --flat` to turn it off.
- **Storybook trees** are generated by `scripts/world/tree_factory.gd` (round trees, cedars, fruit trees).
- **Cottages** (`scripts/world/cottage.gd`): every house is built from soft shapes: pillowy walls on a pebble
  plinth, rounded corner stones, scalloped shingle roofs (or a toadstool cap), shuttered windows with flower boxes,
  an arched door with a porch light and potted shrubs.
- **Chibi heads**: you two have round superellipsoid heads with the face painted onto the curve, and hair and
  beards as soft shells with smooth openings (`Avatar._add_ball`, looks in `avatar_looks.gd`).
- **Grass carpet** (`scripts/world/grass_field.gd`, `shaders/grass_field.gdshader`): a thick Animal Crossing–style
  lawn of 1 m turfs, drawn out to 100 m in three detail levels that hand over smoothly; the blades sway in the
  wind and bend away from whoever walks through them.
- **Performance**: full screen with the 3D world at 1080 lines or more (F11 toggles a window), a 60 fps cap, and
  a quality governor (`scripts/core/quality_governor.gd`) that drops the subtlest effects if the GPU heats up.
- **Toon water** (`shaders/ocean.gdshader`): banded shallow/deep colours, Voronoi light ripples and foam, with
  depth-based absorption of what is under the surface.
- **Lighting**: soft PCSS sun shadows tinted lavender, SSAO and glow. Screen-space indirect light (as in Godot's
  GI demo) is available with `-- --ssil` on GPUs that can spare ~2.5 ms.
- **Neighbours** are little bipedal animals on the same rig as you two (`scripts/characters/animal_looks.gd`).
- **Signs and posters** are painted by `python3 tools/sign_art/make_signs.py` into `assets/signs/`.
- Marco and Yoggi walk on navigation meshes baked at startup (`scripts/world/nav_baker.gd`); physics is Jolt.

## Building the Mac app

`export_presets.cfg` has a **macOS** preset (universal Intel + Apple Silicon, ad-hoc signed, icon `icon_app.png`).
With the 4.7.2 export templates installed: Project → Export → macOS, or
`godot --headless --path godot --export-release "macOS" build/OurLittleIsland.zip`.
The app isn't notarized, so the first launch on another Mac may need right-click → Open.

## Structure

```
scenes/main.tscn              boots everything from scripts/core/main.gd
scripts/core/                 game.gd (autoload: input map, shared refs), main.gd, camera_rig.gd
scripts/world/                terrain (heightfield + collider), ocean (waves, mirrored on the CPU), atmosphere
                              (sky, sun, presets), island_builder (all prop placement), world_layout (the map in
                              numbers), props (asset catalogue, recolouring, wind sway), buoyant_body, ambient_fx
scripts/characters/           person.gd (movement, animation, sit/lie/drive poses), player.gd, partner.gd, villager.gd
scripts/vehicles/car.gd       VehicleBody3D built from a Kenney car
scripts/interaction/          interactable.gd (seats/anchors), memory_spot.gd
scripts/chapters/             chapter base class, chapter manager, chapter 1
scripts/ui/                   hud.gd (prompt bubble, dialogue box, toasts, title card), title_screen.gd
shaders/                      terrain, ocean, sky, foliage sway, palette swap, stripes
tools/                        dev scenes: contact sheets, pose sheet, lint, screenshot helpers
assets/kenney/                Kenney kits (CC0, see each License.txt), assets/fonts (Fredoka + Nunito, OFL)
```

### How a few things work

- **One map, many users.** `WorldLayout` defines the coast, beach width, road loop, plaza, paths and the hill. The
  terrain heights, the painted ground (a splat texture), the prop placement and the flower scatter all read it, so
  they always agree.
- **Waves.** `Ocean.height_at()` evaluates the same sum of sines as `ocean.gdshader`, using the physics clock.
  Floating props sample it, so they ride the visible waves. The shader reads the terrain height texture for shallow
  colour and shoreline foam.
- **Characters.** Kenney *Mini Characters* (player and partner) are scaled 1.6×. Sitting and driving use their own
  animations. Lying down is the rest pose laid on its back. *Cube Pets* are the villagers.
- **Recolouring.** Kenney's palette-textured models are recoloured on the GPU (`palette_swap.gdshader`), which is how
  the houses get their roof colours. The nature kit's teal greens are warmed through `Props.NATURE_PALETTE` and
  the sway shader.

### Screenshots for visual checks

Run with `-- --shots=/some/dir --views=start,plaza,sit,lie,drive,golden,night`, or put the same `key=value` lines
in `res://shots_request.cfg`. That file is deleted after use. View names are listed in
`scripts/tools/shot_director.gd`.

## Credits

3D assets: [Kenney](https://kenney.nl) (CC0), found through [3d.shep.bot](https://3d.shep.bot), and
[KayKit Furniture Bits](https://kaylousberg.itch.io/furniture-bits) (CC0). Fonts: Fredoka and Nunito (SIL Open Font
License). Shader ideas from godotshaders.com: "Stylized Toon Water" (Thundergecko8, MIT), "Absorption-based
stylized water" (CC0) and "Stylized grass with wind and deformation" (MIT), rewritten for this project's toon
lighting.
