#!/usr/bin/env python3
"""Normalize raw mascot frames so the creature is the same torso size and shares
a common feet-baseline + horizontal center across every animation.

Input : mascots_raw/<anim>/frame_*.png  (raw, varying zoom/canvas per clip)
Output: mascots/<anim>/frame_*.png       (uniform canvas, creature anchored)
        mascots/anchor.json              (geometry the WPF popup reads)

The creature body is segmented by its terracotta colour, so confetti specks and
the checkered flag never skew the bbox. Torso widths are hand-measured (legs are
spindly and pose-dependent, so an auto bbox over-counts them).
"""
from PIL import Image, ImageDraw, ImageFilter, ImageOps
import numpy as np, glob, os, json

# Only the wired (choreographed) clips define the shared canvas + anchor, so adding
# spare clips can never shift the live phases. Extras are fitted into that canvas.
CANVAS_ANIMS = ['looking', 'jump', 'confetti', 'flag', 'walking']
ANIMS = CANVAS_ANIMS + ['gym', 'horizontal-jump']
TORSO = {'looking': 184, 'jump': 101, 'confetti': 93, 'flag': 97, 'walking': 170,
         'gym': 153, 'horizontal-jump': 157}  # core: hand-measured torso; extras: matched to looking body height
TARGET = TORSO['looking']  # scale every clip's torso to the (approved) looking size
SRC, DST = 'mascots_raw', 'mascots'

# Uniform creature outline. Colour matches the cream halo the walk-jumper source clips
# already carry, so that accidental halo is absorbed into the ring instead of doubling.
OUTLINE_W = 3
OUTLINE_COLOR = (244, 216, 209)

def _body_mask(im):
    a = np.asarray(im.convert('RGBA')).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    return (al > 128) & (r > 140) & (r - b > 45) & (r > g) & (g > b) & (g > 60)

def _dilate(mask, w):
    im = Image.fromarray((mask * 255).astype('uint8'))
    return np.asarray(im.filter(ImageFilter.MaxFilter(2 * w + 1))) > 127

# Pillow's ImageDraw.floodfill no-ops on single-band 'L' images, so flood on RGB and key
# off a sentinel colour that the plain 0/255 mask never contains.
_SENTINEL = (1, 2, 3)

def _floodfill(mask, seed):
    im = Image.fromarray((mask * 255).astype('uint8')).convert('RGB')
    ImageDraw.floodfill(im, seed, _SENTINEL)
    a = np.asarray(im)
    return (a[..., 0] == 1) & (a[..., 1] == 2) & (a[..., 2] == 3)

def _fill_holes(mask):
    # Eyes are dark pixels enclosed by the body; flood the OUTER background from a corner,
    # so anything unreached is an interior hole that should count as solid body.
    outer = _floodfill(~mask, (0, 0))
    return mask | (~mask & ~outer)

def _creature(mask):
    # Confetti throws off detached body-coloured specks; only the creature itself should be
    # ringed. Flood from the mask's centroid (always inside the dominant blob) to isolate it.
    if not mask.any(): return mask
    ys, xs = np.nonzero(mask)
    cy, cx = int(round(ys.mean())), int(round(xs.mean()))
    if not mask[cy, cx]:
        i = int(np.argmin((ys - cy) ** 2 + (xs - cx) ** 2))
        cy, cx = int(ys[i]), int(xs[i])
    return _floodfill(mask, (cx, cy))

def add_outline(sprite, width=OUTLINE_W, color=OUTLINE_COLOR):
    """Ring the creature's body silhouette with a uniform outline, then re-composite the
    original sprite on top. Confetti specks / flag / eyes survive (they're drawn back over
    the ring); a pre-existing cream halo lands inside the same-coloured ring and disappears.
    Caller must pad the sprite with >=width transparent px so the ring isn't clipped."""
    solid = _creature(_fill_holes(_body_mask(sprite)))
    ring = _dilate(solid, width) & ~solid
    out = np.zeros((*solid.shape, 4), np.uint8)
    out[ring] = (*color, 255)
    res = Image.fromarray(out, 'RGBA')
    res.alpha_composite(sprite.convert('RGBA'))
    return res

def body_bbox(im):
    m = _body_mask(im)
    cols = np.where(m.sum(0) > 10)[0]; rows = np.where(m.sum(1) > 10)[0]
    if not len(cols) or not len(rows): return None
    return (cols.min(), rows.min(), cols.max(), rows.max())

# Anchored coords: torso-center x = 0, feet baseline y = 0. Render a set of clips
# onto one canvas sized to their union extent, anchored so the creature lines up.
def render(data, anims, anchor_path):
    minX = minY = 1e9; maxX = maxY = -1e9
    for d in anims:
        s, cx, y1 = data[d]['scale'], data[d]['ref_cx'], data[d]['ref_y1']
        for im in data[d]['frames']:
            w, h = im.size
            for px, py in [(0, 0), (w, 0), (0, h), (w, h)]:
                X, Y = (px - cx) * s, (py - y1) * s
                minX, maxX = min(minX, X), max(maxX, X)
                minY, maxY = min(minY, Y), max(maxY, Y)
    pad = OUTLINE_W + 1  # room for the ring + rounding slack on every side
    CW, CH = int(np.ceil(maxX - minX)) + 2 * pad, int(np.ceil(maxY - minY)) + 2 * pad
    ax, ay = -minX + pad, -minY + pad
    for d in anims:
        s, cx, y1 = data[d]['scale'], data[d]['ref_cx'], data[d]['ref_y1']
        outdir = f'{DST}/{d}'; os.makedirs(outdir, exist_ok=True)
        ox, oy = round(ax - cx * s), round(ay - y1 * s)
        for f, im in zip(data[d]['files'], data[d]['frames']):
            sc = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.NEAREST)
            sc = add_outline(ImageOps.expand(sc, OUTLINE_W, (0, 0, 0, 0)))
            canvas = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
            canvas.alpha_composite(sc, (ox - OUTLINE_W, oy - OUTLINE_W))
            canvas.save(os.path.join(outdir, os.path.basename(f)))
    cfg = dict(canvasW=CW, canvasH=CH, anchorX=round(ax / CW, 4), anchorY=round(ay / CH, 4))
    os.makedirs(os.path.dirname(anchor_path) or '.', exist_ok=True)
    json.dump(cfg, open(anchor_path, 'w'), indent=2)
    return cfg

def main():
    data = {}
    for d in ANIMS:
        files = sorted(glob.glob(f'{SRC}/{d}/frame_*.png'))
        frames = [Image.open(f).convert('RGBA') for f in files]
        bbs = [body_bbox(im) for im in frames]
        ref = max((bb for bb in bbs if bb), key=lambda bb: bb[3])  # grounded pose = lowest feet
        data[d] = dict(files=files, frames=frames, scale=TARGET / TORSO[d],
                       ref_cx=(ref[0] + ref[2]) / 2.0, ref_y1=ref[3])
    # Core clips share one canvas + anchor (the live choreography swaps between them in a
    # single Image, so they must line up). Spare clips each get their own canvas so a wide
    # pose can't be clipped, with geometry recorded per-dir for if/when they get wired.
    print('core:', render(data, CANVAS_ANIMS, f'{DST}/anchor.json'))
    for d in ANIMS:
        if d not in CANVAS_ANIMS:
            print(f'{d}:', render(data, [d], f'{DST}/{d}/anchor.json'))
    print('scales:', {d: round(data[d]['scale'], 2) for d in ANIMS})

if __name__ == '__main__':
    main()
