#!/usr/bin/env python3
"""Regenerate every audio asset of the game (deterministic, fixed seeds).

    python3 tools/audio/build_audio.py              # everything
    python3 tools/audio/build_audio.py sfx voice    # only some groups

Groups: music, jingles, ui, steps, car, ambience, voice.
Writes OGG Vorbis (q5) to assets/audio/<category>/ and updates
assets/audio/manifest.json. Each file is decoded back and checked
(peak, loudness, duration, loop seam). Spectrograms of the music go to
/home/claude/scratch/audio_check/ (or $AUDIO_CHECK_DIR).
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import ambience  # noqa: E402
import check  # noqa: E402
import sfx  # noqa: E402
import songs  # noqa: E402
import voice  # noqa: E402
from dsp import SR, encode, decode  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")
MANIFEST = os.path.join(AUDIO, "manifest.json")
CHECK_DIR = os.environ.get("AUDIO_CHECK_DIR", "/home/claude/scratch/audio_check")


def have_vorbis():
    try:
        out = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
        return "libvorbis" in out
    except FileNotFoundError:
        return False


FMT = "ogg" if have_vorbis() else "wav"
entries = {}
problems = []


def emit(rel, x, category, desc, loop=False, volume_db=0.0, peak_limit=None, extra=None):
    """Encode, decode back, verify, and register in the manifest."""
    rel = rel.replace(".ogg", "." + FMT)
    path = os.path.join(AUDIO, rel)
    x = np.asarray(x, dtype=np.float64)
    encode(path, x, FMT)
    y = decode(path)
    if y.shape[1] == 1:
        y = y[:, 0]
    info = check.summarize(y, loop=loop)
    n_src = len(x)
    if len(y) != n_src:
        problems.append(f"{rel}: decoded length {len(y)} != source {n_src}")
    if peak_limit is not None and info["peak_dbfs"] > peak_limit + 0.05:
        problems.append(f"{rel}: peak {info['peak_dbfs']} dBFS > {peak_limit}")
    want_ch = 1 if x.ndim == 1 else 2
    if info["channels"] != want_ch:
        problems.append(f"{rel}: channels {info['channels']} != {want_ch}")
    if loop and info.get("seam_step_ratio", 0) > 1.0:
        problems.append(f"{rel}: loop seam step ratio {info['seam_step_ratio']}")
    e = {
        "path": "res://assets/audio/" + rel,
        "category": category,
        "duration_s": round(n_src / SR, 3),
        "loop": bool(loop),
        "channels": want_ch,
        "volume_db": volume_db,
        "description": desc,
        "peak_dbfs": info["peak_dbfs"],
        "lufs": info["lufs"],
    }
    if loop:
        e["loop_start_s"] = 0.0
        e["loop_end_s"] = round(n_src / SR, 3)
        e["seam_step_ratio"] = info["seam_step_ratio"]
    if extra:
        e.update(extra)
    entries[e["path"]] = e
    print(f"  {rel:38s} {e['duration_s']:7.3f}s  ch{want_ch}  peak {info['peak_dbfs']:6.2f}  "
          f"LUFS {info['lufs']:6.2f}" + (f"  seam {info['seam_step_ratio']:.3f}" if loop else ""))
    return y


# ------------------------------------------------------------------ groups
MUSIC_META = {
    "day": dict(bpm=100, key="F major", time_signature="4/4", swing=0.62,
                desc="Sunny afternoon island theme: FM e-piano comping, marimba arps, pizz bass, "
                     "brushes, ocarina lead (A-A-B-A after a 4-bar intro), glockenspiel counter-melody."),
    "golden": dict(bpm=84, key="Bb major", time_signature="4/4", swing=0.56,
                   desc="Golden-hour / sunset theme for romantic moments: e-piano, soft pad, nylon guitar "
                        "arpeggios, clarinet-recorder lead; iv-minor and ii-V to G minor colours."),
    "night": dict(bpm=70, key="F major", time_signature="3/4", swing=0.5,
                  desc="Starry-night lullaby waltz: music box + celesta melody, long-sustain piano, warm pad, "
                       "occasional high twinkles, no drums."),
    "title": dict(bpm=72, key="F major", time_signature="4/4", swing=0.55,
                  desc="Title screen: tender music-box/celesta arrangement of the day theme with harp and pad."),
}


def build_music():
    os.makedirs(CHECK_DIR, exist_ok=True)
    for name in ("day", "golden", "night", "title"):
        t0 = time.time()
        song, out = songs.render(name)
        meta = MUSIC_META[name]
        y = emit(f"music/{name}.ogg", out, "music", meta["desc"], loop=True, volume_db=0.0,
                 peak_limit=-3.0, extra=dict(bpm=meta["bpm"], key=meta["key"],
                                             time_signature=meta["time_signature"],
                                             bars=song.bars, swing=meta["swing"]))
        check.spectrogram_png(os.path.join(CHECK_DIR, f"{name}_spec.png"), y, f"{name} (decoded ogg)")
        # double-loop junction render for click inspection
        jn = np.concatenate([y[-int(0.5 * SR):], y[:int(0.5 * SR)]])
        check.spectrogram_png(os.path.join(CHECK_DIR, f"{name}_junction.png"), jn,
                              f"{name}: last 0.5 s -> first 0.5 s")
        print(f"    ({time.time() - t0:.0f}s)")


def build_jingles():
    J = [
        ("jingle_quest_start", sfx.jingle_quest_start, "'New event!' bright ascending marimba/glock motif"),
        ("jingle_quest_step", sfx.jingle_quest_step, "Objective updated: three cute kalimba/glock notes"),
        ("jingle_quest_complete", sfx.jingle_quest_complete, "Quest complete: little ocarina fanfare with band"),
        ("jingle_memory", sfx.jingle_memory, "Memory found: tender music-box arpeggio over soft pad"),
        ("jingle_item", sfx.jingle_item, "Item get: sparkly 3-note glock/celesta + shimmer"),
    ]
    for name, fn, desc in J:
        emit(f"sfx/{name}.ogg", fn(), "jingle", desc, volume_db=-1.0, peak_limit=-3.0)


def build_ui():
    U = [
        ("ui_confirm", sfx.ui_confirm, "Menu confirm: two rising plinks", -4.0),
        ("ui_cancel", sfx.ui_cancel, "Menu cancel/back: two soft falling notes", -4.0),
        ("ui_open", sfx.ui_open, "Panel/menu open: upward swish + kalimba", -5.0),
        ("ui_close", sfx.ui_close, "Panel/menu close: downward swish + kalimba", -5.0),
        ("ui_prompt", sfx.ui_prompt, "Soft bubble pop when the interact prompt appears", -6.0),
        ("ui_toast", sfx.ui_toast, "Toast/notification: gentle two-note glock chime", -5.0),
        ("ui_text_advance", sfx.ui_text_advance, "Dialogue next page: tiny soft tick", -6.0),
        ("photo_shutter", sfx.photo_shutter, "Camera shutter click-clack", -3.0),
        ("pickup_pop", sfx.pickup_pop, "Pick up item: bubbly pop + glock ping", -4.0),
        ("sit_down", sfx.sit_down, "Sit on bench: cloth rustle, soft wood creak, thump", -4.0),
        ("stand_up", sfx.stand_up, "Stand up: rustle + light creak", -4.0),
        ("lie_down", sfx.lie_down, "Lie down on towel: towel rustle + soft fwump", -4.0),
        ("jump", sfx.jump, "Cartoony 'bwip' jump", -5.0),
        ("land", sfx.land, "Soft landing thump", -4.0),
        ("splash_small", sfx.splash_small, "Small splash stepping into shallow water", -4.0),
    ]
    for name, fn, desc, vol in U:
        emit(f"sfx/{name}.ogg", fn(), "ui" if name.startswith("ui_") else "sfx", desc,
             volume_db=vol, peak_limit=-1.0)
    emit("sfx/sparkle_loop.ogg", sfx.sparkle_loop(), "sfx",
         "Very quiet shimmering loop for memory sparkles (3 s, seamless)", loop=True,
         volume_db=-8.0, peak_limit=-1.0)


def build_steps():
    desc = {"grass": "grass rustle", "sand": "soft sand scrunch", "stone": "stone/cobble tap",
            "wood": "hollow dock/boardwalk knock"}
    for surf in ("grass", "sand", "stone", "wood"):
        for i in range(1, 5):
            emit(f"sfx/step_{surf}_{i}.ogg", sfx.step(surf, i), "footstep",
                 f"Footstep on {surf} ({desc[surf]}), variation {i}", volume_db=-6.0, peak_limit=-6.0,
                 extra=dict(surface=surf))


def build_car():
    emit("sfx/car_engine_loop.ogg", sfx.car_engine_loop(), "car",
         "Small cute petrol engine idle (45 Hz firing), seamless 2 s loop; pitch_scale 0.8-2.2 for speed",
         loop=True, volume_db=-8.0, peak_limit=-1.0)
    emit("sfx/car_horn.ogg", sfx.car_horn(), "car", "Friendly 'beep beep' horn", volume_db=-6.0, peak_limit=-1.0)
    emit("sfx/car_door.ogg", sfx.car_door(), "car", "Car door close thunk + latch", volume_db=-4.0, peak_limit=-1.0)


def build_ambience():
    A = [
        ("waves", ambience.waves, "Gentle shore waves (~8 s period) with foam hiss", 0.0),
        ("birds_day", ambience.birds_day, "Sparse cheerful songbirds + two distant gulls over light wind", 0.0),
        ("night_crickets", ambience.night_crickets, "Crickets with a distant trill bed and very soft wind", 0.0),
        ("wind", ambience.wind, "Light breeze with soft gusts and leaf rustle", 0.0),
        ("fountain", ambience.fountain, "Small fountain splashing/bubbling", 0.0),
    ]
    for name, fn, desc, vol in A:
        emit(f"ambience/{name}.ogg", fn(), "ambience", desc, loop=True, volume_db=vol, peak_limit=-10.0)


def build_voice():
    blips = voice.all_blips()
    for k in "aeioukmst":
        kind = "vowel" if k in "aeiou" else "consonant+vowel"
        emit(f"voice/blip_{k}.ogg", blips[k], "voice",
             f"Animalese blip '{k}' ({kind}), ~300 Hz f0; pitch_scale 0.7-1.8 per speaker",
             volume_db=-4.0, peak_limit=-6.0, extra=dict(f0_hz=300))


GROUPS = {"music": build_music, "jingles": build_jingles, "ui": build_ui, "steps": build_steps,
          "car": build_car, "ambience": build_ambience, "voice": build_voice}


def main(argv):
    want = argv or list(GROUPS)
    if os.path.exists(MANIFEST):
        try:
            with open(MANIFEST) as f:
                for e in json.load(f).get("files", []):
                    entries[e["path"]] = e
        except Exception:
            pass
    for g in want:
        print(f"== {g}")
        GROUPS[g]()
    files = sorted(entries.values(), key=lambda e: (e["category"], e["path"]))
    total = sum(os.path.getsize(os.path.join(AUDIO, e["path"].replace("res://assets/audio/", "")))
                for e in files if os.path.exists(os.path.join(AUDIO, e["path"].replace("res://assets/audio/", ""))))
    man = {
        "generator": "tools/audio/build_audio.py (procedural synthesis, numpy/scipy, fixed seeds)",
        "format": FMT,
        "sample_rate": SR,
        "notes": ("Music loops are seamless over the whole file (loop_start_s = 0). Main music tracks are "
                  "mastered to about -16.5/-17/-18 LUFS with peaks <= -3 dBFS; play at volume_db 0 and "
                  "crossfade over ~8 s. Keys: day F major, golden Bb major, night F major (compatible). "
                  "volume_db values are suggestions for AudioStreamPlayer.volume_db."),
        "total_bytes": total,
        "files": files,
    }
    with open(MANIFEST, "w") as f:
        json.dump(man, f, indent=2)
    print(f"manifest: {len(files)} files, {total / 1e6:.2f} MB")
    if problems:
        print("PROBLEMS:")
        for p in problems:
            print("  -", p)
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
