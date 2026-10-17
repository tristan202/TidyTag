"""Merges a JSON file {danish text: {lang: text}} into languages/src/translations.json,
then lists texts of languages/TidyTag.pot that still have no translation.

    python tools/addtranslations.py new.json      (run tools/mkpot.py afterwards)
    python tools/addtranslations.py               (only list missing texts)
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import mkpot  # noqa: E402

TABLE = os.path.join(ROOT, 'languages', 'src', 'translations.json')
# design-time captions that are replaced at run time
PLACEHOLDERS = {'vars', 'summary', 'TidyTag', 'help', 'info', 'fil'}

table = json.load(open(TABLE, encoding='utf-8'))
if len(sys.argv) > 1:
    new = json.load(open(sys.argv[1], encoding='utf-8'))
    table.update(new)
    json.dump(table, open(TABLE, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'{len(new)} texts added')
pot, _ = mkpot.read_po(os.path.join(ROOT, 'languages', 'TidyTag.pot'))
missing = []
for (_, msgid) in pot:
    k = msgid.replace('\r\n', '\n')
    if k not in table and k not in PLACEHOLDERS and k not in missing:
        missing.append(k)
for k in missing:
    print('missing:', repr(k))
