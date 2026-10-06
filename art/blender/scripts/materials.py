"""
Procedural look-dev + texture baking for the heroine (Blender 4.5, Cycles).

Every garment gets a procedural Cycles material authored in *object space*
(bind pose), so patterns flow continuously across UV seams. Seams, hems and
stitching are driven by distance fields stored as mesh attributes:

  edge_dist   distance (m) along the surface to the nearest open edge — hems,
              cuffs, collars, waistbands, belt edges
  seam_dist   distance (m) to construction seams (side seams, armholes,
              shoulders, in/outseams…)

Bakes (per object, into its UV layout): base colour × ambient occlusion,
tangent-space normal and roughness. `export_material()` then swaps the
procedural tree for a glTF-friendly Principled BSDF using those images.
"""

import heapq
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Vector

# -----------------------------------------------------------------------------
# Distance fields
# -----------------------------------------------------------------------------


def _dijkstra(bm, seeds, max_d):
    dist = [math.inf] * len(bm.verts)
    heap = []
    for i, d0 in seeds:
        if d0 < dist[i]:
            dist[i] = d0
            heapq.heappush(heap, (d0, i))
    bm.verts.ensure_lookup_table()
    while heap:
        d, i = heapq.heappop(heap)
        if d > dist[i] or d > max_d:
            continue
        v = bm.verts[i]
        for e in v.link_edges:
            u = e.other_vert(v)
            nd = d + e.calc_length()
            if nd < dist[u.index]:
                dist[u.index] = nd
                heapq.heappush(heap, (nd, u.index))
    return [min(d, max_d) for d in dist]


def _write_attr(obj, name, values):
    me = obj.data
    if name in me.attributes:
        me.attributes.remove(me.attributes[name])
    at = me.attributes.new(name, "FLOAT", "POINT")
    at.data.foreach_set("value", np.asarray(values, dtype=np.float32))


def shell_split(obj):
    """For a solidified garment: number of outer-shell vertices (solidify appends the
    inner shell after the original vertices) and the boundary (rim) vertices."""
    me = obj.data
    n = len(me.vertices) // 2
    rim = set()
    for e in me.edges:
        a, b = e.vertices
        if abs(a - b) == n:
            rim.add(a)
            rim.add(b)
    if not rim:  # not solidified: use open edges
        bm = bmesh.new()
        bm.from_mesh(me)
        rim = {v.index for v in bm.verts if v.is_boundary}
        bm.free()
        n = len(me.vertices)
    return n, rim


def edge_distance(obj, name="edge_dist", max_d=0.08, select=None):
    """Distance to the garment's edges (hems, cuffs, collars…), optionally only rims passing `select(co)`."""
    _n, rim = shell_split(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    seeds = [(i, 0.0) for i in rim if select is None or select(bm.verts[i].co)]
    d = _dijkstra(bm, seeds, max_d)
    bm.free()
    _write_attr(obj, name, d)
    return d


def seam_distance(obj, seam_value, max_d=0.08):
    """
    Distance to the zero set of a scalar field `seam_value(co) -> signed metres`
    (None outside the seam's domain). Seeds are edges whose endpoints straddle
    zero, at the interpolated crossing distance. Returns the per-vertex list.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    f = [seam_value(v.co) for v in bm.verts]
    seeds = []
    for e in bm.edges:
        a, b = e.verts
        fa, fb = f[a.index], f[b.index]
        if fa is None or fb is None or fa * fb > 0:
            continue
        t = fa / (fa - fb) if fa != fb else 0.5
        L = e.calc_length()
        seeds.append((a.index, abs(t) * L))
        seeds.append((b.index, abs(1 - t) * L))
    d = _dijkstra(bm, seeds, max_d)
    bm.free()
    return d


def write_seams(obj, fields, name="seam_dist", max_d=0.08):
    """Writes min over several seam fields as one distance attribute."""
    if not fields:
        _write_attr(obj, name, [max_d] * len(obj.data.vertices))
        return
    ds = [seam_distance(obj, f, max_d) for f in fields]
    _write_attr(obj, name, [min(v) for v in zip(*ds)])


def garment_uvs(obj, uv_name="BakeUV", margin=0.004):
    """Fresh, non-overlapping UVs for the outer shell (smart project); the inner
    shell and rims collapse into one corner texel (they only ever show a sliver)."""
    n, _rim = shell_split(obj)
    me = obj.data
    if uv_name in me.uv_layers:
        me.uv_layers.remove(me.uv_layers[uv_name])
    for uv in list(me.uv_layers):
        me.uv_layers.remove(uv)
    me.uv_layers.new(name=uv_name)
    bm = bmesh.new()
    bm.from_mesh(me)
    for f in bm.faces:
        f.select = all(v.index < n for v in f.verts)
    bm.to_mesh(me)
    bm.free()
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.view_layer.objects:
        o.select_set(o == obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=margin, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    uv = me.uv_layers[uv_name].data
    for poly in me.polygons:
        if not poly.select:
            for li in poly.loop_indices:
                uv[li].uv = (0.9995, 0.9995)
    # Shrink everything else slightly so nothing touches that corner.
    for poly in me.polygons:
        if poly.select:
            for li in poly.loop_indices:
                uv[li].uv = uv[li].uv * 0.995


# -----------------------------------------------------------------------------
# Node helpers
# -----------------------------------------------------------------------------


class Nodes:
    def __init__(self, mat):
        mat.use_nodes = True
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.x = 0

    def n(self, kind, **kw):
        node = self.nt.nodes.new(kind)
        node.location = (self.x, 0)
        self.x += 160
        for k, v in kw.items():
            if k.startswith("in_"):
                node.inputs[k[3:].replace("_", " ")].default_value = v
            else:
                setattr(node, k, v)
        return node

    def link(self, a, b):
        self.nt.links.new(a, b)
        return b

    # Common building blocks ------------------------------------------------
    def obj(self):
        return self.n("ShaderNodeTexCoord").outputs["Object"]

    def attr(self, name):
        return self.n("ShaderNodeAttribute", attribute_name=name, attribute_type="GEOMETRY").outputs["Fac"]

    def math(self, op, a, b=None, clamp=False):
        m = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        self._in(m.inputs[0], a)
        if b is not None:
            self._in(m.inputs[1], b)
        return m.outputs[0]

    def _in(self, sock, v):
        if isinstance(v, (int, float)):
            sock.default_value = v
        else:
            self.link(v, sock)

    def maprange(self, v, a, b, c=0.0, d=1.0, interp="SMOOTHSTEP"):
        m = self.n("ShaderNodeMapRange", interpolation_type=interp, clamp=True)
        self._in(m.inputs["Value"], v)
        m.inputs["From Min"].default_value = a
        m.inputs["From Max"].default_value = b
        m.inputs["To Min"].default_value = c
        m.inputs["To Max"].default_value = d
        return m.outputs["Result"]

    def noise(self, vec, scale, detail=4.0, rough=0.55, distortion=0.0, dims="3D"):
        t = self.n("ShaderNodeTexNoise", noise_dimensions=dims)
        self.link(vec, t.inputs["Vector"])
        t.inputs["Scale"].default_value = scale
        t.inputs["Detail"].default_value = detail
        t.inputs["Roughness"].default_value = rough
        t.inputs["Distortion"].default_value = distortion
        return t.outputs["Fac"]

    def voronoi(self, vec, scale, feature="F1", out="Distance"):
        t = self.n("ShaderNodeTexVoronoi", feature=feature)
        self.link(vec, t.inputs["Vector"])
        t.inputs["Scale"].default_value = scale
        return t.outputs[out]

    def mix(self, fac, a, b, blend="MIX"):
        m = self.n("ShaderNodeMixRGB", blend_type=blend)
        self._in(m.inputs["Fac"], fac)
        for sock, v in ((m.inputs["Color1"], a), (m.inputs["Color2"], b)):
            if isinstance(v, tuple):
                sock.default_value = (*v[:3], 1.0)
            else:
                self.link(v, sock)
        return m.outputs["Color"]

    def scale_vec(self, vec, sx, sy, sz):
        m = self.n("ShaderNodeVectorMath", operation="MULTIPLY")
        self.link(vec, m.inputs[0])
        m.inputs[1].default_value = (sx, sy, sz)
        return m.outputs["Vector"]

    def sep(self, vec):
        s = self.n("ShaderNodeSeparateXYZ")
        self.link(vec, s.inputs[0])
        return s.outputs

    def output(self, color, roughness, height, bump_strength=1.0, bump_distance=0.001):
        bsdf = self.n("ShaderNodeBsdfPrincipled")
        self._in(bsdf.inputs["Base Color"], color)
        self._in(bsdf.inputs["Roughness"], roughness)
        if height is not None:
            bump = self.n("ShaderNodeBump")
            bump.inputs["Strength"].default_value = bump_strength
            bump.inputs["Distance"].default_value = bump_distance
            self.link(height, bump.inputs["Height"])
            self.link(bump.outputs["Normal"], bsdf.inputs["Normal"])
        out = self.n("ShaderNodeOutputMaterial")
        self.link(bsdf.outputs["BSDF"], out.inputs["Surface"])
        return bsdf


def hex_lin(h):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin((h >> 16) & 255), lin((h >> 8) & 255), lin(h & 255))


def stitches(N, dist_out, offset, along, period=0.004, width=0.0007):
    """Dashed stitch line at `offset` metres from a distance field, dashes along `along`."""
    line = N.maprange(N.math("ABSOLUTE", N.math("SUBTRACT", dist_out, offset)), width, width * 0.4, 0.0, 1.0)
    dash = N.maprange(N.math("SINE", N.math("MULTIPLY", along, 2 * math.pi / period)), -0.1, 0.35, 0.0, 1.0)
    return N.math("MULTIPLY", line, dash)


# -----------------------------------------------------------------------------
# Bake
# -----------------------------------------------------------------------------


def setup_cycles(samples=32):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.render.bake.margin = 6
    sc.render.bake.use_clear = True


def new_image(name, size, non_color=False, alpha=False):
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    im = bpy.data.images.new(name, size, size, alpha=alpha, float_buffer=False)
    im.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return im


def bake(obj, kind, image, samples=1, pass_filter=None):
    """Bakes `kind` (DIFFUSE/NORMAL/AO/ROUGHNESS) of obj's active materials into image."""
    sc = bpy.context.scene
    sc.cycles.samples = samples
    nodes = []
    for slot in obj.material_slots:
        nt = slot.material.node_tree
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = image
        nt.nodes.active = t
        nodes.append((nt, t))
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    kw = dict(type=kind, margin=6, use_clear=True, target="IMAGE_TEXTURES")
    if pass_filter:
        kw["pass_filter"] = pass_filter
    if kind == "NORMAL":
        kw.update(normal_space="TANGENT")
    bpy.ops.object.bake(**kw)
    for nt, t in nodes:
        nt.nodes.remove(t)


def apply_ao_in_shader(mat, ao_image, strength=0.7):
    """Multiplies a baked AO image into the material's base colour (re-bake DIFFUSE afterwards)."""
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    sock = bsdf.inputs["Base Color"]
    src = sock.links[0].from_socket if sock.is_linked else None
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = ao_image
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs["Fac"].default_value = strength
    if src is not None:
        nt.links.new(src, mix.inputs["Color1"])
    else:
        mix.inputs["Color1"].default_value = sock.default_value
    nt.links.new(tex.outputs["Color"], mix.inputs["Color2"])
    nt.links.new(mix.outputs["Color"], sock)


def save_png(image, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()


def export_material(obj, name, albedo, normal=None, roughness=None, metallic=0.0, rough_value=0.6, normal_strength=1.0):
    """Replaces obj's material with a glTF-friendly Principled using baked images."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    N = Nodes(m)
    tc = N.n("ShaderNodeTexImage", image=albedo)
    bsdf = N.n("ShaderNodeBsdfPrincipled")
    N.link(tc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough_value
    if roughness is not None:
        tr = N.n("ShaderNodeTexImage", image=roughness)
        sep = N.n("ShaderNodeSeparateColor")
        N.link(tr.outputs["Color"], sep.inputs["Color"])
        N.link(sep.outputs["Green"], bsdf.inputs["Roughness"])
    if normal is not None:
        tn = N.n("ShaderNodeTexImage", image=normal)
        nm = N.n("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_strength
        N.link(tn.outputs["Color"], nm.inputs["Color"])
        N.link(nm.outputs["Normal"], bsdf.inputs["Normal"])
    out = N.n("ShaderNodeOutputMaterial")
    N.link(bsdf.outputs["BSDF"], out.inputs["Surface"])
    obj.data.materials.clear()
    obj.data.materials.append(m)
    return m


def inner_uvs_from_outer(obj, uv_name="BakeUV"):
    """After baking: give the inner shell (and rims) the UVs of the matching outer
    faces, so the inside of cuffs, collars and hems shows the same fabric."""
    n, _rim = shell_split(obj)
    me = obj.data
    uv = me.uv_layers[uv_name].data
    outer_by_key = {}
    vert_uv = {}
    for p in me.polygons:
        vs = list(p.vertices)
        if all(v < n for v in vs):
            outer_by_key[tuple(sorted(vs))] = p
            for li, v in zip(p.loop_indices, vs):
                vert_uv.setdefault(v, uv[li].uv.copy())
    for p in me.polygons:
        vs = list(p.vertices)
        if all(v < n for v in vs):
            continue
        if all(v >= n for v in vs):
            src = outer_by_key.get(tuple(sorted(v - n for v in vs)))
            if src is not None:
                m = {v: uv[li].uv.copy() for li, v in zip(src.loop_indices, src.vertices)}
                for li, v in zip(p.loop_indices, vs):
                    uv[li].uv = m.get(v - n, vert_uv.get(v - n, uv[li].uv))
                continue
        for li, v in zip(p.loop_indices, vs):
            o = v if v < n else v - n
            if o in vert_uv:
                uv[li].uv = vert_uv[o]
