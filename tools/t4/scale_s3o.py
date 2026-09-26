#!/usr/bin/env python3
"""Uniformly scale a Spring .s3o model: header radius/height/mid, every piece offset and every
vertex position are multiplied by the factor; normals, UVs, textures and piece names (so unit
scripts and animations) stay the same. Used to build the custom T4 tier from T2/T3 models.

    tools/t4/scale_s3o.py <in.s3o> <out.s3o> <factor>
    tools/t4/scale_s3o.py --info <in.s3o>

S3O layout (little endian): header = magic[12] "Spring unit\\0", int version, float radius,
float height, float midx, midy, midz, int rootPiece, int collisionData, int tex1, int tex2.
piece = int name, int numChildren, int children, int numVertices, int vertices, int vertexType,
int primitiveType, int vertexTableSize, int vertexTable, int collisionData, float xoff, yoff, zoff.
vertex = float x, y, z, nx, ny, nz, u, v (32 bytes).
"""
import struct
import sys

HDR = struct.Struct("<12si5f4i")
PIECE = struct.Struct("<10i3f")
VERT = 32


def cstr(buf, off):
    end = buf.index(b"\0", off)
    return buf[off:end].decode("latin-1")


def walk(buf, off, fn, depth=0):
    p = list(PIECE.unpack_from(buf, off))
    fn(off, p, depth)
    num_children, children = p[1], p[2]
    for i in range(num_children):
        (child,) = struct.unpack_from("<i", buf, children + 4 * i)
        walk(buf, child, fn, depth + 1)


def info(path):
    buf = open(path, "rb").read()
    h = HDR.unpack_from(buf, 0)
    print(f"{path}: radius={h[2]:.1f} height={h[3]:.1f} mid=({h[4]:.1f},{h[5]:.1f},{h[6]:.1f}) "
          f"tex1={cstr(buf, h[9]) if h[9] else '-'} tex2={cstr(buf, h[10]) if h[10] else '-'}")
    bbox = [1e9, 1e9, 1e9, -1e9, -1e9, -1e9]

    def show(off, p, depth, origin=[(0.0, 0.0, 0.0)]):
        print("  " * depth + f"{cstr(buf, p[0])} off=({p[10]:.1f},{p[11]:.1f},{p[12]:.1f}) verts={p[3]}")
    walk(buf, h[7], show)


def scale(src, dst, k):
    buf = bytearray(open(src, "rb").read())
    h = list(HDR.unpack_from(buf, 0))
    if not h[0].startswith(b"Spring unit"):
        raise SystemExit(f"{src}: not an s3o file")
    h[2] *= k  # radius
    h[3] *= k  # height
    h[4] *= k  # mid x
    h[5] *= k
    h[6] *= k
    HDR.pack_into(buf, 0, *h)
    seen = set()

    def fix(off, p, depth):
        if off in seen:
            return
        seen.add(off)
        p[10] *= k
        p[11] *= k
        p[12] *= k
        PIECE.pack_into(buf, off, *p)
        num_vertices, vertices = p[3], p[4]
        for i in range(num_vertices):
            vo = vertices + i * VERT
            x, y, z = struct.unpack_from("<3f", buf, vo)
            struct.pack_into("<3f", buf, vo, x * k, y * k, z * k)
    walk(buf, h[7], fix)
    open(dst, "wb").write(bytes(buf))
    print(f"{src} -> {dst} x{k}: radius {h[2]:.1f}, height {h[3]:.1f}, pieces {len(seen)}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--info":
        info(sys.argv[2])
    elif len(sys.argv) == 4:
        scale(sys.argv[1], sys.argv[2], float(sys.argv[3]))
    else:
        raise SystemExit(__doc__)
