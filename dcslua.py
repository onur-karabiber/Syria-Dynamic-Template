# dcslua.py | v1.0.0
# DCS'in düz Lua veri dosyalarını (mission, options, warehouses, dictionary,
# mapResource: "ad = { [anahtar] = değer, ... }") bağımlılıksız okur ve
# anahtar sırasına göre sıralı, deterministik biçimde yazar.
#
# Amaç: ME her kaydedişte tabloları farklı sırayla yazdığı için ham dosyaların
# git diff'i yüz binlerce satır gürültü içerir. Sıralı yazım aynı VERİYİ verir,
# sadece anahtar sırası sabitlenir. Diziler ([1], [2], ...) açık indeks
# anahtarlarıyla yazılır ve elemanların sırası değiştirilmez.
#
# Her şey bytes üzerinde çalışır (string'ler bytes, dosya kodlamasından bağımsız).
# Desteklenmeyen sözdizimi LuaError fırlatır; çağıran ham dosyaya dönebilir.

import math
import re
import sys

sys.setrecursionlimit(10000)


class LuaError(Exception):
    pass


_NUM = re.compile(rb'[-+]?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)')
_IDENT = re.compile(rb'[A-Za-z_][A-Za-z0-9_]*')
_STR_RUN = {34: re.compile(rb'[^\\\r\n"]*'), 39: re.compile(rb"[^\\\r\n']*")}
_ESC = {ord('n'): 10, ord('t'): 9, ord('r'): 13, ord('a'): 7, ord('b'): 8,
        ord('f'): 12, ord('v'): 11, ord('\\'): 92, ord('"'): 34, ord("'"): 39}
_NIL = object()
_INT_MAX = 2 ** 63 - 1


def _norm_key(k):
    if isinstance(k, float) and k == int(k):
        return int(k)
    return k


class _Parser:
    def __init__(self, data):
        self.d = data
        self.i = 0

    def err(self, msg):
        line = self.d.count(b'\n', 0, self.i) + 1
        raise LuaError("%s (satır %d)" % (msg, line))

    def skip(self):
        d, i, n = self.d, self.i, len(self.d)
        while i < n:
            c = d[i]
            if c in b' \t\r\n':
                i += 1
            elif d.startswith(b'--', i):
                if d.startswith(b'--[[', i):
                    j = d.find(b']]', i + 4)
                    if j < 0:
                        self.i = i
                        self.err("kapanmamış uzun yorum")
                    i = j + 2
                elif d.startswith(b'--[=', i):
                    self.i = i
                    self.err("desteklenmeyen uzun yorum")
                else:
                    j = d.find(b'\n', i)
                    i = n if j < 0 else j + 1
            else:
                break
        self.i = i

    def peek(self):
        self.skip()
        if self.i >= len(self.d):
            self.err("beklenmedik dosya sonu")
        return self.d[self.i]

    def expect(self, ch):
        if self.peek() != ord(ch):
            self.err("'%s' bekleniyordu" % ch)
        self.i += 1

    def value(self):
        c = self.peek()
        if c == ord('{'):
            return self.table()
        if c in (34, 39):
            return self.string()
        if c == ord('-') or c == ord('+') or c == ord('.') or 48 <= c <= 57:
            return self.number()
        m = _IDENT.match(self.d, self.i)
        if m:
            w = m.group()
            if w == b'true':
                self.i = m.end(); return True
            if w == b'false':
                self.i = m.end(); return False
            if w == b'nil':
                self.i = m.end(); return _NIL
        self.err("desteklenmeyen değer")

    def number(self):
        m = _NUM.match(self.d, self.i)
        if not m:
            self.err("geçersiz sayı")
        s = m.group()
        self.i = m.end()
        if s[:2] in (b'0x', b'0X') or s[1:3] in (b'0x', b'0X'):
            v = int(s, 16)
            if abs(v) > _INT_MAX:
                self.err("onaltılık sayı aralık dışı")
            return v
        if b'.' in s or b'e' in s or b'E' in s:
            return float(s)
        v = int(s)
        return v if abs(v) <= _INT_MAX else float(s)

    def string(self):
        d, n = self.d, len(self.d)
        q = d[self.i]
        i = self.i + 1
        out = bytearray()
        run = _STR_RUN[q]
        while True:
            j = run.match(d, i).end()
            out += d[i:j]
            i = j
            if i >= n:
                self.err("kapanmamış string")
            c = d[i]
            if c == q:
                i += 1
                break
            if c in (10, 13):
                self.i = i
                self.err("string içinde kaçışsız satır sonu")
            i += 1                      # ters eğik çizgi
            c = d[i] if i < n else 0
            if c in _ESC:
                out.append(_ESC[c]); i += 1
            elif c == 10:
                out.append(10); i += 1
                if d[i:i + 1] == b'\r':
                    i += 1
            elif c == 13:
                out.append(10); i += 1
                if d[i:i + 1] == b'\n':
                    i += 1
            elif 48 <= c <= 57:
                j = i
                while j < i + 3 and j < n and 48 <= d[j] <= 57:
                    j += 1
                v = int(d[i:j])
                if v > 255:
                    self.i = i
                    self.err("\\ddd 255'ten büyük")
                out.append(v); i = j
            elif c == ord('x'):
                try:
                    out.append(int(d[i + 1:i + 3], 16))
                except ValueError:
                    self.i = i
                    self.err("geçersiz \\x kaçışı")
                i += 3
            else:
                self.i = i
                self.err("desteklenmeyen kaçış dizisi")
        self.i = i
        return bytes(out)

    def table(self):
        self.i += 1
        t = {}
        pos = 1
        while True:
            c = self.peek()
            if c == ord('}'):
                self.i += 1
                return t
            if c == ord('['):
                if self.d[self.i + 1:self.i + 2] in (b'[', b'='):
                    self.err("uzun string anahtar desteklenmiyor")
                self.i += 1
                k = self.value()
                self.expect(']')
                self.expect('=')
                v = self.value()
                if k is _NIL or isinstance(k, bool):
                    self.err("desteklenmeyen anahtar tipi")
                k = _norm_key(k)
            else:
                m = _IDENT.match(self.d, self.i)
                named = False
                if m and m.group() not in (b'true', b'false', b'nil'):
                    save = self.i
                    self.i = m.end()
                    if self.peek() == ord('=') and self.d[self.i + 1:self.i + 2] != b'=':
                        self.i += 1
                        k = m.group()
                        v = self.value()
                        named = True
                    else:
                        self.i = save
                if not named:
                    v = self.value()
                    k = pos
                    pos += 1
            if v is _NIL:
                t.pop(k, None)
            else:
                t[k] = v
            c = self.peek()
            if c in (ord(','), ord(';')):
                self.i += 1
            elif c != ord('}'):
                self.err("',' veya '}' bekleniyordu")

    def file(self):
        self.skip()
        m = _IDENT.match(self.d, self.i)
        if not m:
            self.err("'ad = ...' bekleniyordu")
        name = m.group().decode('ascii')
        self.i = m.end()
        self.expect('=')
        v = self.value()
        self.skip()
        if self.i < len(self.d) and self.d[self.i] == ord(';'):
            self.i += 1
            self.skip()
        if self.i != len(self.d):
            self.err("dosyanın sonunda beklenmeyen içerik")
        if v is _NIL or not isinstance(v, dict):
            self.err("üst seviye değer bir tablo değil")
        return name, v


def parse(data):
    """bytes -> (değişken adı, dict). Anahtarlar int veya bytes, string değerler bytes."""
    try:
        return _Parser(data).file()
    except (IndexError, RecursionError) as e:
        raise LuaError("ayrıştırma hatası: %r" % e)


# ---------------------------------------------------------------- yazıcı

_NEEDS_ESC = re.compile(rb'[\x00-\x1f"\\\x7f]')
_ESC_OUT = {34: b'\\"', 92: b'\\\\', 10: b'\\n', 13: b'\\r', 9: b'\\t'}


def _q(s):
    if not _NEEDS_ESC.search(s):
        return b'"' + s + b'"'
    out = bytearray(b'"')
    for c in s:
        if c in _ESC_OUT:
            out += _ESC_OUT[c]
        elif c < 32 or c == 127:
            out += b'\\%03d' % c
        else:
            out.append(c)
    out.append(34)
    return bytes(out)


def _kord(k):
    if isinstance(k, (int, float)) and not isinstance(k, bool):
        return (0, k, b'')
    if isinstance(k, bytes):
        return (1, 0, k)
    raise LuaError("beklenmeyen anahtar tipi %r" % type(k))


def _scalar(v):
    if v is True:
        return b'true'
    if v is False:
        return b'false'
    if isinstance(v, int):
        return b'%d' % v
    if isinstance(v, float):
        if math.isnan(v) or math.isinf(v):
            raise LuaError("nan/inf yazılamaz")
        return repr(v).encode('ascii')
    if isinstance(v, bytes):
        return _q(v)
    raise LuaError("beklenmeyen değer tipi %r" % type(v))


def _emit(v, ind, out):
    if isinstance(v, dict):
        out.append(b'\n' + b'\t' * ind + b'{\n')
        pad = b'\t' * (ind + 1)
        for k in sorted(v, key=_kord):
            if isinstance(k, bytes):
                ks = b'[' + _q(k) + b']'
            elif isinstance(k, int):
                ks = b'[%d]' % k
            else:
                ks = b'[' + repr(k).encode('ascii') + b']'
            out.append(pad + ks + b' = ')
            _emit(v[k], ind + 1, out)
            out.append(b',\n')
        out.append(b'\t' * ind + b'}')
    else:
        out.append(_scalar(v))


def dump(name, tbl):
    out = [name.encode('ascii'), b' = ']
    _emit(tbl, 0, out)
    out.append(b'\n')
    return b''.join(out)


def strict_diff(a, b, path=()):
    """Tip dahil derin karşılaştırma. İlk farkın (yol, a, b) değerini döndürür, yoksa None."""
    if isinstance(a, dict) != isinstance(b, dict):
        return (path, type(a).__name__, type(b).__name__)
    if isinstance(a, dict):
        if a.keys() != b.keys():
            return (path, sorted(a.keys() - b.keys(), key=str)[:3],
                    sorted(b.keys() - a.keys(), key=str)[:3])
        for k in a:
            r = strict_diff(a[k], b[k], path + (k,))
            if r:
                return r
        return None
    if type(a) is not type(b) or a != b:
        return (path, a, b)
    return None


def normalize(raw, var, verify=True):
    """Ham dosya baytları -> sıralı baytlar. verify=True: çıktıyı tekrar ayrıştırıp
    orijinal veriyle tip dahil karşılaştırır; uyuşmazlıkta LuaError."""
    name, tbl = parse(raw)
    if name != var:
        raise LuaError("değişken adı '%s', beklenen '%s'" % (name, var))
    out = dump(name, tbl)
    if verify:
        name2, tbl2 = parse(out)
        d = strict_diff(tbl, tbl2)
        if name2 != name or d:
            raise LuaError("yazım sonrası doğrulama başarısız: %r" % (d,))
    return out
