"""
Texture stage of the heroine pipeline: seam/hem distance fields, bake UVs,
procedural look-dev materials, Cycles bakes and glTF-ready materials.

    import heroine_textures as HT
    HT.bake_outfit()                # all garments
    HT.bake_garment("Tunic")        # one garment
    HT.bake_skin()                  # body albedo: MakeHuman skin + scalp tint + AO

Textures are written to art/blender/textures/ (PNG, kept as source art) and
embedded in the GLB by the exporter (as WebP).
"""

import os

import bpy
from mathutils.bvhtree import BVHTree

import materials as M
import outfit_looks as L

ROOT = "/Users/marcoleite/Documents/test_ai_agent-1"
TEX_DIR = os.path.join(ROOT, "art", "blender", "textures")


# -----------------------------------------------------------------------------
# Seams per garment (zero sets of smooth fields, in bind-pose object space)
# -----------------------------------------------------------------------------
def _tunic_seams():
    side = lambda co: co.y + 0.025                                      # side seams (+ sleeve seams)
    armhole = lambda co: None if co.z < 1.13 else abs(co.x) - 0.168     # sleeve set-in seams
    shoulder = lambda co: None if (co.z < 1.34 or abs(co.x) > 0.175) else co.y + 0.03
    return [side, armhole, shoulder]


def _trouser_seams():
    side = lambda co: None if co.z > 1.0 else co.y + 0.02               # outseams + inseams
    rise = lambda co: None if co.z < 0.72 or abs(co.x) > 0.08 else co.x  # front fly / back rise
    return [side, rise]


GARMENTS = {
    "Tunic": dict(look=L.tunic, seams=_tunic_seams, size=2048),
    "Trousers": dict(look=L.trousers, seams=_trouser_seams, size=2048),
    "Belt": dict(look=L.belt, seams=None, size=1024),
    "Boots": dict(look="boots", seams=None, size=2048),
    "Soles": dict(look=L.soles, seams=None, size=512, edges=False),
}


def _boot_centers(obj):
    """Shaft axis (x, y) of each boot at mid-shaft height."""
    out = {}
    for side, sx in (("L", 1), ("R", -1)):
        pts = [v.co for v in obj.data.vertices if abs(v.co.z - 0.22) < 0.01 and v.co.x * sx > 0]
        out[side] = (sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts))
    return out


def _hide_helpers():
    for o in bpy.data.objects:
        if o.name.startswith("_"):
            o.hide_render = True


def bake_garment(name, ao_strength=0.7):
    cfg = GARMENTS[name]
    obj = bpy.data.objects[name]
    _hide_helpers()
    M.setup_cycles()
    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.light_settings.distance = 0.08
    # Distance fields + UVs.
    if cfg.get("edges", True):
        M.edge_distance(obj)
    M.write_seams(obj, cfg["seams"]() if cfg["seams"] else [])
    M.garment_uvs(obj)
    # Look-dev material.
    look = bpy.data.materials.get(f"Look_{name}") or bpy.data.materials.new(f"Look_{name}")
    if cfg["look"] == "boots":
        L.boots(look, _boot_centers(obj))
    else:
        cfg["look"](look)
    obj.data.materials.clear()
    obj.data.materials.append(look)
    size = cfg["size"]
    ao = M.new_image(f"T_{name}_ao", max(256, size // 2), non_color=True)
    M.bake(obj, "AO", ao, samples=24)
    M.apply_ao_in_shader(look, ao, strength=ao_strength)
    albedo = M.new_image(f"T_{name}_albedo", size)
    M.bake(obj, "DIFFUSE", albedo, samples=4, pass_filter={"COLOR"})
    normal = M.new_image(f"T_{name}_normal", size, non_color=True)
    M.bake(obj, "NORMAL", normal, samples=2)
    rough = M.new_image(f"T_{name}_rough", max(256, size // 2), non_color=True)
    M.bake(obj, "ROUGHNESS", rough, samples=1)
    for im in (albedo, normal, rough, ao):
        M.save_png(im, os.path.join(TEX_DIR, im.name + ".png"))
    M.inner_uvs_from_outer(obj)
    M.export_material(obj, f"M_{name}", albedo, normal, rough)
    return obj


def bake_outfit():
    for name in GARMENTS:
        if name in bpy.data.objects:
            bake_garment(name)


# -----------------------------------------------------------------------------
# Skin
# -----------------------------------------------------------------------------
def scalp_mask(body, hair, reach=0.07, blur=6):
    """Per-vertex 0..1: skin under the hair cap (tinted with the hair colour)."""
    import bmesh

    dg = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(hair, dg, deform=False)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.normal_update()
    vals = []
    for v in bm.verts:
        # Under the cap: the hair is hit looking straight out of the skin. (Rays, not nearest
        # distance — cards hovering over the forehead or ears must not tint them.)
        loc, _n, _i, _d = tree.ray_cast(v.co - v.normal * 0.004, v.normal, reach)
        vals.append(1.0 if loc is not None else 0.0)
    nb = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    for _ in range(blur):
        vals = [0.5 * vals[i] + 0.5 * (sum(vals[j] for j in nb[i]) / len(nb[i]) if nb[i] else vals[i]) for i in range(len(vals))]
    bm.free()
    M._write_attr(body, "scalp_tint", vals)
    return vals


def bake_skin(diffuse="young_lightskinned_female_diffuse.png", size=2048, hair_color=0x3B2A20, ao_strength=0.55):
    body = bpy.data.objects["Body"]
    hair = bpy.data.objects["Hair"]
    _hide_helpers()
    M.setup_cycles()
    bpy.context.scene.world.light_settings.distance = 0.06
    scalp_mask(body, hair)
    look = bpy.data.materials.get("Look_Skin") or bpy.data.materials.new("Look_Skin")
    L.skin(look, bpy.data.images[diffuse], hair_color=hair_color)
    body.data.materials.clear()
    body.data.materials.append(look)
    # The body keeps MakeHuman's UV layout (single shell, no overlaps).
    ao = M.new_image("T_Skin_ao", size // 2, non_color=True)
    M.bake(body, "AO", ao, samples=24)
    M.apply_ao_in_shader(look, ao, strength=ao_strength)
    albedo = M.new_image("T_Skin_albedo", size)
    M.bake(body, "DIFFUSE", albedo, samples=4, pass_filter={"COLOR"})
    for im in (albedo, ao):
        M.save_png(im, os.path.join(TEX_DIR, im.name + ".png"))
    M.export_material(body, "Skin", albedo, rough_value=0.55)
    return body
