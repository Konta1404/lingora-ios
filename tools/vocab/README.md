# Building `vocab_de.json`

```bash
pip install pdfplumber
npm install --prefix ../vdata german-verbs-dict   # path used by build_vocab.py
pip download german-nouns --no-deps               # unzip so nouns.csv is available
python3 parse_pdf.py        # Goethe PDFs → pdf_entries.json
python3 build_vocab.py out.json
```

The scripts expect the Goethe word-list repo cloned next to them (see paths at the top of each script).
Copy the result to `Lingora/Resources/vocab_de.json` and `backend/functions/data/vocab_de.json`.
