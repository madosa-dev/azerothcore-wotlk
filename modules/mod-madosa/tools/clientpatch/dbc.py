import struct

class DBC:
    def __init__(self, path):
        self.d = open(path,'rb').read()
        _, self.rc, self.fc, self.rs, self.sb = struct.unpack_from('<4sIIII', self.d, 0)
        self.sblock = 20 + self.rc*self.rs
    def row(self, i):
        return struct.unpack_from('<%dI'%self.fc, self.d, 20 + i*self.rs)
    def rows(self):
        return (self.row(i) for i in range(self.rc))
    def s(self, off):
        if not off: return ''
        e = self.d.index(b'\x00', self.sblock+off)
        return self.d[self.sblock+off:e].decode('latin1')
    def find_str_offsets(self, needle):
        """All string-block offsets whose string contains `needle` (case-insensitive)."""
        blk = self.d[self.sblock:self.sblock+self.sb]
        out, pos = [], 0
        low = blk.lower(); nb = needle.lower().encode('latin1')
        while True:
            i = low.find(nb, pos)
            if i < 0: break
            st = blk.rfind(b'\x00', 0, i) + 1
            out.append(st)
            pos = i + 1
        return sorted(set(out))

F = lambda v: struct.unpack('<f', struct.pack('<I', v))[0]
I = lambda f: struct.unpack('<I', struct.pack('<f', f))[0]

def m2_bounds(path):
    d = open(path, 'rb').read()
    bb = struct.unpack_from('<6f', d, 0xBC)          # boundingBox min xyz / max xyz
    radius = struct.unpack_from('<f', d, 0xD4)[0]
    return bb, radius

class DBCBuilder:
    """Append rows (and strings) to an existing DBC, preserving everything else."""
    def __init__(self, path):
        self.src = DBC(path)
        self.rows = [list(self.src.row(i)) for i in range(self.src.rc)]
        self.strings = bytearray(self.src.d[self.src.sblock:self.src.sblock + self.src.sb])
    def addstr(self, s):
        if not s: return 0
        off = len(self.strings)
        self.strings += s.encode('latin1') + b'\x00'
        return off
    def append(self, row):
        self.rows.append(list(row))
    def save(self, out):
        hdr = struct.pack('<4sIIII', b'WDBC', len(self.rows), self.src.fc,
                          self.src.rs, len(self.strings))
        body = b''.join(struct.pack('<%dI' % self.src.fc, *r) for r in self.rows)
        open(out, 'wb').write(hdr + body + bytes(self.strings))
        return len(self.rows)
