# Shore Chapters: a Three.js + Rapier foundation

A modular boilerplate for a chapter-based mini-game. The art direction is a stylised, atmospheric look inspired by
DON'T NOD's _Jusant_, and the setting is a beach, the open Atlantic and an old-town square modelled on Guimarães,
Portugal. It covers:

- **Look**: soft "baked" lighting through `onBeforeCompile`-patched materials, painterly world-space textures, a
  gradient sky that blends into `FogExp2`, colour grading, and prominent wind (curling streaks, drifting sand motes,
  swaying foliage).
- **Physics** ([Rapier](https://rapier.rs)): a sand heightfield that matches the shader-displaced dunes, a Gerstner
  ocean with buoyancy sampled from the same waves, a slanted cobbled plaza, an arcaded town hall and narrow streets
  built from grouped static colliders, and a raycast car with a drivetrain.
- **Character**: a component-based FSM covering idle/walk/run blending, jumping, sitting on benches and tavern
  tables, lying on beach towels, and entering, driving and leaving the car. It has a Verlet cloak and spring-bone hair
  and scarf that react to the wind.

| | | |
|---|---|---|
| ![City](docs/screenshots/02-city-from-promenade.jpg) | ![Plaza](docs/screenshots/03-plaza-townhall.jpg) | ![Shore](docs/screenshots/04-shore-ocean.jpg) |
| ![Sit](docs/screenshots/05-sit-bench.jpg) | ![Lie down](docs/screenshots/06-lay-towel.jpg) | ![Enter car](docs/screenshots/07a-entering-car.jpg) |

_Screenshots are from headless Chromium with software WebGL (SwiftShader), so the fps counter is not representative._

## Quick start

```bash
npm install
npm run dev       # Vite dev server
npm test          # headless physics / FSM test suite (Node ≥ 20)
npm run build     # production build in dist/
```

Requires WebGL2. Assets are procedural, so the project has no downloads beyond npm packages.

### Controls

| On foot | In the car |
|---|---|
| **WASD** move (camera-relative), **Shift** run, **Space** jump | **W** throttle, **S** brake (hold at standstill to reverse) |
| **E** interact (sit, lie down, drive); **E**/move to get up | **A/D** steer, **Space** handbrake, **E** exit (below ~9 km/h) |
| **Drag** orbit camera, **Wheel** zoom | **P** physics debug lines, **H** toggle help |

## Architecture

```
src/
├─ main.js                      bootstrap: Rapier → Engine → global services → chapter
├─ config.js                    palette, render/physics constants, collision layers, bindings, layout
├─ core/
│  ├─ Engine.js                 renderer, composer (MSAA → bloom → grading → output), fixed-step loop
│  ├─ PhysicsWorld.js           Rapier wrapper: interpolation links, scopes, grouped static colliders, queries
│  ├─ Input.js                  action-based input with frame-aware press latching
│  ├─ CameraRig.js              third-person orbit / anchored / vehicle chase, collision-aware
│  └─ ChapterManager.js         Chapter base class (root group, systems, physics scope) + loader
├─ shaders/
│  ├─ StylizedMaterial.js       onBeforeCompile patch of MeshLambertMaterial (lighting model, brush noise, triplanar, rim, wind sway)
│  ├─ common.glsl.js            shared uniforms (sun, sky, wind, time), noise, sky gradient
│  └─ grading.glsl.js           split-toning / saturation / contrast / vignette / grain
├─ environment/
│  ├─ Environment.js            lights, fog, sky, wind, sand, ocean, buoyancy, city, props (an Engine system)
│  ├─ Terrain.js                sandHeight() in JS and GLSL, generated from one parameter set
│  ├─ GerstnerWaves.js          wave spectrum, CPU sampler (inverse displacement, orbital velocity), GLSL
│  ├─ Ocean.js                  graded grid mesh + full ocean vertex/fragment shaders
│  ├─ Sand.js                   dune displacement, grain, ripples, glints, wet sand + heightfield collider
│  ├─ Buoyancy.js               sample-point Archimedes + drag against the wave orbital velocity
│  ├─ Sky.js / WindSystem.js / WindParticles.js
│  ├─ CityBuilder.js            Guimarães-style square: plaza, arcade, shrine, streets, benches, tavern
│  ├─ BeachProps.js             towels (lie-down anchors), parasols, floating crates/barrels/buoys/boat
│  ├─ MeshBatcher.js            groups placements into InstancedMesh draw calls
│  └─ TextureFactory.js         procedural tileable canvas textures (ashlar, stucco, setts, tiles, wood)
├─ character/
│  ├─ CharacterController.js    entity: components + FSM + intent + KCC bridging helpers
│  ├─ StateMachine.js           State / StateMachine with an explicit transition table
│  ├─ CharacterBody.js          capsule + KinematicCharacterController, postures, safe-spawn search
│  ├─ CharacterRig.js           procedural skeleton + pose-vector animator (cross-fades, blend space)
│  ├─ CharacterCloth.js         cloak (Verlet) + ponytail & scarf (spring bones)
│  └─ states/                   LocomotionStates, AnchoredStates (sit, lay), VehicleStates
├─ interaction/
│  ├─ InteractionManager.js     spatial-hash proximity, focus scoring, focus events
│  └─ Interactable.js           Interactable + Anchor (local transforms that follow moving objects)
├─ vehicle/
│  ├─ VehicleSystem.js          RaycastVehicle (Rapier controller + extras) and input routing
│  ├─ Drivetrain.js             torque curve (monotone cubic), auto gearbox, clutch launch, engine braking
│  └─ CarModel.js               procedural car, door hinge, seat mount, door anchor, exit points
├─ simulation/
│  ├─ VerletCloth.js            PBD cloth with per-triangle aerodynamics and capsule collisions
│  └─ SpringBoneChain.js        VRM-style spring bones + skinned tube helper
├─ chapters/ShoreChapter.js     chapter 1: wires it all together
└─ ui/                          HUD (prompt, gauges, toasts) + CSS
tests/                          node --test suites (physics, vehicle, end-to-end FSM)
```

### Frame loop

`Engine` runs physics at a fixed 60 Hz with an accumulator. It caps sub-steps per frame (`engine.maxSubSteps`) to
avoid a spiral of death:

```
for each fixed step:  systems.fixedUpdate → world.step → systems.postPhysics → capture poses
interpolate linked meshes (alpha = accumulator / dt)
systems.update(frameDt, renderTime) → systems.lateUpdate → composer.render
```

Systems are plain objects ordered by priority: input/debug (-100) → character (0) → vehicles (10) → environment
(20) → camera (50) → HUD (100). `renderTime` is the interpolated simulation time and feeds `uTime`, so the ocean shader
and the CPU buoyancy sampler always agree on where the waves are.

### Key design decisions

**One source of truth for GPU and CPU.** The dunes are displaced in the vertex shader. The physics heightfield,
towel placement, ocean depth and shore attenuation all use the same `sandHeight()`, generated as both JS and GLSL from
`TERRAIN`. The same applies to waves: `GerstnerWaves` emits the GLSL and implements the CPU mirror, including shore
attenuation and per-wavelength distance LOD. In the tests the heightfield deviates from the analytic surface by at
most 4 mm (threshold 5 cm), and the wave inversion residual is about 2 mm (threshold 1 cm).

**Stylised lighting without losing three.js features.** `createStylizedMaterial()` patches `MeshLambertMaterial`
instead of using a raw `ShaderMaterial`, so shadows, fog, instancing, skinning and tone mapping keep working. The patch
adds:

- wrapped diffuse with a soft ramp and a warm terminator band
- world-space domain-warped brush noise and fake contact occlusion
- triplanar texturing, so scaled instances never stretch
- a sky- or sun-tinted rim light
- optional vertex wind sway

Every variant is expressed through `defines`, which keeps three's program cache correct.

**FSM with an explicit transition table** (`CHARACTER_TRANSITIONS`). States are small scripts that call controller
helpers (`moveGrounded`, `walkTo`, `holdAndFace`, `setRootMode`). Transitions requested mid-update are deferred until
the update returns.

```
idle ⇄ walk ⇄ run ─┬─► airborne ─► idle/walk/run
                   ├─► sit         (approach → turn → settle → seated → standUp) ─► idle
                   ├─► layDown     (approach → turn → kneel → lie → lying → getUp → rise) ─► idle
                   └─► enterVehicle (approach → open → getIn) ─► drive ─► exitVehicle (door → findSpot → getOut) ─► idle
```

**Anchors.** Interactions snap to anchor matrices stored relative to an `Object3D`, so they follow moving vehicles.

| Anchor type | Origin and orientation |
|---|---|
| Seat | Pelvis contact point on the seat, +Z facing; carries `seatHeight` |
| Towel | Towel centre on the ground, +Y along the sand normal, head towards −Z |
| Door | Ground outside the door, +Z facing the car |

Approaches walk around props, so a bench approached from behind is handled. Stand-up and vehicle exit pick a free
spot by ground-probing and testing the capsule against candidate positions.

**Postures.** The capsule changes shape per state. Standing uses the KCC (slopes up to 48°, 0.38 m autostep, ground
snapping, pushing props). Seated parks a shorter capsule on the seat. Lying uses a horizontal capsule aligned to the
towel axis and the sand normal. In a vehicle the capsule is disabled and the rig is parented to the seat mount.

**Vehicle.** Rapier's `DynamicRayCastVehicleController` handles suspension, contacts and the friction circle.
`RaycastVehicle` adds on top:

- a torque curve and automatic gearbox, with clutch slip at launch, engine braking, a rev limiter and a limited
  reverse
- front-biased brakes in newtons, clamped to μ·N because Rapier doesn't limit brake impulses by grip
- a handbrake that unloads rear lateral grip
- per-wheel surface grip read from collider metadata (sand vs stone)
- anti-roll bars, aerodynamic drag and speed-sensitive steering
- a configurable `rollInfluence`. Rapier hard-codes Bullet's 0.1, which corners almost flat. At 1.0 (fully
  physical) the car rolls about 2° at roughly 0.9 g without anti-roll bars, matching a hand calculation. The default of
  0.55 plus anti-roll bars gives about 1°.

**Collision layers** (`config.js`): STATIC, CHARACTER, VEHICLE, DYNAMIC and BOUNDS. Invisible bounds stop only the
player and car. Camera rays only see static geometry, and wheel rays skip the car's own chassis.

**Performance.** The old town's 50 houses (about 3,000 placed parts: walls, windows, shutters, balconies, merlons)
collapse into 26 instanced draw calls, and all 139 city colliders hang off a single fixed body. Wind particles are fully GPU-animated.
The sun shadow frustum follows the player and is texel-snapped. Cloth and spring bones sub-step at fixed rates and
carry rigidly across long frames instead of exploding. Rapier's inlined WASM is lazy-loaded in its own chunk.

## Extending

- **New chapter**: subclass `Chapter` and build under `this.root`. Physics objects created during `load()` are scoped
  and freed on unload. Register the chapter in `main.js`.
- **New interaction**: add an `INTERACTION_TYPE`, a state, and an entry in `INTERACTION_STATE` and
  `CHARACTER_TRANSITIONS`.
- **Real character art**: keep `CharacterRig`'s API (`setLocomotion`, `playPose`, `setPoseParams`, `update`, `joints`)
  and drive a GLTF `SkinnedMesh` with `AnimationMixer`. Use a 1D idle/walk/run blend space with synced phase and
  cross-faded clips for poses. Point `CharacterCloth` at the shoulder and head bones.
- **Art tuning**: change `PALETTE`, `RENDER` (fog, bloom, grading), `WORLD.sun` and the per-material options in
  `CityBuilder._createAssets()`.
- **Physics tuning**: `RaycastVehicle` `cfg`, `Drivetrain` options, `POSTURE`, `CharacterController` speeds and
  accelerations, `WAVE_SPECTRUM` and `TERRAIN`.

## Known limitations

- The character is a procedural placeholder rig, with no foot IK or authored clips.
- Approach pathing uses one side waypoint. Swap in a navmesh for complex layouts.
- Only keyboard and mouse are supported, although `Input` is action-based so gamepad support is a mapping away.
- The ocean has no screen-space refraction or reflections, by design for the painted look. The shadow map is a single
  player-centred cascade.
