"""
Heroine pipeline — Blender 4.5 + MPFB 2 (MakeHuman, CC0 output).

    Blender ▸ Scripting ▸ open this file ▸ Run Script
    (or: blender --python art/blender/scripts/heroine_pipeline.py)

Stages (each saves a .blend in art/blender/):
  1. source   MPFB human from CONFIG (body shape, face, skin, eyes, hair…) on
              MPFB's game-engine rig            → heroine_mpfb_source.blend
              This file stays editable in MPFB: tweak the face/body there by
              hand if you prefer, then run stage 2 only.
  2. game     bake shape → pose into the game's bind pose (arms relaxed,
              legs straight, fingers curled) → 17-joint game skeleton with
              merged weights + ponytail spring joints → explorer outfit →
              texture bakes → coverage → glTF export
              → heroine_game.blend + public/assets/characters/heroine.glb

Tailoring the heroine to a real person = edit CONFIG and re-run. Everything
downstream (rig, garments, textures, game integration) adapts to the new body.

Requirements: the MPFB extension and the CC0 asset packs "makehuman_system_assets",
"hair01", "eyebrows01", "eyelashes01" (MPFB ▸ Apply assets ▸ Load pack).
"""

import importlib.util
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = "/Users/marcoleite/Documents/test_ai_agent-1"
SCRIPTS = os.path.join(ROOT, "art", "blender", "scripts")
SOURCE_BLEND = os.path.join(ROOT, "art", "blender", "heroine_mpfb_source.blend")
GAME_BLEND = os.path.join(ROOT, "art", "blender", "heroine_game.blend")
GLB = os.path.join(ROOT, "public", "assets", "characters", "heroine.glb")

# -----------------------------------------------------------------------------
# CONFIG — who she is
# -----------------------------------------------------------------------------
CONFIG = dict(
    height=1.68,  # metres, top of the head
    macro=dict(
        gender=0.0, age=0.5, muscle=0.55, weight=0.45, proportions=0.75, height=0.5,
        cupsize=0.5, firmness=0.6, race=dict(asian=0.05, caucasian=0.9, african=0.05),
    ),
    # MPFB targets (data/targets/<group>/<name>.target.gz) and weights.
    face={
        "head/head-oval": 0.5,
        "chin/chin-width-decr": 0.25, "chin/chin-prominent-incr": 0.15, "chin/chin-height-decr": 0.15,
        "cheek/l-cheek-bones-incr": 0.3, "cheek/r-cheek-bones-incr": 0.3,
        "cheek/l-cheek-volume-incr": 0.2, "cheek/r-cheek-volume-incr": 0.2,
        "eyes/l-eye-scale-incr": 0.3, "eyes/r-eye-scale-incr": 0.3,
        "eyes/l-eye-corner2-up": 0.25, "eyes/r-eye-corner2-up": 0.25,
        "eyes/l-eye-bag-decr": 0.5, "eyes/r-eye-bag-decr": 0.5,
        "mouth/mouth-upperlip-volume-incr": 0.35, "mouth/mouth-lowerlip-volume-incr": 0.35,
        "mouth/mouth-cupidsbow-incr": 0.3, "mouth/mouth-angles-up": 0.15,
        "nose/nose-scale-horiz-decr": 0.2, "nose/nose-point-width-decr": 0.3, "nose/nose-point-up": 0.15,
        "nose/nose-volume-decr": 0.15, "nose/nose-flaring-decr": 0.25,
        "eyebrows/eyebrows-angle-up": 0.15,
        "neck/neck-scale-horiz-decr": 0.15,
    },
    skin="young_caucasian_female/young_caucasian_female.mhmat",
    skin_diffuse="young_lightskinned_female_diffuse.png",
    eyes="high-poly/high-poly.mhclo",
    eye_texture="brown_eye.png",
    eyebrows="eyebrow001/eyebrow001.mhclo",
    eyelashes="eyelashes01/eyelashes01.mhclo",
    hair="ponytail01/ponytail01.mhclo",
    hair_color=0x3B2A20,  # scalp tint under the hair (match the hair texture)
    # Ponytail spring joints (bind-pose points, Blender space: −Y = front).
    ponytail=[(0, 0.095, 1.565), (0, 0.107, 1.49), (0, 0.102, 1.415), (0, 0.088, 1.345), (0, 0.079, 1.300)],
    arm_abduction=0.12,  # rad, arms away from the body in the bind pose
)


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(SCRIPTS, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def _mpfb():
    from bl_ext.user_default.mpfb.services.humanservice import HumanService
    from bl_ext.user_default.mpfb.services.locationservice import LocationService
    from bl_ext.user_default.mpfb.services.targetservice import TargetService

    return HumanService, LocationService, TargetService


# -----------------------------------------------------------------------------
# Stage 1 — MPFB source
# -----------------------------------------------------------------------------
def _measure_height(bm):
    for m in bm.modifiers:
        m.show_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    ev = bm.evaluated_get(dg)
    me = ev.to_mesh()
    vg = bm.vertex_groups["body"].index
    top = max((bm.matrix_world @ v.co).z for v in me.vertices if any(g.group == vg for g in v.groups))
    ev.to_mesh_clear()
    for m in bm.modifiers:
        m.show_viewport = True
    return top


def stage_source(cfg=CONFIG):
    HumanService, LocationService, TargetService = _mpfb()
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    probe = HumanService.create_human(scale=0.1, macro_detail_dict=cfg["macro"])
    scale = 0.1 * cfg["height"] / _measure_height(probe)
    bpy.data.objects.remove(probe, do_unlink=True)
    bm = HumanService.create_human(scale=scale, macro_detail_dict=cfg["macro"])
    bm.name = "Heroine"
    td = LocationService.get_mpfb_data("targets")
    for t, w in cfg["face"].items():
        TargetService.load_target(bm, os.path.join(td, t + ".target.gz"), weight=w)
    HumanService.add_builtin_rig(bm, "game_engine", import_weights=True)
    ud = LocationService.get_user_data()
    HumanService.set_character_skin(os.path.join(ud, "skins", cfg["skin"]), bm, skin_type="ENHANCED_SSS")
    for kind, rel in (("Eyes", cfg["eyes"]), ("Eyebrows", cfg["eyebrows"]), ("Eyelashes", cfg["eyelashes"]),
                      ("Teeth", "teeth_base/teeth_base.mhclo"), ("Tongue", "tongue01/tongue01.mhclo"), ("Hair", cfg["hair"])):
        folder = {"Eyes": "eyes", "Eyebrows": "eyebrows", "Eyelashes": "eyelashes", "Teeth": "teeth", "Tongue": "tongue", "Hair": "hair"}[kind]
        HumanService.add_mhclo_asset(os.path.join(ud, folder, rel), bm, asset_type=kind, subdiv_levels=0, material_type="MAKESKIN")
    os.makedirs(os.path.dirname(SOURCE_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE_BLEND, copy=True)
    return bm


# -----------------------------------------------------------------------------
# Stage 2 — game asset
# -----------------------------------------------------------------------------
def _upd():
    bpy.context.view_layer.update()


def pose_to_bind(rig, cfg=CONFIG):
    """Arms relaxed (thumbs forward), legs straight, fingers gently curled."""
    for p in rig.pose.bones:
        p.rotation_mode = "QUATERNION"
        p.rotation_quaternion = Quaternion()
        p.location = (0, 0, 0)
    _upd()
    A = cfg["arm_abduction"]
    dirs = {}
    for s, sx in (("l", 1), ("r", -1)):
        arm = Vector((sx * math.sin(A), -0.02, -math.cos(A)))
        dirs[f"upperarm_{s}"] = dirs[f"lowerarm_{s}"] = arm
        dirs[f"thigh_{s}"] = dirs[f"calf_{s}"] = Vector((0, 0, -1))
    follow = lambda n: any(n.startswith(p) for p in ("hand", "index", "middle", "ring", "pinky", "thumb"))
    bones = sorted(rig.data.bones, key=lambda b: len(b.parent_recursive))
    desired, rot = {}, {}
    for b in bones:
        head = desired[b.parent.name] @ (b.parent.matrix_local.inverted() @ b.head_local) if b.parent else b.head_local.copy()
        if b.name in dirs:
            R = (b.tail_local - b.head_local).normalized().rotation_difference(dirs[b.name].normalized()).to_matrix()
        elif follow(b.name):
            R = rot[b.parent.name]
        else:
            R = Matrix.Identity(3)
        rot[b.name] = R
        M4 = (R @ b.matrix_local.to_3x3()).to_4x4()
        M4.translation = head
        desired[b.name] = M4
    for b in bones:
        rig.pose.bones[b.name].matrix = desired[b.name]
        _upd()
    pb, W = rig.pose.bones, rig.matrix_world

    def twist(name, ang):
        b = pb[name]
        axis = (b.tail - b.head).normalized()
        T = Matrix.Translation(b.head)
        b.matrix = T @ Matrix.Rotation(ang, 4, axis) @ T.inverted() @ b.matrix.copy()
        _upd()

    for s in "lr":  # pronate so the thumbs point forward
        t0 = (W @ pb[f"thumb_03_{s}"].tail).copy()
        twist(f"lowerarm_{s}", 0.3)
        t1 = (W @ pb[f"thumb_03_{s}"].tail).copy()
        twist(f"lowerarm_{s}", -0.3)
        sign = 1 if t1.y < t0.y else -1
        twist(f"upperarm_{s}", sign * 0.25)
        twist(f"lowerarm_{s}", sign * 0.45)
    amounts = {"index": (0.25, 0.35, 0.25), "middle": (0.3, 0.42, 0.28), "ring": (0.34, 0.46, 0.3), "pinky": (0.38, 0.5, 0.32)}
    for s in "lr":
        across = ((W @ pb[f"index_01_{s}"].head) - (W @ pb[f"pinky_01_{s}"].head)).normalized()
        down = ((W @ pb[f"middle_01_{s}"].head) - (W @ pb[f"hand_{s}"].head)).normalized()
        palm = Vector((-1 if s == "l" else 1, 0, 0))

        def curl(b, axis_world, a):
            base = b.rotation_quaternion.copy()
            Rb = (W @ b.matrix).to_3x3().normalized()
            best = None
            for sign in (1, -1):
                ax = (Rb.inverted() @ (axis_world * sign)).normalized()
                t0 = (W @ b.tail).copy()
                b.rotation_quaternion = base @ Quaternion(ax, a)
                _upd()
                sc = ((W @ b.tail) - t0).dot(palm)
                b.rotation_quaternion = base
                _upd()
                if best is None or sc > best[0]:
                    best = (sc, ax)
            b.rotation_quaternion = base @ Quaternion(best[1], a)
            _upd()

        for f, angs in amounts.items():
            for seg, a in zip(("01", "02", "03"), angs):
                curl(pb[f"{f}_{seg}_{s}"], across, a)
        for seg, a in zip(("02", "03"), (0.15, 0.2)):
            curl(pb[f"thumb_{seg}_{s}"], across.cross(down), a)


def bake_pose(rig):
    meshes = [o for o in rig.children if o.type == "MESH"]
    for o in meshes:
        with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o], selected_editable_objects=[o]):
            for m in list(o.modifiers):
                if m.type in ("MASK", "ARMATURE"):
                    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.context.view_layer.objects.active = rig
    for o in bpy.context.view_layer.objects:
        o.select_set(o == rig)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return meshes


JOINT_MAP = {  # MPFB game_engine bone → {game joint: share}
    "Root": {"pelvis": 1}, "pelvis": {"pelvis": 1}, "spine_01": {"pelvis": 0.5, "spine": 0.5}, "spine_02": {"spine": 1},
    "spine_03": {"chest": 1}, "neck_01": {"neck": 1}, "head": {"head": 1},
}
for _s, _S in (("l", "L"), ("r", "R")):
    JOINT_MAP.update({
        f"clavicle_{_s}": {"chest": 1}, f"upperarm_{_s}": {f"upperArm{_S}": 1}, f"lowerarm_{_s}": {f"foreArm{_S}": 1},
        f"hand_{_s}": {f"hand{_S}": 1}, f"thigh_{_s}": {f"thigh{_S}": 1}, f"calf_{_s}": {f"shin{_S}": 1},
        f"foot_{_s}": {f"foot{_S}": 1}, f"ball_{_s}": {f"foot{_S}": 1},
    })
    for _f in ("index", "middle", "ring", "pinky", "thumb"):
        for _k in ("01", "02", "03"):
            JOINT_MAP[f"{_f}_{_k}_{_s}"] = {f"hand{_S}": 1}


def build_game_rig(mh, cfg=CONFIG):
    from collections import defaultdict

    W = mh.matrix_world
    H = lambda n: W @ mh.data.bones[n].head_local
    J = {"pelvis": (None, H("pelvis")), "spine": ("pelvis", H("spine_02")), "chest": ("spine", H("spine_03")),
         "neck": ("chest", H("neck_01")), "head": ("neck", H("head"))}
    for s, S in (("l", "L"), ("r", "R")):
        J[f"upperArm{S}"] = ("chest", H(f"upperarm_{s}"))
        J[f"foreArm{S}"] = (f"upperArm{S}", H(f"lowerarm_{s}"))
        J[f"hand{S}"] = (f"foreArm{S}", H(f"hand_{s}"))
        J[f"thigh{S}"] = ("pelvis", H(f"thigh_{s}"))
        J[f"shin{S}"] = (f"thigh{S}", H(f"calf_{s}"))
        J[f"foot{S}"] = (f"shin{S}", H(f"foot_{s}"))
    tails = {"pelvis": "spine", "spine": "chest", "chest": "neck", "neck": "head"}
    for S in "LR":
        tails.update({f"upperArm{S}": f"foreArm{S}", f"foreArm{S}": f"hand{S}", f"thigh{S}": f"shin{S}", f"shin{S}": f"foot{S}"})
    arm = bpy.data.armatures.new("HeroineSkeleton")
    rig = bpy.data.objects.new("HeroineRig", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for n, (_p, h) in J.items():
        eb[n] = arm.edit_bones.new(n)
        eb[n].head = h
    for n, b in eb.items():
        if n in tails:
            b.tail = J[tails[n]][1]
        elif n.startswith("hand"):
            b.tail = b.head + (b.head - J["foreArm" + n[-1]][1]).normalized() * 0.08
        elif n.startswith("foot"):
            b.tail = b.head + Vector((0, -0.12, -0.05))
        else:
            b.tail = b.head + Vector((0, 0, 0.2))
    for n, (p, _h) in J.items():
        if p:
            eb[n].parent = eb[p]
    # Ponytail spring joints.
    pts = [Vector(p) for p in cfg["ponytail"]]
    prev = eb["head"]
    for i in range(len(pts) - 1):
        b = arm.edit_bones.new(f"hair{i}")
        b.head, b.tail, b.parent, b.use_connect = pts[i], pts[i + 1], prev, i > 0
        prev = b
    bpy.ops.object.mode_set(mode="OBJECT")
    # Merge MPFB weights into the game joints.
    names = [b.name for b in arm.bones]
    for o in [c for c in mh.children if c.type == "MESH"]:
        idx = {g.index: g.name for g in o.vertex_groups}
        new = defaultdict(dict)
        for v in o.data.vertices:
            acc = defaultdict(float)
            for g in v.groups:
                for gb, f in JOINT_MAP.get(idx[g.group], {}).items():
                    acc[gb] += g.weight * f
            if not acc:
                acc["head" if o.name != "Heroine" else "pelvis"] = 1.0
            top = sorted(acc.items(), key=lambda x: -x[1])[:4]
            tot = sum(w for _, w in top)
            for gb, w in top:
                new[gb][v.index] = w / tot
        for g in list(o.vertex_groups):
            if g.name in JOINT_MAP:
                o.vertex_groups.remove(g)
        for gb in names:
            if gb in new:
                vg = o.vertex_groups.new(name=gb)
                for vi, w in new[gb].items():
                    vg.add([vi], w, "REPLACE")
        o.parent = rig
        o.matrix_parent_inverse.identity()
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.object = rig
        if not any(m.type == "ARMATURE" for m in o.modifiers):
            o.modifiers.new("Armature", "ARMATURE").object = rig
    bpy.data.objects.remove(mh, do_unlink=True)
    return rig, pts


def weight_ponytail(hair, body, pts):
    from mathutils.bvhtree import BVHTree

    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    hair.vertex_groups.clear()
    n = len(pts) - 1
    groups = {name: hair.vertex_groups.new(name=name) for name in ["head"] + [f"hair{i}" for i in range(n)]}
    tie_z = pts[0].z
    for v in hair.data.vertices:
        p = hair.matrix_world @ v.co
        _loc, _n, _i, off = bvh.find_nearest(p)
        best = (1e9, 0.0)
        for i in range(n):
            a, b = pts[i], pts[i + 1]
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
            d = (a + ab * t - p).length
            if d < best[0]:
                best = (d, i + t)
        tail = max(0.0, min(1.0, ((off or 0) - 0.012) / 0.02)) * max(0.0, min(1.0, (tie_z + 0.02 - p.z) / 0.03))
        if tail <= 0:
            groups["head"].add([v.index], 1.0, "REPLACE")
            continue
        i = min(n - 1, int(best[1]))
        f = best[1] - i
        if 1 - tail > 0:
            groups["head"].add([v.index], 1 - tail, "REPLACE")
        groups[f"hair{i}"].add([v.index], (1 - f) * tail if i < n - 1 else tail, "ADD")
        if i < n - 1 and f > 0:
            groups[f"hair{i + 1}"].add([v.index], f * tail, "ADD")


def split_cornea(eyes):
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(eyes.data)
    bm.verts.ensure_lookup_table()
    seen, comps = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        while stack:
            u = stack.pop()
            if u.index in seen:
                continue
            seen.add(u.index)
            comp.append(u.index)
            stack.extend(e.other_vert(u) for e in u.link_edges)
        comps.append(comp)
    cornea = set()
    for sx in (1, -1):
        side = sorted([c for c in comps if bm.verts[c[0]].co.x * sx > 0], key=lambda c: min(bm.verts[i].co.y for i in c))
        cornea.update(side[0])
    bm.free()
    for p in eyes.data.polygons:
        p.select = all(v in cornea for v in p.vertices)
    bpy.context.view_layer.objects.active = eyes
    for o in bpy.context.view_layer.objects:
        o.select_set(o == eyes)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    c = [o for o in bpy.context.selected_objects if o != eyes][0]
    c.name = c.data.name = "Cornea"
    return c


def simple_materials(cfg=CONFIG):
    def pbr(obj, name, image=None, rough=0.5, alpha=False, alpha_value=1.0):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        b = nt.nodes["Principled BSDF"]
        b.inputs["Roughness"].default_value = rough
        b.inputs["Alpha"].default_value = alpha_value
        if image:
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images[image]
            nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
            if alpha:
                nt.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
        obj.data.materials.clear()
        obj.data.materials.append(m)

    O = bpy.data.objects
    pbr(O["Eyes"], "Eyes", cfg["eye_texture"], rough=0.08)
    pbr(O["Cornea"], "Cornea", rough=0.02, alpha_value=0.12)
    pbr(O["Eyebrows"], "Eyebrows", os.path.basename(cfg["eyebrows"]).replace(".mhclo", ".png"), 0.8, True)
    pbr(O["Eyelashes"], "Eyelashes", os.path.basename(cfg["eyelashes"]).replace(".mhclo", ".png"), 0.8, True)
    hair_img = [im.name for im in bpy.data.images if im.name.startswith(os.path.basename(cfg["hair"]).replace(".mhclo", ""))]
    pbr(O["Hair"], "Hair", hair_img[0] if hair_img else None, 0.45, True)
    pbr(O["Teeth"], "Teeth", "teeth.png", 0.25)
    pbr(O["Tongue"], "Tongue", "tongue01_diffuse.png", 0.4)
    for n in ("teeth.png", "tongue01_diffuse.png"):
        if n in bpy.data.images and bpy.data.images[n].size[0] > 512:
            bpy.data.images[n].scale(512, 512)
    O["Buckle"].data.materials.clear()
    m = bpy.data.materials.new("M_Brass")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.43, 0.27, 0.095, 1)
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = 0.35
    O["Buckle"].data.materials.append(m)


def coverage(body, garments, channel=0):
    """Per-vertex: 1 where the outfit covers the skin (ray along the normal hits cloth), eroded 2 rings."""
    import bmesh
    from mathutils.bvhtree import BVHTree

    dg = bpy.context.evaluated_depsgraph_get()
    trees = [BVHTree.FromObject(g, dg, deform=False) for g in garments]
    groups = {g.index: g.name for g in body.vertex_groups}
    # Never hidden: hands hang near hems; forearms slide out of the sleeves when the elbows bend.
    keep = {"head", "handL", "handR", "foreArmL", "foreArmR"}

    def dominant(v):
        best = max(v.groups, key=lambda g: g.weight, default=None)
        return groups.get(best.group) if best else None

    never = {v.index for v in body.data.vertices if dominant(v) in keep}
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.normal_update()
    cov = [
        0.0 if v.index in never else
        1.0 if any(t.ray_cast(v.co - v.normal * 0.002, v.normal, 0.045)[0] is not None for t in trees) else 0.0
        for v in bm.verts
    ]
    nb = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    for _ in range(2):
        cov = [min([cov[i]] + [cov[j] for j in nb[i]]) for i in range(len(cov))]
    bm.free()
    me = body.data
    at = me.attributes.get("_COVER")
    if at is None:
        at = me.attributes.new("_COVER", "FLOAT_COLOR", "POINT")
        for d in at.data:
            d.color = (0.0, 0.0, 0.0, 0.0)  # (new colour attributes default to alpha 1)
    for i, c in enumerate(cov):
        col = list(at.data[i].color)
        col[channel] = c
        at.data[i].color = col


def export_glb(rig, path=GLB):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(False)
    rig.select_set(True)
    for c in rig.children:
        c.hide_viewport = False
        c.hide_set(False)
        c.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_skins=True,
        export_animations=False, export_yup=True, export_texcoords=True, export_normals=True, export_tangents=True,
        export_materials="EXPORT", export_morph=False, export_extras=False, export_attributes=True,
        export_image_format="WEBP", export_image_quality=88, export_leaf_bone=False, export_def_bones=False,
        export_vertex_color="NONE", export_all_vertex_colors=False,
    )
    return path


def _append_source():
    """Brings the MPFB source objects into a clean current scene. (Appending keeps the
    script's context valid, unlike opening the file.)"""
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)
    with bpy.data.libraries.load(SOURCE_BLEND, link=False) as (src, dst):
        dst.objects = list(src.objects)
    for o in dst.objects:
        if o is not None:
            bpy.context.scene.collection.objects.link(o)
    bpy.context.view_layer.update()


def stage_game(cfg=CONFIG, textures=True):
    G = _load("garments")
    _load("materials")
    _load("outfit_looks")
    HT = _load("heroine_textures")
    EO = _load("explorer_outfit")
    HumanService, _LS, TargetService = _mpfb()
    _append_source()
    mh = bpy.data.objects["Heroine.rig"]
    body = bpy.data.objects["Heroine"]
    TargetService.bake_targets(body)
    pose_to_bind(mh, cfg)
    bake_pose(mh)
    rig, pts = build_game_rig(mh, cfg)
    names = {"Heroine": "Body", "high-poly": "Eyes", "eyebrow": "Eyebrows", "eyelashes": "Eyelashes",
             "ponytail": "Hair", "teeth": "Teeth", "tongue": "Tongue"}
    for o in list(rig.children):
        for key, new in names.items():
            if o.name == key or o.name.startswith("Heroine." + key):
                o.name = new
    hair = next(o for o in rig.children if o.name.startswith("Hair") or o.name.startswith("Heroine."))
    hair.name = "Hair"
    body = bpy.data.objects["Body"]
    weight_ponytail(hair, body, pts)
    split_cornea(bpy.data.objects["Eyes"])
    outfit = EO.build(body, rig)
    simple_materials(cfg)
    if textures:
        HT.bake_outfit()
        HT.bake_skin(diffuse=cfg["skin_diffuse"], hair_color=cfg["hair_color"])
    coverage(body, [outfit[n] for n in ("Tunic", "Trousers", "Boots", "Belt", "Soles")])
    for o in rig.children:
        if o.type == "MESH":
            for p in o.data.polygons:
                p.use_smooth = True
    export_glb(rig)
    bpy.ops.wm.save_as_mainfile(filepath=GAME_BLEND, copy=True)
    return rig


if __name__ == "__main__":
    stage = os.environ.get("HEROINE_STAGE", "all")
    if stage in ("all", "source"):
        stage_source()
    if stage in ("all", "game"):
        stage_game()
