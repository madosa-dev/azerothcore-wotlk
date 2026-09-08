#!/usr/bin/env python3
"""Decode BLP2 textures - the format every WoW 3.3.5 UI texture is in.

Three encodings turn up: a 256-colour palette with a separate alpha plane,
DXT1/3/5 block compression, and straight BGRA. All three are here; JPEG-typed
BLP1 is not, because 3.3.5 does not ship any.

Usage: blp.py <file.blp> <out.png>
"""
import struct
import sys

from PIL import Image

RAW, DXT, ARGB = 1, 2, 3


def _dxt_colors(block):
    c0, c1 = struct.unpack_from("<HH", block, 0)
    def rgb(c):
        return (((c >> 11) & 0x1F) * 255 // 31,
                ((c >> 5) & 0x3F) * 255 // 63,
                (c & 0x1F) * 255 // 31)
    a, b = rgb(c0), rgb(c1)
    if c0 > c1:
        third = tuple((2 * a[i] + b[i]) // 3 for i in range(3))
        fourth = tuple((a[i] + 2 * b[i]) // 3 for i in range(3))
        alphas = (255, 255, 255, 255)
    else:
        third = tuple((a[i] + b[i]) // 2 for i in range(3))
        fourth = (0, 0, 0)
        alphas = (255, 255, 255, 0)          # DXT1 one-bit alpha
    return (a, b, third, fourth), alphas


def _decode_dxt(data, width, height, kind):
    out = Image.new("RGBA", (width, height))
    px = out.load()
    stride = 8 if kind == 1 else 16
    pos = 0
    for by in range(0, height, 4):
        for bx in range(0, width, 4):
            block = data[pos:pos + stride]
            pos += stride
            if len(block) < stride:
                return out
            if kind == 1:
                colour_block, alpha = block, None
            else:
                colour_block, alpha = block[8:], block[:8]
            colours, implicit = _dxt_colors(colour_block)
            bits = struct.unpack_from("<I", colour_block, 4)[0]
            for y in range(4):
                for x in range(4):
                    if bx + x >= width or by + y >= height:
                        continue
                    index = (bits >> (2 * (4 * y + x))) & 3
                    r, g, b = colours[index]
                    if kind == 1:
                        a = implicit[index]
                    elif kind == 3:                      # DXT3: 4 bits per pixel
                        nibble = alpha[(4 * y + x) // 2]
                        a = (nibble & 0x0F) if (4 * y + x) % 2 == 0 else (nibble >> 4)
                        a = a * 17
                    else:                                # DXT5: interpolated
                        a0, a1 = alpha[0], alpha[1]
                        lookup = int.from_bytes(alpha[2:8], "little")
                        code = (lookup >> (3 * (4 * y + x))) & 7
                        if code == 0:
                            a = a0
                        elif code == 1:
                            a = a1
                        elif a0 > a1:
                            a = ((8 - code) * a0 + (code - 1) * a1) // 7
                        elif code == 6:
                            a = 0
                        elif code == 7:
                            a = 255
                        else:
                            a = ((6 - code) * a0 + (code - 1) * a1) // 5
                    px[bx + x, by + y] = (r, g, b, a)
    return out


def decode(data):
    if data[:4] != b"BLP2":
        raise ValueError("not a BLP2 texture")
    _type, encoding, alpha_depth, alpha_encoding, _mips = struct.unpack_from("<IBBBB", data, 4)
    width, height = struct.unpack_from("<II", data, 12)
    offsets = struct.unpack_from("<16I", data, 20)
    sizes = struct.unpack_from("<16I", data, 84)
    body = data[offsets[0]:offsets[0] + sizes[0]]

    if encoding == DXT:
        kind = {0: 1, 1: 3, 7: 5}.get(alpha_encoding, 1)
        if alpha_depth == 0:
            kind = 1
        return _decode_dxt(body, width, height, kind)

    if encoding == ARGB:
        img = Image.frombytes("RGBA", (width, height), body[:width * height * 4])
        b, g, r, a = img.split()
        return Image.merge("RGBA", (r, g, b, a))

    if encoding == RAW:
        palette = struct.unpack_from("<1024B", data, 148)
        count = width * height
        indices = body[:count]
        alpha_bytes = body[count:]
        img = Image.new("RGBA", (width, height))
        px = img.load()
        for i, index in enumerate(indices):
            b, g, r = palette[index * 4], palette[index * 4 + 1], palette[index * 4 + 2]
            if alpha_depth == 8:
                a = alpha_bytes[i] if i < len(alpha_bytes) else 255
            elif alpha_depth == 4:
                byte = alpha_bytes[i // 2] if i // 2 < len(alpha_bytes) else 0xFF
                a = ((byte & 0x0F) if i % 2 == 0 else (byte >> 4)) * 17
            elif alpha_depth == 1:
                byte = alpha_bytes[i // 8] if i // 8 < len(alpha_bytes) else 0xFF
                a = 255 if (byte >> (i % 8)) & 1 else 0
            else:
                a = 255
            px[i % width, i // width] = (r, g, b, a)
        return img

    raise NotImplementedError("BLP colour encoding %d" % encoding)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    decode(open(sys.argv[1], "rb").read()).save(sys.argv[2])
    print(sys.argv[2])


if __name__ == "__main__":
    main()
