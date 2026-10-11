#!/usr/bin/env python3
"""Parser and disassembler for America (Related Designs, 2000/2001) AI script modules (*.mod,
"KIMODULE"), as run by the KI virtual machine in AmericaAddOn.exe (see VM.md).

usage:
  kimod.py FILE.mod [...]          disassemble (variables, constants, code with source lines)
  kimod.py --stats DIR [DIR...]    parse every *.mod, report errors and native usage counts
  kimod.py --json FILE.mod         dump the parsed module as JSON
"""
import json, os, struct, sys, glob, collections

from kinatives import NATIVES   # id -> (name, n_args, n_results, short description)

OPNAMES = {0: 'push', 1: 'pop', 2: 'pushi', 3: 'popraw', 4: 'call', 5: 'gosub',
           6: 'spawn', 7: 'jmp', 8: 'jz', 9: 'jnz'}
TYPES = {0: 'int', 1: 'bool', 2: 'building', 3: 'unit', 4: 'neutral'}
CLASSES = {0: '', 1: 'ref ', 2: 'array ', 3: 'ref array '}
DISCARD = 0x0FFFFFFF


class ModError(Exception):
    pass


def var_kind(vid):
    """variable id -> (class, type, index). class bit0 = by-reference (parent's
    variable), bit1 = array; type = 0 int, 1 bool, 2 building, 3 unit, 4 neutral object."""
    return (vid >> 24) & 0xF, (vid >> 16) & 0xFF, vid & 0xFFFF


class Module:
    def __init__(self, data, path=''):
        self.path = path
        if data[:8] != b'KIMODULE':
            raise ModError('bad magic')
        total = struct.unpack_from('<I', data, 8)[0]
        if total + 12 != len(data):
            raise ModError('size field %d != file size %d - 12' % (total, len(data)))
        self.sections = collections.OrderedDict()
        off = 12
        while off < len(data):
            if off + 12 > len(data):
                raise ModError('truncated section header at %#x' % off)
            name = data[off:off + 8].rstrip(b' \0').decode('ascii')
            size = struct.unpack_from('<I', data, off + 8)[0]
            body = data[off + 12:off + 12 + size]
            if len(body) != size:
                raise ModError('truncated section %s' % name)
            self.sections[name] = body
            off += 12 + size
        for need in ('HEADER', 'VARIABLE', 'CONSTDAT', 'CODEDATA'):
            if need not in self.sections:
                raise ModError('missing section ' + need)
        self.header = struct.unpack('<I', self.sections['HEADER'][:4])[0]
        # VARIABLE: u32 n, n x {u32 descriptor (class<<24 | type<<16), u32 element count}
        v = self.sections['VARIABLE']
        n = struct.unpack_from('<I', v)[0]
        if 4 + 8 * n != len(v):
            raise ModError('VARIABLE size')
        self.var_blocks = [struct.unpack_from('<II', v, 4 + 8 * i) for i in range(n)]
        # CONSTDAT: u32 n, n x {u32 variable id, i32 initial value}
        c = self.sections['CONSTDAT']
        n = struct.unpack_from('<I', c)[0]
        if 4 + 8 * n != len(c):
            raise ModError('CONSTDAT size')
        self.consts = collections.OrderedDict(
            (struct.unpack_from('<I', c, 4 + 8 * i)[0], struct.unpack_from('<i', c, 8 + 8 * i)[0])
            for i in range(n))
        cd = self.sections['CODEDATA']
        if len(cd) % 4:
            raise ModError('CODEDATA not word aligned')
        self.code = list(struct.unpack('<%dI' % (len(cd) // 4), cd))
        # VARMAP: u32 n, n x {char name[32], u32 variable id}
        self.names = {}
        vm = self.sections.get('VARMAP', b'')
        if vm:
            n = struct.unpack_from('<I', vm)[0]
            if 4 + 36 * n != len(vm):
                raise ModError('VARMAP size')
            for i in range(n):
                raw = vm[4 + 36 * i:36 + 36 * i]
                nm = raw.split(b'\0')[0].decode('cp1252')
                vid = struct.unpack_from('<I', vm, 36 + 36 * i)[0]
                self.names[vid] = nm
        # DEBUGGER: char source[256], u32 n, u32 first_pc[n] (pc of the first instruction of
        # source line i, 0-based)
        self.source = ''
        self.lines = []
        dbg = self.sections.get('DEBUGGER', b'')
        if dbg:
            self.source = dbg[:256].split(b'\0')[0].decode('cp1252')
            n = struct.unpack_from('<I', dbg, 256)[0]
            if 260 + 4 * n != len(dbg):
                raise ModError('DEBUGGER size')
            self.lines = list(struct.unpack_from('<%dI' % n, dbg, 260))
        # sizes of declared storage: (class,type) -> count
        self.storage = {((d >> 24) & 0xF, (d >> 16) & 0xFF): cnt for d, cnt in self.var_blocks}
        self.check()

    def check(self):
        n = len(self.code)
        for pc, w in enumerate(self.code):
            op, arg = w >> 28, w & 0x0FFFFFFF
            if op not in OPNAMES:
                raise ModError('bad opcode %d at %d' % (op, pc))
            if op in (7, 8, 9) and not (0 <= arg <= n):
                raise ModError('jump out of range at %d' % pc)
            if op in (0, 1, 3) and not (op == 1 and arg == DISCARD):
                cl, ty, ix = var_kind(arg)
                if ix >= self.storage.get((cl, ty), 0):
                    raise ModError('variable %#x out of range at %d' % (arg, pc))

    def line_of(self, pc):
        """0-based source line holding pc (same search as 0x43ed80)."""
        for i in range(len(self.lines) - 1, -1, -1):
            if self.lines[i] <= pc:
                return i
        return 0

    def vname(self, vid):
        cl, ty, ix = var_kind(vid)
        nm = self.names.get(vid)
        if vid in self.consts and (nm is None or nm == '#INTERNAL#'):
            return '%d' % self.consts[vid]
        if nm and nm != '#INTERNAL#':
            return nm
        return self.label(vid)

    def label(self, vid):
        """generic name for an unnamed slot: t/r/a/ra (scalar/ref/array/ref array) +
        i/b/B/u/n (int/bool/building/unit/neutral) + index"""
        cl, ty, ix = var_kind(vid)
        pre = {0: 't', 1: 'r', 2: 'a', 3: 'ra'}[cl] + ('ibBun'[ty] if ty < 5 else 'x')
        return '%s%d' % (pre, ix)

    def decl(self, vid):
        cl, ty, ix = var_kind(vid)
        return '%s%s' % (CLASSES.get(cl, '?%d ' % cl), TYPES.get(ty, 'type%d' % ty))

    def disasm(self):
        """yield (pc, word, op name, operand text, comment)"""
        targets = {w & 0x0FFFFFFF for w in self.code if (w >> 28) in (7, 8, 9)}
        for pc, w in enumerate(self.code):
            op, arg = w >> 28, w & 0x0FFFFFFF
            name = OPNAMES[op]
            cmt = ''
            if op == 0:
                txt = self.vname(arg)
                if arg in self.consts and self.names.get(arg, '#INTERNAL#') == '#INTERNAL#':
                    name = 'pushc'
            elif op in (1, 3):
                txt = '-' if arg == DISCARD else self.vname(arg)
                if arg == DISCARD:
                    name = 'drop'
                    txt = ''
            elif op == 2:
                cl, ty, ix = var_kind(arg)
                if arg in self.names or (arg > 0xFFFF and ix < self.storage.get((cl, ty), 0)):
                    txt = '&' + self.vname(arg)
                    cmt = 'variable reference %#x' % arg
                else:
                    txt = '%d' % arg
            elif op == 4:
                nat = NATIVES.get(arg)
                if nat:
                    txt = nat[0]
                    cmt = '#%d (%d args -> %d)' % (arg, nat[1], nat[2])
                else:
                    txt = 'native_%d' % arg
                    cmt = 'UNKNOWN NATIVE'
            elif op in (5, 6):
                # the expansion exe formats kimodules2/, the base exe kimodules/
                d = 'kimodules' if '/kimodules/' in self.path.replace('\\', '/') else 'kimodules2'
                txt = '%s/%08d.mod' % (d, arg)
            else:
                txt = 'L%d' % arg
            yield pc, w, name, txt, cmt, pc in targets

    def listing(self, out):
        p = lambda *a: print(*a, file=out)
        p('; %s  source=%s  header=%d  code=%d words' % (os.path.basename(self.path), self.source,
                                                          self.header, len(self.code)))
        p('; storage:', ', '.join('%s%s x%d' % (CLASSES[c], TYPES.get(t, t), n)
                                  for (c, t), n in sorted(self.storage.items()) if n))
        p('; variables:')
        for vid, nm in sorted(self.names.items()):
            if nm == '#INTERNAL#':
                continue
            init = self.consts.get(vid)
            p(';   %-24s %-16s id=%08x%s' % (nm, self.decl(vid), vid,
                                              '' if init is None else ' = %d' % init))
        cs = [(vid, v) for vid, v in self.consts.items()
              if self.names.get(vid, '#INTERNAL#') == '#INTERNAL#']
        p('; constants: ' + ' '.join('%s=%d' % (self.label(vid), v) for vid, v in cs))
        last = None
        for pc, w, name, txt, cmt, tgt in self.disasm():
            ln = self.line_of(pc) + 1 if self.lines else None
            if ln != last and ln is not None:
                p('            ; line %d' % ln)
                last = ln
            lab = ('L%d:' % pc) if tgt else ''
            p('%-6s %5d  %08x  %-6s %-30s%s' % (lab, pc, w, name, txt, ('; ' + cmt) if cmt else ''))

    def to_json(self):
        return {'file': self.path, 'source': self.source, 'header': self.header,
                'var_blocks': self.var_blocks, 'consts': self.consts,
                'names': {'%08x' % k: v for k, v in self.names.items()},
                'lines': self.lines, 'code': self.code}


def load(path):
    with open(path, 'rb') as f:
        return Module(f.read(), path)


def stats(dirs):
    files = []
    for d in dirs:
        files += sorted(glob.glob(os.path.join(d, '*.mod')))
    ok = 0
    bad = []
    use = collections.Counter()
    ops = collections.Counter()
    sources = {}
    for f in files:
        try:
            m = load(f)
            list(m.disasm())
            ok += 1
            for w in m.code:
                ops[w >> 28] += 1
                if w >> 28 == 4:
                    use[w & 0x0FFFFFFF] += 1
            sources[os.path.basename(f)] = m.source
        except Exception as e:  # noqa
            bad.append((f, repr(e)))
    print('%d files, %d parsed cleanly, %d failed' % (len(files), ok, len(bad)))
    for f, e in bad:
        print('  FAIL', f, e)
    print('opcode counts:', ', '.join('%s=%d' % (OPNAMES[k], v) for k, v in sorted(ops.items())))
    unk = [n for n in use if n not in NATIVES]
    print('natives used: %d distinct, %d calls; unknown ids: %s' % (len(use), sum(use.values()), unk))
    for n, c in use.most_common():
        print('  %4d %-28s %6d' % (n, NATIVES.get(n, ('?',))[0], c))
    return use


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        sys.exit(1)
    if a[0] == '--stats':
        stats(a[1:])
    elif a[0] == '--json':
        for f in a[1:]:
            print(json.dumps(load(f).to_json(), indent=1))
    else:
        for f in a:
            load(f).listing(sys.stdout)
            print()
