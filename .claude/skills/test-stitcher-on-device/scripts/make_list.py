#!/usr/bin/env python3
"""Génère la liste d'entrée de stitch_cli pour une session de capture.

Si le dossier contient session.json (écrit par l'app à la fin de la
capture), les rotations viennent des **quaternions réellement mesurés** et
l'ordre de capture est respecté : l'assemblage est rejoué à l'identique.

Sinon (anciennes sessions), les rotations sont reconstruites à partir des
angles des cibles de la grille (approximation : le cap réel peut s'en
écarter). Grilles : garder en phase avec lib/core/constants/app_constants.dart.

Conversions : mêmes formules que CameraRotation.openCvCameraToWorld et
recenterYaw (lib/core/math/camera_rotation.dart).

Usage :
  make_list.py <dossier_photos_local> [--grid wide|standard] [--count N]
               [--hfov 53] [--width 4096] [--refine 1]
               [--remote /data/local/tmp/sary] > list.txt
Sans manifeste, la session retenue = les N photos les plus récentes.
"""
import argparse
import json
import math
import os
import re
import sys

GRIDS = {
    # rangées : zénith, haute, horizon, basse, nadir
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
    """[(fichier, rotation caméra → monde OpenCV)], hfov, dans l'ordre de capture."""
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
    photos.sort()  # ordre de capture
    session = photos[-count:]
    if len(session) < count:
        sys.exit(f"seulement {len(session)} photos trouvées, {count} attendues")

    entries = [(name, camera_to_world(r, i, elevations, per_row)) for _, r, i, name in session]
    print_list(entries, args.hfov or default_hfov, args)


def print_list(entries, hfov, args):
    # Recentrage : la première photo capturée au centre du panorama.
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
