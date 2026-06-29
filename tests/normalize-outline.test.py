#!/usr/bin/env python3
"""Unit test for the mascot outline step in tools/normalize-mascots.py.

Run: python3 tests/normalize-outline.test.py
"""
import importlib.util
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("nm", os.path.join(ROOT, "tools", "normalize-mascots.py"))
nm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nm)  # safe: executable pipeline lives under __main__ guard

CREAM = (244, 216, 209)


def _sprite():
    # Terracotta body with a dark eye-hole inside, plus two detached confetti specks:
    # one blue, one the SAME terracotta as the body (the case that was wrongly ringed).
    # 20px transparent margin all round so a 3px ring is never clipped.
    a = np.zeros((60, 60, 4), np.uint8)
    a[20:40, 20:40] = (200, 100, 80, 255)  # body
    a[25:30, 25:30] = (10, 10, 10, 255)    # eye (dark, enclosed by body)
    a[5:8, 5:8] = (50, 80, 220, 255)       # detached blue speck
    a[5:8, 50:53] = (200, 100, 80, 255)    # detached terracotta speck
    return Image.fromarray(a, "RGBA")


def main():
    out = np.asarray(nm.add_outline(_sprite(), 3, CREAM))

    # ring sits just outside the body's left edge (body starts at x=20)
    assert tuple(out[30, 18][:3]) == CREAM and out[30, 18, 3] == 255, out[30, 18]
    # body pixels untouched
    assert tuple(out[30, 30][:3]) == (200, 100, 80), out[30, 30]
    # eye preserved...
    assert tuple(out[27, 27][:3]) == (10, 10, 10), out[27, 27]
    # ...and NOT ringed internally: a body pixel one step outside the eye stays body-coloured
    assert tuple(out[24, 27][:3]) == (200, 100, 80), out[24, 27]
    # detached blue speck preserved, no ring forced onto it
    assert tuple(out[6, 6][:3]) == (50, 80, 220), out[6, 6]
    # detached terracotta speck preserved but NOT ringed (it's not the creature)
    assert tuple(out[6, 51][:3]) == (200, 100, 80), out[6, 51]
    assert out[6, 49, 3] == 0, out[6, 49]  # one px left of the speck: still transparent, no ring
    # far background stays transparent
    assert out[55, 55, 3] == 0, out[55, 55]

    print("ok: normalize-outline")


if __name__ == "__main__":
    main()
