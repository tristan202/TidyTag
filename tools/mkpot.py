"""Builds languages/TidyTag.pot and updates languages/TidyTag.<lang>.po.

Sources: the .rsj files the compiler writes for every unit with resourcestrings
(run lazbuild first) and the string properties of the forms (.lfm).
Existing translations are kept (matched on msgctxt + msgid, then on msgid alone);
entries whose text disappeared are dropped.

    python tools/mkpot.py            (from the project folder)
"""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, 'lib', 'x86_64-win64')
SRC = os.path.join(ROOT, 'src')
OUT = os.path.join(ROOT, 'languages')
PROPS = ('Caption', 'Hint', 'Title', 'Filter', 'TextHint')


def rsj_entries():
    out = []
    for path in sorted(glob.glob(os.path.join(LIB, '*.rsj'))):
        data = json.load(open(path, encoding='utf-8'))
        for s in data['strings']:
            value = bytes(s['sourcebytes']).decode('utf-8')
            out.append((s['name'].lower(), value))
    return out


def lfm_value(text):
    """Decodes 'abc'#248'def' (code points) into a Python string."""
    out = ''
    for m in re.finditer(r"'((?:[^']|'')*)'|#(\d+)", text):
        out += chr(int(m.group(2))) if m.group(2) else m.group(1).replace("''", "'")
    return out


def lfm_entries():
    out = []
    for path in sorted(glob.glob(os.path.join(SRC, '*.lfm'))):
        lines = open(path, encoding='utf-8').read().split('\n')
        stack, form, i = [], '', 0
        counters = []
        while i < len(lines):
            s = lines[i].strip()
            m = re.match(r'(object|inherited|inline)\s+(\w+)\s*:\s*(\w+)', s)
            if m:
                if not stack:
                    form = m.group(3)
                    stack.append(form)
                else:
                    stack.append(m.group(2))
            elif s == 'item':
                n = counters[-1] if counters else 0
                stack.append(f'item{n}')
                if counters:
                    counters[-1] += 1
            elif re.match(r'\w+ = <$', s):
                counters.append(0)
            elif s.endswith('>') and re.match(r'^(end>|>)', s) is None and s == '>':
                counters.pop()
            elif s in ('end', 'end>'):
                if stack:
                    stack.pop()
                if s == 'end>' and counters:
                    counters.pop()
            else:
                m = re.match(r'(\w+) = (.*)$', s)
                if m and m.group(1) in PROPS and (m.group(2).startswith("'") or m.group(2).startswith('#')):
                    raw = m.group(2)
                    while raw.rstrip().endswith('+'):
                        i += 1
                        raw = raw.rstrip()[:-1] + lines[i].strip()
                    value = lfm_value(raw)
                    if re.search(r'[A-Za-zÀ-ÿ]', value):
                        ident = '.'.join(stack[:1] + stack[1:] + [m.group(1)]).lower()
                        out.append((ident, value))
            i += 1
    return out


def esc(s):
    # Lazarus' po reader knows \n but not \r, so line breaks are written as \n only
    s = s.replace('\r\n', '\n')
    return (s.replace('\\', '\\\\').replace('"', '\\"').replace('\r', '\\r')
            .replace('\n', '\\n').replace('\t', '\\t'))


def unesc(s):
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 'r': '\r', 't': '\t'}.get(m.group(1), m.group(1)), s)


def read_po(path):
    """({(msgctxt, msgid): msgstr}, {msgid: msgstr}) of a po file (blocks separated by blank lines)."""
    entries = {}
    text = open(path, encoding='utf-8').read() if os.path.exists(path) else ''
    for block in re.split(r'\n\s*\n', text):
        cur, key = {}, None
        for line in block.split('\n'):
            line = line.strip()
            m = re.match(r'(msgctxt|msgid|msgstr) "(.*)"$', line)
            if m:
                key = m.group(1)
                cur[key] = unesc(m.group(2))
            elif line.startswith('"') and key:
                cur[key] += unesc(line[1:-1])
        if cur.get('msgid'):
            entries[(cur.get('msgctxt', ''), cur['msgid'])] = cur.get('msgstr', '')
    by_id = {}
    for (c, i), v in entries.items():
        if v and i not in by_id:
            by_id[i] = v
    return entries, by_id


def header(lang):
    h = ('msgid ""\nmsgstr ""\n"Content-Type: text/plain; charset=UTF-8\\n"\n'
         '"Content-Transfer-Encoding: 8bit\\n"\n"Project-Id-Version: TidyTag\\n"\n')
    if lang:
        h += f'"Language: {lang}\\n"\n'
    return h + '\n'


def write(path, entries, lang, translations=None):
    counts = {}
    for _, v in entries:
        counts[v] = counts.get(v, 0) + 1
    tr_full, tr_id = translations or ({}, {})
    done = 0
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(header(lang))
        for ident, value in entries:
            ctxt = ident if counts[value] > 1 else ''
            msgstr = ''
            if translations:
                msgstr = tr_full.get((ctxt, value)) or tr_id.get(value, '')
                done += bool(msgstr)
            f.write(f'#: {ident}\n')
            if ctxt:
                f.write(f'msgctxt "{esc(ctxt)}"\n')
            f.write(f'msgid "{esc(value)}"\nmsgstr "{esc(msgstr)}"\n\n')
    return done


def main():
    entries = rsj_entries() + lfm_entries()
    seen, unique = set(), []
    for ident, value in entries:
        if ident not in seen and value.strip():
            seen.add(ident)
            unique.append((ident, value))
    os.makedirs(OUT, exist_ok=True)
    write(os.path.join(OUT, 'TidyTag.pot'), unique, '')
    print(f'TidyTag.pot: {len(unique)} entries, {len(set(v for _, v in unique))} distinct texts')
    # translations: languages/src/translations.json {danish text: {lang: text}} (line breaks
    # as \n); texts missing there keep what the po file already has
    tj = os.path.join(OUT, 'src', 'translations.json')
    table = json.load(open(tj, encoding='utf-8')) if os.path.exists(tj) else {}
    langs = sorted(set(['da'] + [l for d in table.values() for l in d] +
                       [p.split('.')[-2] for p in glob.glob(os.path.join(OUT, 'TidyTag.*.po'))]))
    fmt = re.compile(r'%[dsx]|%\.\d+x')
    for lang in langs:
        path = os.path.join(OUT, f'TidyTag.{lang}.po')
        full, by_id = read_po(path)
        for _, value in unique:
            t = table.get(value.replace('\r\n', '\n'), {}).get(lang)
            if t:
                if '\r\n' in value:
                    t = t.replace('\n', '\r\n')
                if sorted(fmt.findall(t)) != sorted(fmt.findall(value)):
                    print(f'  {lang}: format codes differ: {value[:50]!r}')
                    continue
                by_id[value] = t
                full = {k: v for k, v in full.items() if k[1] != value}
        done = write(path, unique, lang, (full, by_id))
        print(f'{os.path.basename(path)}: {done}/{len(unique)} translated')


if __name__ == '__main__':
    main()
