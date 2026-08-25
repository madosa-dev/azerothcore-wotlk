import struct, sys, zlib, bz2, os

# --- MPQ crypt table (Blizzard) ---
_ct = {}
def _mkct():
    seed = 0x00100001
    for i in range(256):
        for j in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            a = (seed & 0xFFFF) << 0x10
            seed = (seed * 125 + 3) % 0x2AAAAB
            b = (seed & 0xFFFF)
            _ct[i + j*0x100] = (a | b)
_mkct()

def hash_str(s, t):
    s = s.upper().encode('ascii', 'replace')
    seed1, seed2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in s:
        v = _ct[(t*0x100)+ch]
        seed1 = (v ^ (seed1 + seed2)) & 0xFFFFFFFF
        seed2 = (ch + seed1 + seed2 + (seed2 << 5) + 3) & 0xFFFFFFFF
    return seed1

def decrypt(data, key):
    out = bytearray()
    seed2 = 0xEEEEEEEE
    for i in range(len(data)//4):
        seed2 = (seed2 + _ct[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
        v = struct.unpack_from('<I', data, i*4)[0]
        v = (v ^ (key + seed2)) & 0xFFFFFFFF
        out += struct.pack('<I', v)
        key = (((~key << 0x15) + 0x11111111) | (key >> 0x0B)) & 0xFFFFFFFF
        seed2 = (v + seed2 + (seed2 << 5) + 3) & 0xFFFFFFFF
    return bytes(out)

def decompress(data):
    mask = data[0]
    body = data[1:]
    if mask == 2:   return zlib.decompress(body)
    if mask == 0x10: return bz2.decompress(body)
    if mask == 8:
        try:
            import pylzma; return pylzma.decompress(body)
        except Exception: raise ValueError('pkware/lzma unsupported')
    raise ValueError('compression 0x%02x unsupported' % mask)

class MPQ:
    def __init__(self, path):
        self.f = open(path, 'rb')
        # find header (aligned to 512)
        off = 0
        while True:
            self.f.seek(off)
            magic = self.f.read(4)
            if magic == b'MPQ\x1a': break
            if not magic: raise ValueError('no MPQ header')
            off += 512
        self.base = off
        hdr = self.f.read(28)
        (self.hdr_size, self.arc_size, self.fmt, self.bs,
         self.htbl_off, self.btbl_off, self.htbl_n, self.btbl_n) = struct.unpack('<IIHHIIII', hdr)
        hi_h = hi_b = 0
        if self.fmt >= 1:
            ext = self.f.read(12)
            _, hi_h, hi_b = struct.unpack('<QHH', ext)
        self.htbl_off |= hi_h << 32
        self.btbl_off |= hi_b << 32

    def _table(self, off, n, key, esz):
        self.f.seek(self.base + off)
        return decrypt(self.f.read(n*esz), hash_str(key, 3))

    def read_file(self, name):
        ht = self._table(self.htbl_off, self.htbl_n, '(hash table)', 16)
        bt = self._table(self.btbl_off, self.btbl_n, '(block table)', 16)
        i0 = hash_str(name, 0) & (self.htbl_n - 1)
        a, b = hash_str(name, 1), hash_str(name, 2)
        idx = None
        for k in range(self.htbl_n):
            i = (i0 + k) & (self.htbl_n - 1)
            h1, h2, loc, blk = struct.unpack_from('<IIIi', ht, i*16)
            if blk == -1: break
            if h1 == a and h2 == b and blk >= 0:
                idx = blk; break
        if idx is None: return None
        fpos, csize, fsize, flags = struct.unpack_from('<IIII', bt, idx*16)
        fpos |= 0  # (hi bits ignored; fine for <4GB offsets)
        self.f.seek(self.base + fpos)
        if flags & 0x00010000:  # ENCRYPTED
            return None
        if flags & 0x01000000:  # SINGLE UNIT
            raw = self.f.read(csize)
            return decompress(raw) if flags & 0x00000200 else raw
        # uncompressed: raw contiguous data, no sector offset table
        if not (flags & 0x00000300):
            return self.f.read(fsize)
        # sector-based
        secsize = 512 << self.bs
        nsec = (fsize + secsize - 1)//secsize
        tbl = struct.unpack('<%dI' % (nsec+1), self.f.read((nsec+1)*4))
        out = b''
        for s in range(nsec):
            self.f.seek(self.base + fpos + tbl[s])
            raw = self.f.read(tbl[s+1]-tbl[s])
            want = min(secsize, fsize - len(out))
            if flags & 0x00000200 and len(raw) < want:
                out += decompress(raw)
            else:
                out += raw[:want]
        return out[:fsize]


def encrypt(data, key):
    out = bytearray(); seed2 = 0xEEEEEEEE
    for i in range(len(data)//4):
        seed2 = (seed2 + _ct[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
        ch = struct.unpack_from('<I', data, i*4)[0]
        out += struct.pack('<I', (ch ^ (key + seed2)) & 0xFFFFFFFF)
        key = (((~key << 0x15) + 0x11111111) | (key >> 0x0B)) & 0xFFFFFFFF
        seed2 = (ch + seed2 + (seed2 << 5) + 3) & 0xFFFFFFFF
    return bytes(out)

MPQ_FILE_EXISTS   = 0x80000000
MPQ_FILE_COMPRESS = 0x00000200
HASH_FREE = 0xFFFFFFFF

def _pack_sectors(blob, secsize):
    """Compress a file into MPQ sectors (zlib, mask 0x02). Returns packed bytes."""
    import zlib
    nsec = max(1, (len(blob) + secsize - 1)//secsize)
    sectors = []
    for i in range(nsec):
        raw = blob[i*secsize:(i+1)*secsize]
        comp = b'\x02' + zlib.compress(raw, 9)
        # MPQ convention: keep the sector raw when compression does not help
        sectors.append(comp if len(comp) < len(raw) else raw)
    tbl_size = (nsec + 1) * 4
    offs, cur = [], tbl_size
    for sec in sectors:
        offs.append(cur); cur += len(sec)
    offs.append(cur)
    return struct.pack('<%dI' % (nsec+1), *offs) + b''.join(sectors)

def build(out_path, files, sector_shift=3):
    """files: list of (archive_name, bytes)"""
    secsize = 512 << sector_shift
    names = [n for n, _ in files]
    listfile = ('\r\n'.join(names) + '\r\n').encode('ascii')
    entries = list(files) + [('(listfile)', listfile)]

    hsize = 16
    while hsize < len(entries) * 2:
        hsize <<= 1

    data_blob = bytearray()
    block = []
    for name, blob in entries:
        packed = _pack_sectors(blob, secsize)
        pos = 32 + len(data_blob)
        data_blob += packed
        data_blob += b'\x00' * ((-len(data_blob)) % 8)
        block.append((pos, len(packed), len(blob),
                      MPQ_FILE_EXISTS | MPQ_FILE_COMPRESS))

    htbl = [[HASH_FREE, HASH_FREE, 0xFFFF, 0xFFFF, HASH_FREE] for _ in range(hsize)]
    for idx, (name, _) in enumerate(entries):
        start = hash_str(name, 0) & (hsize - 1)
        a, b = hash_str(name, 1), hash_str(name, 2)
        for k in range(hsize):
            i = (start + k) & (hsize - 1)
            if htbl[i][4] == HASH_FREE:
                htbl[i] = [a, b, 0, 0, idx]; break
        else:
            raise RuntimeError('hash table full')

    hraw = b''.join(struct.pack('<IIHHI', e[0], e[1], e[2], e[3], e[4]) for e in htbl)
    braw = b''.join(struct.pack('<IIII', *b) for b in block)
    henc = encrypt(hraw, hash_str('(hash table)', 3))
    benc = encrypt(braw, hash_str('(block table)', 3))

    htbl_off = 32 + len(data_blob)
    btbl_off = htbl_off + len(henc)
    arc_size = btbl_off + len(benc)
    hdr = struct.pack('<4sIIHHIIII', b'MPQ\x1a', 32, arc_size, 0, sector_shift,
                      htbl_off, btbl_off, hsize, len(block))
    with open(out_path, 'wb') as f:
        f.write(hdr); f.write(data_blob); f.write(henc); f.write(benc)
    return arc_size, len(block)
