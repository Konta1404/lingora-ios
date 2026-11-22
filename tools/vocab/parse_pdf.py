import pdfplumber, collections, json, re, sys

CFG = {
    'a1': [(130, 236)],
    'a2': [(30, 105), (300, 374)],
    'b1': [(30, 131), (310, 410)],
}

def entries(level):
    out = []
    with pdfplumber.open(f'/home/claude/gwl/pdf-files/{level}.pdf') as pdf:
        for pno, pg in enumerate(pdf.pages):
            ws = [w for w in pg.extract_words(keep_blank_chars=False) if w['x0'] > 25 and w['top'] > 40 and w['top'] < 790]
            for (lo, hi) in CFG[level]:
                lines = collections.defaultdict(list)
                for w in ws:
                    if lo <= w['x0'] < hi:
                        lines[round(w['top'])].append(w)
                cur = None; last_top = None
                for t in sorted(lines):
                    words = sorted(lines[t], key=lambda w: w['x0'])
                    # first word must start near the column's left edge
                    if words[0]['x0'] > lo + 40:
                        continue
                    text = ' '.join(w['text'] for w in words)
                    cont = cur is not None and last_top is not None and t - last_top <= 12.5 and (cur.rstrip().endswith(',') or cur.rstrip().endswith('-'))
                    if cont:
                        cur = cur[:-1] + text if cur.rstrip().endswith('-') and not cur.rstrip().endswith(' -') else cur + ' ' + text
                    else:
                        if cur: out.append((pno, cur))
                        cur = text
                    last_top = t
                if cur: out.append((pno, cur))
    return out

if __name__ == '__main__':
    res = {lv: entries(lv) for lv in CFG}
    json.dump(res, open('/home/claude/vocab/pdf_entries.json', 'w'), ensure_ascii=False, indent=0)
    for lv, e in res.items():
        print(lv, len(e))
        for x in e[200:215]: print('   ', x)
