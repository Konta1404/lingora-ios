"""Builds Lingora/Localizable.xcstrings from translations.tsv and checks every L("…") key in the app is covered.

translations.tsv columns: key, sr-Latn, de, es, fr, it, pt-BR, ru  (English text = key unless listed in EN below)
Run: python3 tools/l10n/build_catalog.py
"""
import json, re, glob, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LANGS = ['sr-Latn', 'de', 'es', 'fr', 'it', 'pt-BR', 'ru']
EN = {
    'Splitting %lld min across %lld (languages)': 'Splitting %1$lld min a day across your languages',
}
# Plural variations: key -> {lang: {category: value}}
PLURALS = {
    '%lld days': {
        'en': {'one': '%lld day', 'other': '%lld days'},
        'sr-Latn': {'one': '%lld dan', 'few': '%lld dana', 'other': '%lld dana'},
        'de': {'one': '%lld Tag', 'other': '%lld Tage'},
        'es': {'one': '%lld día', 'other': '%lld días'},
        'fr': {'one': '%lld jour', 'other': '%lld jours'},
        'it': {'one': '%lld giorno', 'other': '%lld giorni'},
        'pt-BR': {'one': '%lld dia', 'other': '%lld dias'},
        'ru': {'one': '%lld день', 'few': '%lld дня', 'many': '%lld дней', 'other': '%lld дня'},
    },
    '%lld days left': {
        'en': {'one': '%lld day left', 'other': '%lld days left'},
        'sr-Latn': {'one': 'Još %lld dan', 'few': 'Još %lld dana', 'other': 'Još %lld dana'},
        'de': {'one': 'Noch %lld Tag', 'other': 'Noch %lld Tage'},
        'es': {'one': 'Queda %lld día', 'other': 'Quedan %lld días'},
        'fr': {'one': '%lld jour restant', 'other': '%lld jours restants'},
        'it': {'one': 'Manca %lld giorno', 'other': 'Mancano %lld giorni'},
        'pt-BR': {'one': 'Falta %lld dia', 'other': 'Faltam %lld dias'},
        'ru': {'one': 'Остался %lld день', 'few': 'Осталось %lld дня', 'many': 'Осталось %lld дней', 'other': 'Осталось %lld дня'},
    },
    'Continue with %lld (languages)': {
        'en': {'one': 'Continue with %lld language', 'other': 'Continue with %lld languages'},
        'sr-Latn': {'one': 'Nastavi sa %lld jezikom', 'few': 'Nastavi sa %lld jezika', 'other': 'Nastavi sa %lld jezika'},
        'de': {'one': 'Weiter mit %lld Sprache', 'other': 'Weiter mit %lld Sprachen'},
        'es': {'one': 'Continuar con %lld idioma', 'other': 'Continuar con %lld idiomas'},
        'fr': {'one': 'Continuer avec %lld langue', 'other': 'Continuer avec %lld langues'},
        'it': {'one': 'Continua con %lld lingua', 'other': 'Continua con %lld lingue'},
        'pt-BR': {'one': 'Continuar com %lld idioma', 'other': 'Continuar com %lld idiomas'},
        'ru': {'one': 'Продолжить: %lld язык', 'few': 'Продолжить: %lld языка', 'many': 'Продолжить: %lld языков', 'other': 'Продолжить: %lld языка'},
    },
}


def unit(v):
    return {'stringUnit': {'state': 'translated', 'value': v}}


def main():
    rows = {}
    for line in open(os.path.join(ROOT, 'tools/l10n/translations.tsv'), encoding='utf-8'):
        line = line.rstrip('\n')
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) != 1 + len(LANGS):
            sys.exit(f'bad row ({len(parts)} cols): {parts[0]!r}')
        rows[parts[0]] = dict(zip(LANGS, parts[1:]))

    used = []
    for f in glob.glob(os.path.join(ROOT, 'Lingora/**/*.swift'), recursive=True):
        for m in re.finditer(r'\bL\(\s*"((?:[^"\\]|\\.)*)"', open(f, encoding='utf-8').read()):
            used.append(m.group(1))
    used += ['Travel', 'Work', 'Exams', 'Conversation', 'Culture & media', 'Moving abroad', 'Family']
    missing = sorted({k for k in used if k not in rows and k not in PLURALS})
    if missing:
        sys.exit('Missing translations:\n  ' + '\n  '.join(missing))

    def nfmt(s):
        return len(re.findall(r'%(?:\d\$)?(?:@|lld|d)', s))

    strings = {}
    for key, tr in rows.items():
        loc = {'en': unit(EN.get(key, key))}
        for lang, v in tr.items():
            if nfmt(v) > nfmt(key):
                sys.exit(f'{lang}: too many format specifiers in {key!r}')
            loc[lang] = unit(v)
        strings[key] = {'extractionState': 'manual', 'localizations': dict(sorted(loc.items()))}
    for key, by_lang in PLURALS.items():
        strings[key] = {'extractionState': 'manual', 'localizations': {
            lang: {'variations': {'plural': {cat: unit(v) for cat, v in sorted(cats.items())}}} for lang, cats in sorted(by_lang.items())}}

    catalog = {'sourceLanguage': 'en', 'strings': dict(sorted(strings.items())), 'version': '1.0'}
    out = os.path.join(ROOT, 'Lingora/Localizable.xcstrings')
    with open(out, 'w', encoding='utf-8') as fh:
        # Same layout Xcode writes, so opening the project doesn't rewrite the whole file.
        json.dump(catalog, fh, ensure_ascii=False, indent=2, separators=(',', ' : '))
        fh.write('\n')
    unused = sorted(set(rows) - set(used))
    print(f'{len(strings)} keys × {len(LANGS) + 1} languages → {os.path.relpath(out, ROOT)}')
    if unused:
        print('unused keys:', unused)


if __name__ == '__main__':
    main()
