"""Builds Lingora's German vocab list (A1 → A2 → B1) from the Goethe-Institut word lists.

Sources
- Headwords, plurals and verb forms: Goethe PDFs (parsed by parse_pdf.py → pdf_entries.json)
- Example sentences (+ English translation of the sentence): TSVs from ilkermeliksitki/goethe-institute-wordlist
- Fallback gender/plural: german-nouns (Wiktionary, CC BY-SA 4.0)
- Fallback Partizip II: german-verbs-dict (Apache-2.0)

Each word lands in the LOWEST level it appears in, so A2 only holds words that are new after A1, etc.
"""
import csv, glob, json, re, subprocess, sys, unicodedata, collections, hashlib

ROOT = '/home/claude'
LEVELS = ['a1', 'a2', 'b1']
ARTICLES = {'der', 'die', 'das'}
GENUS = {'m': 'der', 'f': 'die', 'n': 'das'}

pdf = json.load(open(f'{ROOT}/vocab/pdf_entries.json'))

# ---------- verb dictionary (Partizip II) ----------
verbs_dict = json.loads(subprocess.check_output(
    ['node', '-e', "const v=require('german-verbs-dict/dist/verbs.json');const o={};for(const k in v){o[k]=v[k].PA2}console.log(JSON.stringify(o))"],
    cwd=f'{ROOT}/vdata'))

# ---------- nouns (Wiktionary) ----------
nouns = {}
with open(f'{ROOT}/vocab/gn/german_nouns/nouns.csv', newline='') as f:
    for row in csv.DictReader(f):
        lem = row['lemma']
        if lem in nouns or 'Substantiv' not in row['pos']:
            continue
        g = [row.get(k) for k in ('genus', 'genus 1', 'genus 2', 'genus 3') if row.get(k)]
        pls = [row.get(k) for k in ('nominativ plural', 'nominativ plural*', 'nominativ plural 1', 'nominativ plural 2', 'nominativ plural 3') if row.get(k)]
        pl = pls[0] if pls else ''
        sg = row.get('nominativ singular') or row.get('nominativ singular 1') or ''
        nouns[lem] = {'genus': g, 'plural': pl, 'plurals': pls, 'hasSg': bool(sg)}

# ---------- Perfekt auxiliary ----------
SEIN_BASE = {
    'gehen', 'kommen', 'fahren', 'laufen', 'fliegen', 'fallen', 'steigen', 'springen', 'rennen', 'reisen',
    'bleiben', 'sein', 'werden', 'sterben', 'wachsen', 'passieren', 'geschehen', 'gelingen', 'misslingen',
    'begegnen', 'folgen', 'landen', 'starten', 'wandern', 'schwimmen', 'joggen', 'klettern', 'segeln', 'reiten',
    'aufstehen', 'aufwachen', 'einschlafen', 'erscheinen', 'verschwinden', 'entstehen', 'aufwachsen', 'umziehen',
    'ausziehen', 'einziehen', 'ankommen', 'abfahren', 'losfahren', 'zurückkehren', 'auswandern', 'einwandern',
    'explodieren', 'verreisen', 'rutschen', 'stürzen', 'sinken', 'schmelzen', 'gleiten', 'kriechen', 'eilen',
    'aufhören', 'platzen', 'rasen', 'stolpern', 'wechseln', 'ausfallen', 'einfallen', 'auffallen', 'gefallen',
    'zunehmen', 'abnehmen', 'aussteigen', 'einsteigen', 'umsteigen', 'vorkommen', 'zusammenstoßen', 'ausgehen',
}
HABEN_ONLY = {  # prefixed forms of sein-verbs that take haben
    'verstehen', 'bestehen', 'gestehen', 'entstehen_no', 'bekommen', 'verbringen', 'gefallen', 'aufhören',
    'zunehmen', 'abnehmen', 'begehen', 'vergehen_no', 'erfahren', 'befahren', 'verfahren', 'unterlaufen_no',
    'überfahren', 'übergehen_no', 'umgehen_no', 'verlaufen', 'befolgen', 'verfolgen', 'überholen', 'erreichen',
    'verlassen', 'anziehen', 'ausziehen_cloth', 'beziehen', 'erziehen', 'vorziehen', 'überziehen', 'unterziehen',
    'verfliegen_no', 'besteigen', 'ersteigen', 'übersteigen', 'bewachsen', 'verwechseln', 'auswechseln', 'abwechseln',
}
SEPARABLE = ['zurück', 'zusammen', 'weiter', 'vorbei', 'heraus', 'herein', 'hinaus', 'hinein', 'herunter', 'hinunter',
             'heraus', 'heim', 'fort', 'los', 'mit', 'nach', 'vor', 'weg', 'zu', 'ab', 'an', 'auf', 'aus', 'bei', 'ein',
             'um', 'durch', 'über', 'unter', 'wieder', 'statt', 'teil', 'fest', 'fern', 'frei', 'hin', 'her', 'kennen',
             'spazieren', 'Rad ', 'Auto ']
INSEP = ('be', 'ge', 'er', 'ver', 'zer', 'ent', 'emp', 'miss')


def guess_aux(inf):
    if inf in HABEN_ONLY:
        return 'hat'
    if inf in SEIN_BASE:
        return 'ist'
    for p in SEPARABLE:
        p = p.strip()
        if inf.startswith(p) and inf[len(p):] in SEIN_BASE and len(inf) > len(p) + 2:
            return 'ist'
    if inf.startswith(INSEP):  # be-/ver-/er- verbs are almost always haben
        return 'hat'
    return 'hat'


# ---------- helpers ----------
def clean(s):
    s = s.replace('­', '').replace('–', '-').replace('—', '-').replace('’', "'")
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def strip_notes(s):
    s = re.sub(r'\((?:D|A|CH|D,\s*A|D,\s*CH|A,\s*CH|D,\s*A,\s*CH)\)', '', s)
    s = re.sub(r'→.*$', '', s)
    s = re.sub(r'\s*\(\d+\)\s*$', '', s)
    s = re.sub(r'(?<=\S)\d\.?$', '', s)        # "-en1." → "-en"
    return clean(s)


UML = {'a': 'ä', 'o': 'ö', 'u': 'ü', 'A': 'Ä', 'O': 'Ö', 'U': 'Ü'}


def umlaut(w):
    m = re.search(r'(au|Au)(?!.*[aouAOU])', w)
    if m:
        return w[:m.start()] + ('äu' if m.group(1) == 'au' else 'Äu') + w[m.end():]
    for i in range(len(w) - 1, -1, -1):
        if w[i] in UML:
            return w[:i] + UML[w[i]] + w[i + 1:]
    return w


def apply_plural(word, note):
    note = note.strip().replace(' ', '')
    if note in ('-', '–'):
        return word
    um = '¨' in note or note.startswith('-ä') or note.startswith('-ö') or note.startswith('-ü') or note.startswith('ä')
    suffix = re.sub(r'[¨\-äöü,]', '', note)
    base = umlaut(word) if um else word
    if not re.fullmatch(r'[a-zäöüß]*', suffix):
        return None
    return base + suffix


def key(s):
    s = unicodedata.normalize('NFC', s.lower())
    return re.sub(r'[^a-zäöüß ]', '', s).strip()


ARTICLE_FIX = {'Kursleiter': ['der'], 'Tropfen': ['der'], 'Zünder': ['der'], 'Teil': ['der', 'das']}
ADJ_NOUNS = {'Bekannte', 'Erwachsene', 'Jugendliche', 'Verwandte', 'Angehörige', 'Angestellte', 'Studierende', 'Deutsche', 'Kranke', 'Beamte', 'Arbeitslose', 'Alte', 'Fremde', 'Reisende', 'Auszubildende', 'Vorsitzende', 'Selbstständige', 'Selbständige'}


def choose_plural(lemma, pdf_pl, n):
    variants = (n or {}).get('plurals') or []
    if not pdf_pl:
        return variants[0] if variants else None
    if not variants or pdf_pl in variants:
        return pdf_pl
    glitch = (pdf_pl.startswith(lemma) and len(pdf_pl) - len(lemma) >= 4 and re.search(r'(der|die|das)$', pdf_pl)) \
        or (pdf_pl == lemma + 'en' and re.search(r'([aeiou]|um|is)$', lemma)) \
        or (pdf_pl == lemma + 'a' and lemma.endswith('um')) \
        or (pdf_pl == lemma and re.search(r'(ion|ung|keit|heit)$', lemma)) \
        or pdf_pl.endswith('nen') and not lemma.endswith('in')
    return variants[0] if glitch else pdf_pl


# ---------- parse entries ----------
NOUN_RE = re.compile(r'^(der|die|das)(?:/(der|die|das))?\s+([A-ZÄÖÜ][\w\-äöüß/]*)(.*)$')
PERF_RE = re.compile(r'\b(hat|ist|hat/ist|ist/hat)\s+(?:sich\s+)?([a-zäöüß]+(?:ge|)[a-zäöüß]*)\s*$')
JUNK = re.compile(r'^(\d|•|[A-ZÄÖÜ]$|[A-ZÄÖÜ] |WORTLISTE|Seite|Goethe|z\. ?B|=|\(|-|D, A|bung|aufgeführt)')


def parse_entry(raw):
    s = strip_notes(raw)
    if not s or JUNK.match(s) or len(s) > 90:
        return None
    m = NOUN_RE.match(s)
    if m:
        art, art2, word, rest = m.group(1), m.group(2), m.group(3), m.group(4)
        word = word.split('/')[0].rstrip(',').rstrip('-')
        if len(word) < 2:
            return None
        rest = rest.strip()
        pl_only = '(Pl' in rest or 'Plural' in rest
        sg_only = '(Sg' in rest
        plural = None
        pm = re.match(r'^,\s*([¨\-äöü][^\s(,]*(?:,\s*[a-zäöü]+\b)?)', rest)
        if pm and not pl_only:
            plural = apply_plural(word, pm.group(1))
        arts = [art] + ([art2] if art2 else [])
        return {'pos': 'noun', 'lemma': word, 'arts': arts, 'plural': plural, 'plOnly': pl_only, 'sgOnly': sg_only}
    # verbs: "abfahren, fährt ab, fuhr ab, ist abgefahren" / "sich bemühen, ..." / "beschweren (sich), ..."
    first = s.split(',')[0].strip()
    refl = first.startswith('sich ') or '(sich)' in first
    inf = first.replace('(sich)', '').replace('sich ', '').strip()
    inf = re.sub(r'^\((\w+)\)', r'\1', inf)            # "(ab)fahren" → "abfahren"
    inf = re.sub(r'\s*\(\d+\)$', '', inf)
    if re.fullmatch(r'[a-zäöüß]+(?:en|ern|eln|n)', inf) and (inf in verbs_dict or ',' in s or PERF_RE.search(s)):
        perf = None
        pm = PERF_RE.search(s)
        if pm and ',' in s:
            aux = pm.group(1).replace('ist/hat', 'hat/ist')
            part = pm.group(2)
            known = verbs_dict.get(inf)
            if (known and part in known) or (not known and 'ge' in part):
                perf = f'{aux} {part}'
        return {'pos': 'verb', 'lemma': inf, 'refl': refl, 'perf': perf}
    if re.fullmatch(r'[a-zäöüßA-ZÄÖÜ][\w\-äöüß.\' /]*', s) and len(s.split()) <= 4:
        word = re.sub(r'\s*\(\d+\)$', '', s.split(',')[0]).strip()
        if len(word) < 2 or word.isupper():
            return None
        return {'pos': 'other', 'lemma': word}
    return None


# ---------- examples from TSVs ----------
examples = collections.defaultdict(dict)
for lv in LEVELS:
    files = [f'{ROOT}/gwl/{lv}/a1.tsv'] if lv == 'a1' else sorted(glob.glob(f'{ROOT}/gwl/{lv}/[a-z].tsv'))
    for fn in files:
        for line in open(fn, encoding='utf-8'):
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 3 or parts[0] == 'german word' or not parts[1].strip():
                continue
            e = parse_entry(parts[0])
            if not e:
                continue
            k = (e['pos'] if e['pos'] != 'other' else 'other', key(e['lemma']))
            examples[lv].setdefault(k, (clean(parts[1]), clean(parts[2])))

# ---------- merge ----------
participles = {p for v in verbs_dict.values() for p in (v or [])}
PAGES = {'a1': (8, 26), 'a2': (7, 30), 'b1': (15, 101)}
tsv_keys = set()
for lv in LEVELS:
    tsv_keys |= {k[1] for k in examples[lv]}
words = {}
order = 0
for lv in LEVELS:
    for page, raw in pdf[lv]:
        if not (PAGES[lv][0] <= page <= PAGES[lv][1]):
            continue
        e = parse_entry(raw)
        if e and e['pos'] == 'other':
            lem = e['lemma']
            if key(lem) not in tsv_keys or lem[0].isupper() or lem in participles:
                continue
            if lem.split()[0] in ARTICLES:
                continue
        if not e:
            continue
        k = (e['pos'], key(e['lemma']))
        if not k[1]:
            continue
        if k in words:
            w = words[k]
            # later lists often add forms the earlier list left out
            if e['pos'] == 'noun' and not w.get('plural') and e.get('plural'):
                w['plural'] = e['plural']
            if e['pos'] == 'verb' and not w.get('perf') and e.get('perf'):
                w['perf'] = e['perf']
            continue
        e['level'] = lv.upper()
        e['order'] = order
        order += 1
        words[k] = e

# also pick up TSV-only headwords the PDF parser missed
for lv in LEVELS:
    for k in examples[lv]:
        if k not in words and k[1] and len(k[1]) > 1:
            pass  # PDF is the source of truth for headwords; TSVs only add examples

# ---------- enrich ----------
out = []
conflicts = []
missing = collections.Counter()
for k, w in words.items():
    item = {'level': w['level'], 'pos': w['pos'], 'de': w['lemma']}
    if w['pos'] == 'noun':
        n = nouns.get(w['lemma'])
        arts = w['arts']
        if n and n['genus']:
            wik = [GENUS[g] for g in n['genus'] if g in GENUS]
            if wik and arts[0] not in wik:
                missing['article-conflict'] += 1
                conflicts.append((w['lemma'], arts, wik))
        if w['lemma'] in ARTICLE_FIX:
            arts = ARTICLE_FIX[w['lemma']]
        elif re.search(r'(ene|ige|ende|te)$', w['lemma']) and n and 'f' in n['genus'] and arts[0] in ('der', 'die') and w['lemma'] in ADJ_NOUNS:
            arts = ['der', 'die']
        item['article'] = arts[0]
        if len(arts) > 1:
            item['articles'] = arts
        if w.get('plOnly') or (n and not n['hasSg'] and n['plural']):
            item['pluralOnly'] = True
            item['article'] = 'die'
        else:
            wik_pl = n['plural'] if n else None
            pdf_pl = w.get('plural')
            pl = choose_plural(w['lemma'], pdf_pl, n)
            if wik_pl and pdf_pl and pl != pdf_pl:
                conflicts.append((w['lemma'], pdf_pl, '->', pl))
            if w.get('sgOnly') or (n and not n['plural'] and not w.get('plural')):
                item['plural'] = None
            elif pl:
                item['plural'] = pl
            else:
                missing['plural'] += 1
                continue  # skip nouns we can't give a plural for
    elif w['pos'] == 'verb':
        perf = w.get('perf')
        if not perf:
            pa2 = (verbs_dict.get(w['lemma']) or [None])[0]
            if not pa2:
                missing['perfekt'] += 1
                continue
            perf = f"{guess_aux(w['lemma'])} {pa2}"
        if w.get('refl'):
            item['reflexive'] = True
            item['de'] = 'sich ' + w['lemma']
            if ' sich ' not in perf:
                aux, _, part = perf.partition(' ')
                perf = f'{aux} sich {part}'
        item['perfekt'] = perf
    ex = None
    for lv in LEVELS:
        ex = examples[lv].get(k)
        if ex:
            break
    if ex:
        item['example'], item['exampleEn'] = ex
    item['id'] = hashlib.sha1(f"{w['pos']}|{w['lemma']}".encode()).hexdigest()[:10]
    out.append(item)

out.sort(key=lambda x: (LEVELS.index(x['level'].lower()), x['de'].lower()))
counts = collections.Counter((x['level'], x['pos']) for x in out)
for c in conflicts: print('conflict', c, file=sys.stderr)
print('total', len(out), dict(sorted(counts.items())), dict(missing), file=sys.stderr)
json.dump({'source': 'Goethe-Institut Wortlisten A1/A2/B1', 'words': out},
          open(sys.argv[1] if len(sys.argv) > 1 else f'{ROOT}/vocab/vocab_de.json', 'w'),
          ensure_ascii=False, separators=(',', ':'))
