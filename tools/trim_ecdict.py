"""Trim ECDICT to a classroom dictionary: common words, phrases made of them, Chinese senses, word forms.
Output TSV: word \t senses (joined by ' | ') \t exchange"""
import csv, sys, re
src, out = sys.argv[1], sys.argv[2]
LIMIT = int(sys.argv[3]) if len(sys.argv) > 3 else 40000
rows = []
with open(src, encoding='utf-8', newline='') as f:
    for r in csv.DictReader(f):
        rows.append(r)
def num(x):
    try: return int(x)
    except: return 0
def common(r):
    b, q = num(r['bnc']), num(r['frq'])
    return (0 < b <= LIMIT) or (0 < q <= LIMIT) or bool(r['tag'].strip()) or r['oxford'] == '1' or num(r['collins']) > 0
word_ok = re.compile(r"^[A-Za-z][A-Za-z'\-]*$")
singles = {}
for r in rows:
    w = r['word'].strip()
    if ' ' in w or not word_ok.match(w) or not r['translation'].strip(): continue
    if common(r): singles[w] = r
lower = {w.lower() for w in singles}
CORE = int(sys.argv[4]) if len(sys.argv) > 4 else 12000
def core(r):
    b, q = num(r['bnc']), num(r['frq']); tags = r['tag'].split()
    return (0 < b <= CORE) or (0 < q <= CORE) or any(t in ('zk', 'gk', 'cet4') for t in tags)
core_words = {w.lower() for w, r in singles.items() if core(r)}
def senses(t):
    lines = [l.strip() for l in t.replace('\\n', '\n').split('\n') if l.strip()]
    plain = [l for l in lines if not l.startswith('[')]
    if not plain: plain = [l.replace('[网络]', '').strip() for l in lines]
    return [l for l in plain if l][:5]
phrases = {}
for r in rows:
    w = r['word'].strip()
    toks = w.split(' ')
    if not (2 <= len(toks) <= 4) or not all(word_ok.match(t) for t in toks): continue
    if not r['translation'].strip(): continue
    if not all(t.lower() in core_words for t in toks): continue
    if all(l.strip().startswith('[') for l in r['translation'].replace('\\n', '\n').split('\n') if l.strip()): continue
    if any(c.isupper() for c in w): continue
    phrases[w] = r
with open(out, 'w', encoding='utf-8') as f:
    for w, r in sorted({**singles, **phrases}.items(), key=lambda kv: kv[0].lower()):
        s = senses(r['translation'])
        if not s: continue
        f.write(w + '\t' + ' | '.join(x.replace('\t', ' ') for x in s) + '\t' + r['exchange'].strip() + '\n')
print('singles', len(singles), 'phrases', len(phrases))
