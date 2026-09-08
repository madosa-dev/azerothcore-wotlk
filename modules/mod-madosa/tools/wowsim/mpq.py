#!/usr/bin/env python3
"""Read files out of the WoW 3.3.5 client's MPQ archives.

Enough of the format to pull the interface out: the header, the encrypted hash
and block tables, and sector decompression. No writing, no listfile parsing
beyond what is asked for by name.

The client stacks its archives - a patch archive overrides the base one for
any file it also carries - so Client() opens them in the game's own order and
a lookup takes the last archive that has the file. Archives parked with a
.disabled suffix are skipped, the same way the game skips them.

Usage: mpq.py <archive dir> <file inside it> [<out path>]
"""
import os
import struct
import sys
import zlib

# --------------------------------------------------------------------------
# The crypt table every MPQ is keyed with, built the way Blizzard builds it.
# --------------------------------------------------------------------------

def _crypt_table():
    table = [0] * 0x500
    seed = 0x00100001
    for i in range(0x100):
        index = i
        for _ in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            a = (seed & 0xFFFF) << 0x10
            seed = (seed * 125 + 3) % 0x2AAAAB
            b = seed & 0xFFFF
            table[index] = a | b
            index += 0x100
    return table


CRYPT = _crypt_table()

HASH_TABLE_OFFSET, HASH_NAME_A, HASH_NAME_B, HASH_FILE_KEY = 0, 1, 2, 3


def hash_string(text, kind):
    seed1, seed2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in text.upper().replace("/", "\\"):
        value = ord(ch)
        seed1 = CRYPT[(kind << 8) + value] ^ ((seed1 + seed2) & 0xFFFFFFFF)
        seed2 = (value + seed1 + seed2 + (seed2 << 5) + 3) & 0xFFFFFFFF
    return seed1 & 0xFFFFFFFF


def decrypt(data, key):
    out = bytearray()
    seed = 0xEEEEEEEE
    for i in range(len(data) // 4):
        seed = (seed + CRYPT[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
        value = struct.unpack_from("<I", data, i * 4)[0]
        value = value ^ ((key + seed) & 0xFFFFFFFF)
        key = (((~key << 0x15) + 0x11111111) | (key >> 0x0B)) & 0xFFFFFFFF
        seed = (value + seed + (seed << 5) + 3) & 0xFFFFFFFF
        out += struct.pack("<I", value)
    out += data[len(data) // 4 * 4:]
    return bytes(out)


# --------------------------------------------------------------------------
# PKWARE DCL "implode", the one compression in these archives zlib cannot do.
# --------------------------------------------------------------------------

_LEN_BASE = [0x00, 0x01, 0x02, 0x03, 0x04, 0x06, 0x08, 0x0C, 0x10, 0x18, 0x20,
             0x30, 0x40, 0x60, 0x80, 0xC0]
_LEN_BITS = [3, 2, 3, 3, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 7, 7]
_LEN_CODE = [0x05, 0x03, 0x01, 0x06, 0x0A, 0x02, 0x0C, 0x14, 0x04, 0x18, 0x08,
             0x30, 0x10, 0x20, 0x40, 0x00]
_DIST_BITS = [2, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
              6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
              7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7]
_DIST_CODE = [
    0x03, 0x0D, 0x05, 0x19, 0x09, 0x11, 0x01, 0x3E, 0x1E, 0x2E, 0x0E, 0x36,
    0x16, 0x26, 0x06, 0x3A, 0x1A, 0x2A, 0x0A, 0x32, 0x12, 0x22, 0x42, 0x02,
    0x7C, 0x3C, 0x5C, 0x1C, 0x6C, 0x2C, 0x4C, 0x0C, 0x74, 0x34, 0x54, 0x14,
    0x64, 0x24, 0x44, 0x04, 0x78, 0x38, 0x58, 0x18, 0x68, 0x28, 0x48, 0x08,
    0x70, 0x30, 0x50, 0x10, 0x60, 0x20, 0x40, 0x00]


class _Bits:
    def __init__(self, data):
        self.data, self.pos, self.bit = data, 0, 0

    def read(self, count):
        value = 0
        for i in range(count):
            if self.pos >= len(self.data):
                raise EOFError("imploded stream ran out")
            value |= ((self.data[self.pos] >> self.bit) & 1) << i
            self.bit += 1
            if self.bit == 8:
                self.bit, self.pos = 0, self.pos + 1
        return value


def _decode(bits, codes, lengths):
    value, length = 0, 0
    while length < 8:
        value |= bits.read(1) << length
        length += 1
        for i, code in enumerate(codes):
            if lengths[i] == length and code == value:
                return i
    raise ValueError("bad implode code")


def explode(data):
    """PKWARE DCL, the 'implode' MPQs use. Binary mode only, which is all WoW has."""
    literal_mode, dict_bits = data[0], data[1]
    if literal_mode != 0:
        raise NotImplementedError("ASCII-mode implode is not used by WoW archives")
    bits = _Bits(data[2:])
    out = bytearray()
    while True:
        if bits.read(1):
            index = _decode(bits, _LEN_CODE, _LEN_BITS)
            length = _LEN_BASE[index] + 2
            if _LEN_BITS[index] and index:
                pass
            extra = [0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5, 6][index]
            if extra:
                length += bits.read(extra)
            if length == 519:
                break
            slot = _decode(bits, _DIST_CODE, _DIST_BITS)
            if length == 2:
                distance = (slot << 2) | bits.read(2)
            else:
                distance = (slot << dict_bits) | bits.read(dict_bits)
            distance += 1
            for _ in range(length):
                out.append(out[-distance])
        else:
            out.append(bits.read(8))
    return bytes(out)


# --------------------------------------------------------------------------

COMPRESSIONS = {
    0x02: zlib.decompress,
    0x08: explode,
}


class Archive:
    FLAG_IMPLODE = 0x00000100
    FLAG_COMPRESS = 0x00000200
    FLAG_ENCRYPTED = 0x00010000
    FLAG_FIX_KEY = 0x00020000
    FLAG_EXISTS = 0x80000000
    FLAG_SINGLE_UNIT = 0x01000000
    FLAG_SECTOR_CRC = 0x04000000

    def __init__(self, path):
        self.path = path
        self._fh = open(path, "rb")
        blob = self._fh.read(0x20)
        if blob[:4] != b"MPQ\x1a":
            raise ValueError("%s is not an MPQ archive" % path)
        (_, _, _, _fmt, self.sector_shift, hash_pos, block_pos,
         hash_count, block_count) = struct.unpack_from("<4sIIHHIIII", blob, 0)
        self.sector_size = 512 << self.sector_shift

        self._fh.seek(hash_pos)
        self.hash_table = decrypt(self._fh.read(hash_count * 16),
                                  hash_string("(hash table)", HASH_FILE_KEY))
        self._fh.seek(block_pos)
        self.block_table = decrypt(self._fh.read(block_count * 16),
                                   hash_string("(block table)", HASH_FILE_KEY))
        self.hash_count, self.block_count = hash_count, block_count

    def _find(self, name):
        start = hash_string(name, HASH_TABLE_OFFSET) & (self.hash_count - 1)
        a, b = hash_string(name, HASH_NAME_A), hash_string(name, HASH_NAME_B)
        for step in range(self.hash_count):
            i = (start + step) & (self.hash_count - 1)
            ha, hb, _locale, _plat, block = struct.unpack_from("<IIHHI", self.hash_table, i * 16)
            if block == 0xFFFFFFFF:
                return None
            if ha == a and hb == b and block != 0xFFFFFFFE:
                return block
        return None

    def __contains__(self, name):
        return self._find(name) is not None

    def read(self, name):
        block = self._find(name)
        if block is None:
            return None
        offset, packed, size, flags = struct.unpack_from("<IIII", self.block_table, block * 16)
        if not flags & self.FLAG_EXISTS:
            return None
        self._fh.seek(offset)
        raw = self._fh.read(packed)

        key = None
        if flags & self.FLAG_ENCRYPTED:
            key = hash_string(name.replace("/", "\\").rsplit("\\", 1)[-1], HASH_FILE_KEY)
            if flags & self.FLAG_FIX_KEY:
                key = ((key + offset) ^ size) & 0xFFFFFFFF

        if flags & self.FLAG_SINGLE_UNIT:
            if key is not None:
                raw = decrypt(raw, key)
            return self._unpack(raw, size, flags)

        sectors = (size + self.sector_size - 1) // self.sector_size
        table_len = (sectors + 1) * 4
        if flags & self.FLAG_SECTOR_CRC:
            table_len += 4
        table = raw[:table_len]
        if key is not None:
            table = decrypt(table, (key - 1) & 0xFFFFFFFF)
        offsets = struct.unpack_from("<%dI" % (table_len // 4), table, 0)

        out = bytearray()
        for i in range(sectors):
            chunk = raw[offsets[i]:offsets[i + 1]]
            if key is not None:
                chunk = decrypt(chunk, (key + i) & 0xFFFFFFFF)
            wanted = min(self.sector_size, size - len(out))
            out += self._unpack(chunk, wanted, flags)
        return bytes(out[:size])

    def _unpack(self, chunk, wanted, flags):
        if len(chunk) >= wanted:
            return chunk[:wanted]
        if flags & self.FLAG_COMPRESS:
            mask, body = chunk[0], chunk[1:]
            for bit, fn in COMPRESSIONS.items():
                if mask & bit:
                    body = fn(body)
                    mask &= ~bit
            if mask:
                raise NotImplementedError("compression mask 0x%02x" % mask)
            return body
        if flags & self.FLAG_IMPLODE:
            return explode(chunk)
        return chunk


# The order the 3.3.5 client stacks its archives; later ones win.
BASE_ORDER = ["common.mpq", "common-2.mpq", "expansion.mpq", "lichking.mpq", "patch.mpq"]
LOCALE_ORDER = ["locale-%s.mpq", "expansion-locale-%s.mpq", "lichking-locale-%s.mpq",
                "base-%s.mpq", "patch-%s.mpq"]


class Client:
    """Every archive of a client install, in load order."""

    def __init__(self, data_dir, locale="enus"):
        self.archives = []
        self._open_many(data_dir, BASE_ORDER)
        self._open_patches(data_dir, "patch-")
        locale_dir = os.path.join(data_dir, locale)
        if os.path.isdir(locale_dir):
            self._open_many(locale_dir, [n % locale for n in LOCALE_ORDER])
            self._open_patches(locale_dir, "patch-%s-" % locale)
        if not self.archives:
            raise SystemExit("no archives under %s" % data_dir)

    def _open_many(self, directory, names):
        for name in names:
            path = os.path.join(directory, name)
            if os.path.exists(path):
                self.archives.append(Archive(path))

    def _open_patches(self, directory, prefix):
        found = []
        for name in sorted(os.listdir(directory)):
            lower = name.lower()
            if lower.startswith(prefix) and lower.endswith(".mpq"):
                suffix = lower[len(prefix):-4]
                if suffix and suffix not in ("2", "3"):    # already in BASE_ORDER? no - keep all
                    found.append((suffix, name))
                else:
                    found.append((suffix, name))
        for _, name in sorted(found):
            self._open_many(directory, [name])

    def read(self, name):
        for archive in reversed(self.archives):
            if name in archive:
                data = archive.read(name)
                if data is not None:
                    return data
        return None

    def which(self, name):
        for archive in reversed(self.archives):
            if name in archive:
                return os.path.basename(archive.path)
        return None


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    client = Client(sys.argv[1])
    data = client.read(sys.argv[2])
    if data is None:
        raise SystemExit("%s: not in any archive" % sys.argv[2])
    if len(sys.argv) > 3:
        open(sys.argv[3], "wb").write(data)
        print("%s (%d bytes, from %s) -> %s"
              % (sys.argv[2], len(data), client.which(sys.argv[2]), sys.argv[3]))
    else:
        sys.stdout.buffer.write(data)


if __name__ == "__main__":
    main()
