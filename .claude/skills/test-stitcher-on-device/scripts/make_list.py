#!/usr/bin/env python3
"""Generate stitch_cli's input list for a capture session.

When the folder contains session.json (written by the app at the end of a
capture), rotations come from the **actually measured quaternions** and the
capture order is kept: the stitching is replayed exactly.

Otherwise (older sessions), rotations are rebuilt from the grid's target
angles (approximation: the real heading may differ). Grids: keep in sync with
lib/core/constants/app_constants.dart.

Conversions: same formulas as CameraRotation.openCvCameraToWorld and
recenterYaw (lib/core/math/camera_rotation.dart).

Usage:
  make_list.py <local_photo_dir> [--grid wide|standard] [--count N]
               [--hfov 53] [--width 4096] [--refine 1]
               [--remote /data/local/tmp/sary] > list.txt
Without a manifest, the session = the N most recent photos.
"""
import argparse
import json
import math
import os
import re
import sys

GRIDS = {
    # rows: zenith, upper, horizon, lower, nadir
    "wide": ([85, 45, 0, -45, -85], [1, 7, 10, 7, 1], 53.0),
    "standard": ([75, 35, 0, -35, -75], [5, 10, 12, 10, 5], 40.0),
}
PATTERN = re.compile(r"photo_r(\d)_i(\d+)_(\d+)\.jpg$")


def mul(a, b):
    return [sum(a[i * 3 + k] * b[k * 3 + j] for k in range(3)) for i in range(3) for j in range(3)]


def camera_to_world(row, idx, elevations, per_row):
    step = 360 / per_row[row]
    offset = 0 if row % 2 == 0 else step / 2
    az = math.radians((idx * step + offset) % 360)
    el = math.radians(elevations[row])
    f = [math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)]
    r = [math.cos(az), -math.sin(az), 0.0]
    u = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]]
    device_to_world = [r[0], u[0], -f[0], r[1], u[1], -f[1], r[2], u[2], -f[2]]
    cam_to_device = [1, 0, 0, 0, -1, 0, 0, 0, -1]
    enu_to_cv = [1, 0, 0, 0, 0, -1, 0, 1, 0]
    return mul(enu_to_cv, mul(device_to_world, cam_to_device))


def quaternion_matrix(q):
    x, y, z, w = q
    n = math.sqrt(x * x + y * y + z * z + w * w)
    x, y, z, w = x / n, y / n, z / n, w / n
    return [
        1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y),
        2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x),
        2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y),
    ]


def from_manifest(path):
    """[(file, OpenCV camera → world rotation)], hfov, in capture order."""
    with open(path) as f:
        manifest = json.load(f)
    cam_to_device = [1, 0, 0, 0, -1, 0, 0, 0, -1]
    enu_to_cv = [1, 0, 0, 0, 0, -1, 0, 1, 0]
    entries = [
        (p["file"], mul(enu_to_cv, mul(quaternion_matrix(p["quaternion"]), cam_to_device)))
        for p in manifest["photos"]
    ]
    return entries, manifest["photos"][0].get("hFov")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("photos_dir")
    ap.add_argument("--grid", default="wide", choices=GRIDS)
    ap.add_argument("--count", type=int)
    ap.add_argument("--hfov", type=float)
    ap.add_argument("--width", type=int, default=4096)
    ap.add_argument("--refine", type=int, default=1)
    ap.add_argument("--remote", default="/data/local/tmp/sary")
    args = ap.parse_args()

    elevations, per_row, default_hfov = GRIDS[args.grid]
    manifest = os.path.join(args.photos_dir, "session.json")
    if os.path.exists(manifest):
        entries, hfov = from_manifest(manifest)
        print_list(entries, args.hfov or hfov or default_hfov, args)
        return

    count = args.count or sum(per_row)
    photos = []
    for name in os.listdir(args.photos_dir):
        m = PATTERN.match(name)
        if m:
            photos.append((int(m.group(3)), int(m.group(1)), int(m.group(2)), name))
    photos.sort()  # capture order
    session = photos[-count:]
    if len(session) < count:
        sys.exit(f"only {len(session)} photos found, {count} expected")

    entries = [(name, camera_to_world(r, i, elevations, per_row)) for _, r, i, name in session]
    print_list(entries, args.hfov or default_hfov, args)


def print_list(entries, hfov, args):
    # Recenter: the first captured photo at the panorama center.
    first = entries[0][1]
    yaw = math.atan2(first[2], first[8])
    c, s = math.cos(-yaw), math.sin(-yaw)
    ry = [c, 0, s, 0, 1, 0, -s, 0, c]
    print(f"{args.remote}/pano.jpg {hfov} {args.width} {args.refine}")
    for name, rot in entries:
        values = " ".join(f"{v:.6f}" for v in mul(ry, rot))
        print(f"{args.remote}/photos/{name} {values}")


if __name__ == "__main__":
    main()
