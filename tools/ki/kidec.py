#!/usr/bin/env python3
"""Rough decompiler for KI modules: turns the stack code into statements with expressions,
recovers if/else and while loops where the jump pattern is the compiler's usual one and
falls back to labels and gotos otherwise.

usage: kidec.py FILE.mod [...]
"""
import os, sys, glob
import kimod
from kinatives import NATIVES

INFIX = {1: '+', 2: '-', 3: '*', 4: '/', 5: '&', 6: '|', 7: '^', 8: '%', 10: '>', 11: '<',
         12: '==', 13: '!=', 14: '>=', 15: '<=', 20: '&&', 21: '||'}
PREC = {'*': 5, '/': 5, '%': 5, '+': 4, '-': 4, '&': 3, '^': 3, '|': 3, '>': 2, '<': 2,
        '==': 2, '!=': 2, '>=': 2, '<=': 2, '&&': 1, '||': 0}

MODDIRS = []
_arity = {}


def find_module(num):
    for d in MODDIRS:
        p = os.path.join(d, '%08d.mod' % num)
        if os.path.exists(p):
            return p
    return None


def sub_arity(num, seen=()):
    """(n_params, n_results) of a module used with gosub: params = leading pops, results =
    stack depth left at the end of its code."""
    if num in _arity:
        return _arity[num]
    p = find_module(num)
    if not p or num in seen:
        return None
    m = kimod.load(p)
    npar = 0
    for w in m.code:
        if w >> 28 in (1, 3) and (w & 0x0FFFFFFF) != kimod.DISCARD:
            npar += 1
        else:
            break
    depth = {0: 0}
    work = [0]
    end = None
    while work:
        pc = work.pop()
        d = depth[pc]
        if pc >= len(m.code):
            end = d if end is None else max(end, d)
            continue
        w = m.code[pc]
        op, a = w >> 28, w & 0x0FFFFFFF
        nxt = [pc + 1]
        if op in (0, 2):
            d += 1
        elif op in (1, 3):
            d -= 1
        elif op == 4:
            n = NATIVES.get(a)
            d += (n[2] - n[1]) if n else 0
        elif op == 5:
            r = sub_arity(a, seen + (num,))
            d += (r[1] - r[0]) if r else 0
        elif op == 7:
            nxt = [a]
        elif op in (8, 9):
            d -= 1
            nxt = [pc + 1, a]
        for t in nxt:
            if t not in depth:
                depth[t] = d
                work.append(t)
    res = (npar, max(0, (end or 0) + npar))
    _arity[num] = res
    return res


class Expr:
    def __init__(self, text, prec=9):
        self.text, self.prec = text, prec

    def __str__(self):
        return self.text


def wrap(e, p):
    return '(%s)' % e.text if e.prec < p else e.text


def decompile(m):
    """returns list of (pc, kind, text, target) statements"""
    raw = []
    stack = []
    names = lambda vid: m.vname(vid)
    start = [0]
    class L(list):
        def append(self, s):
            list.append(self, s + (start[0],))
    stmts = L()
    for pc, w in enumerate(m.code):
        op, a = w >> 28, w & 0x0FFFFFFF
        if not stack or all(getattr(x, 'spawned', False) for x in stack):
            if not stack:
                start[0] = pc
        if op == 0:
            stack.append(Expr(names(a)))
        elif op == 2:
            stack.append(Expr('&' + names(a)))
        elif op in (1, 3):
            v = stack.pop() if stack else Expr('<arg>')
            if a == kimod.DISCARD:
                if not getattr(v, 'spawned', False):
                    stmts.append((pc, 'stmt', '%s;' % v, None))
            else:
                stmts.append((pc, 'stmt', '%s = %s;' % (names(a), v), None))
        elif op == 4:
            n = NATIVES.get(a, ('native_%d' % a, 0, 0, ''))
            k = n[1]
            while len(stack) < k:
                stack.insert(0, Expr('<underflow>'))
            args = stack[len(stack) - k:] if k else []
            del stack[len(stack) - k:]
            if a in INFIX and k == 2:
                o = INFIX[a]
                e = Expr('%s %s %s' % (wrap(args[0], PREC[o]), o, wrap(args[1], PREC[o] + 1)), PREC[o])
            elif a == 22:
                e = Expr('!' + wrap(args[0], 8), 8)
            else:
                e = Expr('%s(%s)' % (n[0], ', '.join(str(x) for x in args)))
            if n[2] == 1:
                stack.append(e)
            elif n[2] == 0:
                stmts.append((pc, 'stmt', '%s;' % e, None))
            else:
                stack.append(e)
                for _ in range(n[2] - 1):
                    stack.append(Expr('?'))
        elif op == 5:
            ar = sub_arity(a)
            k = ar[0] if ar else len(stack)
            args = stack[len(stack) - k:] if k else []
            del stack[len(stack) - k:]
            e = Expr('gosub_%08d(%s)' % (a, ', '.join(str(x) for x in args)))
            if ar and ar[1]:
                stack.append(e)
                for _ in range(ar[1] - 1):
                    stack.append(Expr('?'))
            else:
                stmts.append((pc, 'stmt', '%s;' % e, None))
        elif op == 6:
            args = stack[-10:]
            for x in args:
                x.spawned = True
            stmts.append((pc, 'stmt', 'spawn_%08d(%s);' % (a, ', '.join(str(x) for x in args)), None))
        elif op == 7:
            live = [x for x in stack if not getattr(x, 'spawned', False)]
            if live and a >= len(m.code):
                stmts.append((pc, 'stmt', 'return %s;' % ', '.join(map(str, live)), None))
                stack = []
                continue
            stmts.append((pc, 'jmp', '', a))
        elif op in (8, 9):
            v = stack.pop() if stack else Expr('<empty>')
            stmts.append((pc, 'jz' if op == 8 else 'jnz', str(v), a))
        if stack and op in (7, 8, 9) and not all(getattr(x, 'spawned', False) for x in stack):
            stmts.append((pc, 'stmt', '/* stack not empty: %s */' % ', '.join(map(str, stack)), None))
            stack = []
    if stack:
        stmts.append((len(m.code), 'stmt', 'return %s;' % ', '.join(map(str, stack)), None))
    return list(stmts)
    return stmts


def structure(m, stmts):
    """while:  S: <cond> jz E; body; jmp S; E:      (S = first pc of the condition)
       if:     <cond> jz E; body; E:
       if/else:<cond> jz E; body; jmp X; E: else-body; X:
    anything else stays a goto"""
    lines = []
    def first_at(pc):
        for i, st in enumerate(stmts):
            if st[0] >= pc:
                return i
        return len(stmts)

    def block(i, end, depth):
        while i < end:
            pc, kind, text, tgt, st = stmts[i]
            # do { ... } while (cond): a later conditional jump back to this statement
            dw = [j for j in range(i + 1, end) if stmts[j][1] in ('jz', 'jnz')
                  and stmts[j][3] == st and stmts[j][3] < stmts[j][0]]
            if dw and not getattr(block, 'skip', None) == i:
                j = max(dw)
                c = stmts[j][2]
                cond = '!(%s)' % c if stmts[j][1] == 'jz' else c
                lines.append((depth, 'do {', pc))
                block.skip = i
                block(i, j, depth + 1)
                lines.append((depth, '} while (%s);' % cond, stmts[j][0]))
                i = j + 1
                continue
            block.skip = None
            if kind in ('jz', 'jnz'):
                cond = text if kind == 'jz' else '!(%s)' % text
                j = first_at(tgt)
                if i < j <= end:
                    last = stmts[j - 1] if j - 1 > i else None
                    if last and last[1] == 'jmp' and last[3] == st:
                        lines.append((depth, 'while (%s) {' % cond, pc))
                        block(i + 1, j - 1, depth + 1)
                        lines.append((depth, '}', None))
                        i = j
                        continue
                    if last and last[1] == 'jmp' and last[3] > last[0]:
                        x = first_at(last[3])
                        if x == j:
                            lines.append((depth, 'if (%s) {' % cond, pc))
                            block(i + 1, j - 1, depth + 1)
                            lines.append((depth, '}', None))
                            i = j
                            continue
                        if x <= end:
                            lines.append((depth, 'if (%s) {' % cond, pc))
                            block(i + 1, j - 1, depth + 1)
                            lines.append((depth, '} else {', None))
                            block(j, x, depth + 1)
                            lines.append((depth, '}', None))
                            i = x
                            continue
                    lines.append((depth, 'if (%s) {' % cond, pc))
                    block(i + 1, j, depth + 1)
                    lines.append((depth, '}', None))
                    i = j
                    continue
                lines.append((depth, 'if (!(%s)) goto L%d;' % (cond, tgt), pc))
            elif kind == 'jmp':
                lines.append((depth, 'goto L%d;' % tgt, pc))
            else:
                lines.append((depth, text, pc))
            i += 1

    block(0, len(stmts), 0)
    return lines


def render(path):
    m = kimod.load(path)
    stmts = decompile(m)
    lines = structure(m, stmts)
    # labels still referenced by gotos
    used = set()
    for d, t, pc in lines:
        if 'goto L' in t:
            used.add(int(t.split('goto L')[1].rstrip(';')))
    out = ['// %s  (%s)' % (os.path.basename(path), m.source)]
    vars_ = [(vid, nm) for vid, nm in sorted(m.names.items()) if nm != '#INTERNAL#']
    for vid, nm in vars_:
        init = m.consts.get(vid)
        out.append('%s %s%s;' % (m.decl(vid), nm, '' if init is None else ' = %d' % init))
    lastline = None
    pcs_emitted = set()
    for d, t, pc in lines:
        if pc is not None:
            for L in sorted(used):
                if L <= pc and L not in pcs_emitted:
                    out.append('L%d:' % L)
                    pcs_emitted.add(L)
            ln = m.line_of(pc) + 1
            if ln != lastline:
                t = '%-60s // line %d' % (t, ln)
                lastline = ln
        out.append('    ' * (d + 1) + t)
    for L in sorted(used - pcs_emitted):
        out.append('L%d:' % L)
    return '\n'.join(out)


if __name__ == '__main__':
    R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'original')
    MODDIRS[:] = [os.path.join(R, 'extracted/america3/kimodules'), os.path.join(R, 'expansion/extracted/america8/kimodules2'),
                  os.path.join(R, '..', 'assets/campaign/base/ai'), os.path.join(R, '..', 'assets/campaign/expansion/ai')]
    for f in sys.argv[1:]:
        print(render(f))
        print()
