"""
Procedural Cycles materials for the explorer outfit (baked by heroine_pipeline).

All patterns are in object space (bind pose). See materials.py for helpers and
the edge_dist / seam_dist distance fields.
"""

import math

import bpy

from materials import Nodes, hex_lin, stitches


def _along(N, o):
    """A coordinate that varies along both horizontal and vertical seams (stitch dashes)."""
    x, y, z = N.sep(o)[0], N.sep(o)[1], N.sep(o)[2]
    return N.math("ADD", N.math("ADD", N.math("MULTIPLY", x, 0.81), N.math("MULTIPLY", y, 0.59)), z)


def tunic(mat, base=0xB9803C, thread=0xD9B47C):
    N = Nodes(mat)
    o = N.obj()
    z = N.sep(o)[2]
    edge = N.attr("edge_dist")
    seam = N.attr("seam_dist")
    along = _along(N, o)
    c0 = hex_lin(base)
    dark = tuple(c * 0.72 for c in c0)
    faded = tuple(min(1.0, c * 1.18 + 0.02) for c in c0)
    dirt = hex_lin(0x6A5238)
    # Fibre mottling + sun-faded patches.
    mott = N.maprange(N.noise(o, 42.0, detail=8.0, rough=0.62), 0.3, 0.7, 0.0, 0.42)
    col = N.mix(mott, c0, dark)
    fade = N.maprange(N.noise(o, 3.5, detail=2.0), 0.45, 0.75, 0.0, 0.45)
    col = N.mix(fade, col, faded)
    # Grime towards the hem and at the cuffs/collar edges.
    grime = N.math("ADD", N.maprange(z, 0.93, 0.84, 0.0, 0.22), N.maprange(edge, 0.03, 0.0, 0.0, 0.18))
    grime = N.math("MULTIPLY", grime, N.maprange(N.noise(o, 9.0, detail=4.0), 0.35, 0.7, 0.4, 1.0))
    col = N.mix(grime, col, dirt)
    # Hem allowance (double layer) reads slightly darker.
    hem = N.maprange(edge, 0.017, 0.013, 0.0, 0.12)
    col = N.mix(hem, col, dark)
    # Stitching: a hem line 1 cm in, double-needle lines either side of every seam.
    st = N.math("MAXIMUM", stitches(N, edge, 0.0105, along), stitches(N, seam, 0.0032, along))
    col = N.mix(st, col, hex_lin(thread))
    rough = N.math("SUBTRACT", 0.93, N.math("MULTIPLY", st, 0.15))
    # Relief: rolled hem edge + fold line, seam groove with puckering, fine creases.
    h_edge = N.maprange(edge, 0.0, 0.004, 0.55, 1.0)
    h_fold = N.maprange(N.math("ABSOLUTE", N.math("SUBTRACT", edge, 0.0135)), 0.0, 0.0018, -0.45, 0.0)
    h_seam = N.maprange(seam, 0.0, 0.0016, -0.9, 0.0)
    pucker = N.math(
        "MULTIPLY",
        N.math("SINE", N.math("MULTIPLY", along, 2 * math.pi / 0.011)),
        N.maprange(seam, 0.007, 0.001, 0.0, 0.22),
    )
    creases = N.math("MULTIPLY", N.noise(N.scale_vec(o, 1.0, 1.0, 3.0), 28.0, detail=3.0, distortion=0.6), 0.45)
    h = N.math("ADD", N.math("ADD", h_edge, h_fold), N.math("ADD", N.math("ADD", h_seam, pucker), creases))
    h = N.math("SUBTRACT", h, N.math("MULTIPLY", st, 0.35))
    N.output(col, rough, h, bump_strength=1.0, bump_distance=0.0012)


def trousers(mat, base=0x3B4552, thread=0xC79A55):
    N = Nodes(mat)
    o = N.obj()
    s = N.sep(o)
    y, z = s[1], s[2]
    edge = N.attr("edge_dist")
    seam = N.attr("seam_dist")
    along = _along(N, o)
    c0 = hex_lin(base)
    worn = tuple(min(1.0, c * 1.45 + 0.015) for c in c0)
    dark = tuple(c * 0.75 for c in c0)
    mott = N.maprange(N.noise(o, 55.0, detail=8.0, rough=0.65), 0.3, 0.7, 0.0, 0.35)
    col = N.mix(mott, c0, dark)
    # Wear on the knees and thigh fronts (front = −Y), streaky like canvas.
    knee = N.maprange(N.math("ABSOLUTE", N.math("SUBTRACT", z, 0.5)), 0.09, 0.0, 0.0, 1.0)
    thigh = N.maprange(N.math("ABSOLUTE", N.math("SUBTRACT", z, 0.68)), 0.12, 0.0, 0.0, 0.55)
    front = N.maprange(y, -0.03, -0.085, 0.0, 1.0)
    streak = N.maprange(N.noise(N.scale_vec(o, 6.0, 6.0, 0.8), 6.0, detail=5.0), 0.35, 0.75, 0.2, 1.0)
    wear = N.math("MULTIPLY", N.math("MULTIPLY", N.math("MAXIMUM", knee, thigh), front), streak)
    col = N.mix(N.math("MULTIPLY", wear, 0.55), col, worn)
    # Dust towards the boots.
    dust = N.math("MULTIPLY", N.maprange(z, 0.45, 0.31, 0.0, 0.3), N.noise(o, 12.0))
    col = N.mix(dust, col, hex_lin(0x8A7A66))
    # Waistband (top 3.5 cm) + its stitching, double-needle seams in contrasting thread.
    band = N.maprange(N.math("ABSOLUTE", N.math("SUBTRACT", edge, 0.035)), 0.0, 0.0012, 1.0, 0.0)
    st = N.math(
        "MAXIMUM",
        N.math("MAXIMUM", stitches(N, edge, 0.004, along), stitches(N, edge, 0.031, along)),
        N.math("MAXIMUM", stitches(N, seam, 0.003, along), stitches(N, seam, 0.0085, along)),
    )
    col = N.mix(st, col, hex_lin(thread))
    rough = N.math("SUBTRACT", 0.9, N.math("MULTIPLY", st, 0.2))
    h_seam = N.maprange(seam, 0.0, 0.002, -0.8, 0.0)
    h_felled = N.maprange(N.math("ABSOLUTE", N.math("SUBTRACT", seam, 0.0058)), 0.0, 0.004, 0.35, 0.0)
    creases = N.math("MULTIPLY", N.noise(N.scale_vec(o, 1.0, 1.0, 4.0), 22.0, detail=3.0, distortion=0.8), 0.5)
    h = N.math("ADD", N.math("ADD", h_seam, h_felled), N.math("ADD", creases, N.math("MULTIPLY", band, -0.5)))
    h = N.math("SUBTRACT", h, N.math("MULTIPLY", st, 0.3))
    N.output(col, rough, h, bump_strength=1.0, bump_distance=0.0012)


def belt(mat, base=0x4A2F1F, thread=0xC9A06A):
    N = Nodes(mat)
    o = N.obj()
    edge = N.attr("edge_dist")
    along = _along(N, o)
    c0 = hex_lin(base)
    burnished = tuple(c * 0.55 for c in c0)
    col = N.mix(N.maprange(N.noise(o, 60.0, detail=6.0), 0.3, 0.7, 0.0, 0.3), c0, burnished)
    col = N.mix(N.maprange(edge, 0.0035, 0.0005, 0.0, 0.8), col, burnished)
    scuff = N.maprange(N.noise(o, 25.0, detail=6.0), 0.62, 0.75, 0.0, 0.35)
    col = N.mix(scuff, col, hex_lin(0x8C6A4E))
    st = stitches(N, edge, 0.0038, along, period=0.0045, width=0.0006)
    col = N.mix(st, col, hex_lin(thread))
    rough = N.math("ADD", 0.48, N.math("MULTIPLY", N.noise(o, 30.0), 0.18))
    h = N.math("ADD", N.maprange(edge, 0.0, 0.0025, -0.6, 0.0), N.math("MULTIPLY", st, 0.4))
    N.output(col, rough, h, bump_strength=1.0, bump_distance=0.0008)


def boots(mat, centers, base=0x5A3A26, lace=0x3A2618):
    """`centers`: {side: (x, y)} shaft axis of each boot in object space."""
    N = Nodes(mat)
    o = N.obj()
    s = N.sep(o)
    x, y, z = s[0], s[1], s[2]
    edge = N.attr("edge_dist")
    along = _along(N, o)
    c0 = hex_lin(base)
    dark = tuple(c * 0.6 for c in c0)
    col = N.mix(N.maprange(N.noise(o, 48.0, detail=7.0), 0.3, 0.7, 0.0, 0.35), c0, dark)
    # Darkened, dusty foot; scuffed toes.
    col = N.mix(N.maprange(z, 0.06, 0.0, 0.0, 0.35), col, dark)
    toe = N.math("MULTIPLY", N.maprange(y, -0.12, -0.19, 0.0, 1.0), N.maprange(z, 0.09, 0.03, 0.0, 1.0))
    scuff = N.math("MULTIPLY", toe, N.maprange(N.noise(o, 30.0, detail=6.0), 0.5, 0.7, 0.0, 0.6))
    col = N.mix(scuff, col, hex_lin(0x9C8370))
    dust = N.math("MULTIPLY", N.maprange(z, 0.08, 0.01, 0.0, 0.35), N.noise(o, 14.0))
    col = N.mix(dust, col, hex_lin(0x8A7A66))
    # Lacing panel on the front of each shaft: eyelets + criss-cross laces.
    lace_mask = None
    eyelets = None
    for side, (cx, cy) in centers.items():
        lx = N.math("SUBTRACT", x, cx)
        front = N.maprange(y, cy - 0.035, cy - 0.05, 0.0, 1.0)
        panel = N.math("MULTIPLY", front, N.math("MULTIPLY", N.maprange(z, 0.07, 0.085), N.maprange(z, 0.315, 0.3)))
        alx = N.math("ABSOLUTE", lx)
        # laces: two diagonal families inside |lx| < 1.2 cm
        d1 = N.math("FRACT", N.math("DIVIDE", N.math("ADD", z, N.math("MULTIPLY", lx, 0.9)), 0.022))
        d2 = N.math("FRACT", N.math("DIVIDE", N.math("SUBTRACT", z, N.math("MULTIPLY", lx, 0.9)), 0.022))
        l1 = N.maprange(N.math("ABSOLUTE", N.math("SUBTRACT", d1, 0.5)), 0.16, 0.09, 0.0, 1.0)
        l2 = N.maprange(N.math("ABSOLUTE", N.math("SUBTRACT", d2, 0.5)), 0.16, 0.09, 0.0, 1.0)
        laces = N.math("MULTIPLY", N.math("MAXIMUM", l1, l2), N.math("MULTIPLY", panel, N.maprange(alx, 0.013, 0.011)))
        # eyelets: rings at lx = ±1.3 cm every 2.2 cm
        ez = N.math("SUBTRACT", N.math("FRACT", N.math("DIVIDE", N.math("SUBTRACT", z, 0.011), 0.022)), 0.5)
        er = N.math("SQRT", N.math("ADD", N.math("POWER", N.math("MULTIPLY", ez, 0.022), 2.0),
                                     N.math("POWER", N.math("SUBTRACT", alx, 0.0135), 2.0)))
        ring = N.math("MULTIPLY", N.maprange(N.math("ABSOLUTE", N.math("SUBTRACT", er, 0.0024)), 0.0011, 0.0005), panel)
        lace_mask = laces if lace_mask is None else N.math("MAXIMUM", lace_mask, laces)
        eyelets = ring if eyelets is None else N.math("MAXIMUM", eyelets, ring)
    col = N.mix(lace_mask, col, hex_lin(lace))
    col = N.mix(eyelets, col, hex_lin(0x8C8780))
    # Welt stitching above the sole, cuff stitching below the top edge.
    welt = stitches(N, z, 0.017, along, period=0.005, width=0.0008)
    cuff = stitches(N, edge, 0.007, along, period=0.0045)
    st = N.math("MAXIMUM", welt, cuff)
    col = N.mix(st, col, hex_lin(0xB8946A))
    rough = N.math("ADD", N.math("SUBTRACT", 0.5, N.math("MULTIPLY", eyelets, 0.25)), N.math("MULTIPLY", scuff, 0.3))
    # Relief: creases across the ankle, laces raised, cuff roll.
    ankle = N.math("MULTIPLY", N.maprange(N.math("ABSOLUTE", N.math("SUBTRACT", z, 0.115)), 0.04, 0.0),
                   N.math("SINE", N.math("ADD", N.math("MULTIPLY", z, 420.0), N.math("MULTIPLY", N.noise(o, 18.0), 6.0))))
    h = N.math("ADD", N.math("MULTIPLY", ankle, 0.6), N.math("MULTIPLY", lace_mask, 0.9))
    h = N.math("ADD", h, N.maprange(edge, 0.0, 0.004, 0.5, 0.0))
    h = N.math("ADD", h, N.math("MULTIPLY", N.noise(o, 70.0, detail=6.0), 0.25))
    h = N.math("SUBTRACT", h, N.math("MULTIPLY", N.math("MAXIMUM", st, eyelets), 0.4))
    N.output(col, rough, h, bump_strength=1.0, bump_distance=0.0012)


def soles(mat, base=0x2B2622):
    N = Nodes(mat)
    o = N.obj()
    z = N.sep(o)[2]
    c0 = hex_lin(base)
    col = N.mix(N.maprange(N.noise(o, 40.0), 0.3, 0.7, 0.0, 0.3), c0, hex_lin(0x4A423A))
    grooves = N.math("SINE", N.math("MULTIPLY", z, 2 * math.pi / 0.0035))
    h = N.math("MULTIPLY", grooves, 0.5)
    N.output(col, 0.85, h, bump_strength=1.0, bump_distance=0.0006)


def skin(mat, diffuse_image, hair_color=0x3B2A20):
    """MakeHuman diffuse + a scalp tint under the hair (vertex attribute `scalp_tint`)."""
    N = Nodes(mat)
    t = N.n("ShaderNodeTexImage", image=diffuse_image)
    scalp = N.attr("scalp_tint")
    col = N.mix(N.math("MINIMUM", N.math("MULTIPLY", scalp, 1.25), 0.97), t.outputs["Color"], hex_lin(hair_color))
    N.output(col, 0.55, None)
