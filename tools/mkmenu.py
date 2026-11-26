"""Builds renderer/menudata.js from 1.2's mainform.pas: the actions (caption, hint, shortcut),
the seven menus, the file list popup menu and the two toolbars, in 1.2's exact order.
Texts stay Danish source strings; the renderer translates them with strings.js.

    python tools/mkmenu.py        (from the project folder)
"""
import glob, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'src')
OUT = os.path.join(ROOT, 'renderer', 'menudata.js')


def pascal_string(expr):
    """'a''b' + LineEnding + #248 ... -> Python string."""
    out, i = [], 0
    while i < len(expr):
        c = expr[i]
        if c == "'":
            j = i + 1
            buf = []
            while j < len(expr):
                if expr[j] == "'":
                    if j + 1 < len(expr) and expr[j + 1] == "'":
                        buf.append("'"); j += 2; continue
                    break
                buf.append(expr[j]); j += 1
            out.append(''.join(buf)); i = j + 1
        elif c == '#':
            m = re.match(r'#(\d+)', expr[i:])
            out.append(chr(int(m.group(1)))); i += len(m.group(0))
        elif expr.startswith('LineEnding', i):
            out.append('\n'); i += len('LineEnding')
        else:
            i += 1
    return ''.join(out)


def resourcestrings():
    rs = {}
    # resourcestrings are unit-scoped: mainform.pas is read last so its own names win
    paths = sorted(glob.glob(os.path.join(SRC, '*.pas')), key=lambda p: os.path.basename(p) == 'mainform.pas')
    for path in paths:
        text = open(path, encoding='utf-8').read()
        for block in re.findall(r'resourcestring(.*?)(?:\n(?:type|const|var|function|procedure|implementation|uses)\b)', text, re.S | re.I):
            for m in re.finditer(r'^\s*(rs\w+)\s*=\s*(.*?);\s*$', block, re.M | re.S):
                rs[m.group(1).lower()] = pascal_string(m.group(2))
    return rs


VK = {'VK_BACK': 'Backspace', 'VK_RETURN': 'Enter', 'VK_DELETE': 'Del', 'VK_UP': 'Up', 'VK_DOWN': 'Down'}


def shortcut(expr):
    m = re.match(r'ShortCut\((VK_\w+),\s*\[(.*?)\]\)', expr.strip())
    if not m:
        return ''
    key = VK.get(m.group(1), m.group(1)[3:])
    mods = [{'ssCtrl': 'Ctrl', 'ssShift': 'Shift', 'ssAlt': 'Alt'}[s.strip()] for s in m.group(2).split(',') if s.strip()]
    order = [x for x in ('Ctrl', 'Shift', 'Alt') if x in mods]
    return '+'.join(order + [key])


def split_args(s):
    args, depth, cur = [], 0, ''
    for c in s:
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        if c == ',' and depth == 0:
            args.append(cur.strip()); cur = ''
        else:
            cur += c
    args.append(cur.strip())
    return args


# Phase of the TidyTag 2 plan in which an action starts to work (1 = this skeleton).
PHASE1 = {'aRefresh', 'aExit', 'aSelAll', 'aSelNone', 'aChkSel', 'aUnchkSel', 'aChkAll', 'aUnchkAll',
          'aInvert', 'FActToolsPanel', 'FActFolders', 'FActAddress', 'FActFilter', 'FActSubfolders',
          'aTabRename', 'aTabMulti', 'aTabF2T', 'aUp', 'aFav',
          'aTreeRefresh', 'aCloseFolders'}
PHASE = {'aEdit': 3, 'aMulti': 2, 'aCopy': 3, 'FActPaste': 3, 'aSwapAT': 3, 'aSwapAA': 3, 'aSwapLT': 3,
         'aSwap': 3, 'aCopyField': 3, 'aClean': 3, 'aRemoveTags': 3, 'aSync': 3, 'aTracks': 3,
         'aCoverIn': 3, 'aCoverOut': 3, 'aCoverAsFolder': 3, 'aResizeFiles': 3, 'aResizeFolders': 3,
         'aDelFolderCover': 3, 'FActAutoResize': 3, 'aRenameFolder': 4, 'aRenameDlg': 4, 'aF2TDlg': 4,
         'FActUndo': 4, 'aRenameManual': 4, 'aWords': 4, 'FActManageActions': 4, 'aWeb': 6, 'aToken': 6,
         'aReplayGain': 7, 'aRemoveRG': 7, 'aAnalyze': 7, 'aConvertKeys': 7, 'aExport': 8,
         'aPhone': 9, 'aAddPhone': 9, 'aSettings': 10, 'aGenres': 10, 'FActKeepDate': 2}
# Everything else (open dialog, play, playlists, file operations, find, about ...) is phase 5.

ICON_BY_ACTION = {'aRenameDlg': 'rename', 'aF2TDlg': 'f2t', 'aRenameFolder': 'renameFolder', 'aKeys': 'keyboard'}
ICON = {'icoOpen': 'open', 'icoRefresh': 'refresh', 'icoSearch': 'search', 'icoSubfolders': 'subfolders',
        'icoEdit': 'pencil', 'icoMultiEdit': 'tags', 'icoPreview': 'rename', 'icoCopy': 'copy',
        'icoPaste': 'paste', 'icoPlay': 'play', 'icoMoveUp': 'up', 'icoMoveDown': 'down',
        'icoTracks': 'tracks', 'icoWeb': 'cloud', 'icoExport': 'export', 'icoCheckAll': 'check',
        'icoUncheck': 'x', 'icoUndo': 'undo', 'icoHelp': 'keyboard', 'icoInfo': 'info',
        'icoFolderUp': 'folderUp', 'icoFavorites': 'star', 'icoNewFolder': 'newFolder',
        'icoClose': 'x', 'icoSave': 'save', 'icoSettings': 'settings', 'icoExit': 'exit',
        'icoRenameFiles': 'rename', 'icoFileToTag': 'f2t', 'icoRenameFolder': 'renameFolder'}


def main():
    rs = resourcestrings()
    text = open(os.path.join(SRC, 'mainform.pas'), encoding='utf-8').read()
    start = text.index('FActions.Images := ImagesMain;')
    menu_at = text.index('// ---- main menu', start)
    end = text.index('Btn(ToolBarFolders, aCloseFolders);', menu_at)
    defs = text[start:menu_at]
    flow = text[menu_at:end + len('Btn(ToolBarFolders, aCloseFolders);')]

    def val(expr):
        expr = expr.strip()
        if expr.lower() in rs:
            return rs[expr.lower()]
        if expr.startswith("'") or expr.startswith('#'):
            return pascal_string(expr)
        raise KeyError(expr)

    actions = {}
    for m in re.finditer(r'(\w+(?:\[\w+\])?)\s*:=\s*NewAction\((.*?)\);', defs, re.S):
        name = m.group(1)
        cap, hint, sc, img, _ = split_args(' '.join(m.group(2).split()))
        caption = val(cap)
        actions[name] = {
            'id': name, 'text': caption, 'hint': val(hint) if hint != "''" else caption.replace('&', ''),
            'shortcut': '' if sc == '0' else shortcut(sc),
            'icon': ICON_BY_ACTION.get(name, ICON.get(img, '')),
            'phase': 1 if name in PHASE1 else PHASE.get(name, 5),
            'check': bool(re.search(re.escape(name) + r'\.AutoCheck := True', defs)),
        }
    name_tools = [a for a in actions if a.startswith('NameTools[')]

    menus, popup, toolbar, folderbar = [], [], [], []
    stack = []  # current menu item lists
    current = None

    def item(a):
        return '-' if a == 'nil' else {'ref': a}

    for st in re.findall(r'[^;]+;', flow):
        st = st.strip()
        if st.startswith('//'):
            st = st.split('\n', 1)[-1].strip()
        m = re.match(r'TopMenu := Menu\((\w+)\);', st)
        if m:
            current = {'text': val(m.group(1)), 'items': []}
            menus.append(current); stack = [current]; continue
        m = re.match(r'(?:\w+ := )?Sub\((TopMenu|SubMenu), (\w+)\);', st)
        if m:
            sub = {'text': val(m.group(2)), 'items': []}
            parent = stack[0] if m.group(1) == 'TopMenu' else stack[-1]
            parent['items'].append(sub)
            if st.startswith('SubMenu :='):
                stack = stack[:1] + ([] if m.group(1) == 'TopMenu' else stack[1:]) + [sub]
            else:
                sub['dynamic'] = True  # filled at run time (play with, recent folders, actions)
            continue
        if st == 'SubMenu := SubMenu.Parent;':
            stack.pop(); continue
        m = re.match(r'Add\((TopMenu|SubMenu), (\w+)\);', st)
        if m:
            (stack[0] if m.group(1) == 'TopMenu' else stack[-1])['items'].append(item(m.group(2))); continue
        if st.startswith('for NT := Low(TNameTool)'):
            stack[-1]['items'].extend({'ref': n} for n in name_tools); continue
        m = re.match(r'(AddAlbumArtistMenu|AddLanguageMenu)\(TopMenu\);', st)
        if m:
            stack[0]['items'].append({'special': 'albumArtist' if m.group(1) == 'AddAlbumArtistMenu' else 'language'}); continue
        m = re.match(r'AddPopup\((\w+)\);', st)
        if m:
            popup.append(item(m.group(1))); continue
        if st.startswith('FPlayWithPopup.Caption'):
            popup.append({'text': rs['rsafspilmed'], 'items': [], 'dynamic': True}); continue
        m = re.match(r'Btn\((ToolBarMain|ToolBarFolders), (\w+)(?:, \w+)?\);', st)
        if m:
            (toolbar if m.group(1) == 'ToolBarMain' else folderbar).append(item(m.group(2))); continue

    # unit-local texts: mainform's own resourcestrings, audiotypes' field captions
    main_rs = {}
    for block in re.findall(r'resourcestring(.*?)(?:\n(?:type|const|var|function|procedure|implementation|uses)\b)', text, re.S | re.I):
        for m in re.finditer(r'^\s*(rs\w+)\s*=\s*(.*?);\s*$', block, re.M):
            main_rs[m.group(1)] = pascal_string(m.group(2)).replace('\r\n', '\n')
    at = open(os.path.join(SRC, 'audiotypes.pas'), encoding='utf-8').read()
    at_rs = {m.group(1).lower(): pascal_string(m.group(2)) for m in re.finditer(r'^\s*(rs\w+)\s*=\s*(.*?);\s*$', at, re.M)}
    fields = re.search(r'TTagField = \((.*?)\);', at, re.S).group(1)
    fields = [f.strip() for f in re.sub(r'//[^\n]*', '', fields).split(',')]
    caps = split_args(' '.join(re.search(r'TagFieldCaptions: array\[TTagField\] of string = \((.*?)\);', at, re.S).group(1).split()))
    def key(tf):  # tfRGTrackGain -> rgTrackGain, tfAlbumArtist -> albumArtist
        k = tf[2:]
        return 'rg' + k[2:] if k.startswith('RG') else k[0].lower() + k[1:]
    field_captions = {key(f): (at_rs[c.lower()] if c.lower() in at_rs else pascal_string(c)) for f, c in zip(fields, caps)}

    def str_list(name):
        body = re.search(name + r': array\[[^\]]*\] of string = \((.*?)\);', text, re.S).group(1)
        return [main_rs[a] if a in main_rs else pascal_string(a) for a in split_args(' '.join(body.split()))]

    columns = []
    for m in re.finditer(r"AddColumn\((.*?)\);", text[text.index("AddColumn('✓'"):]):
        a = split_args(m.group(1))
        if a[0].startswith('TagFieldCaptions['):
            cap = field_captions[key(a[0][17:-1])]
        else:
            cap = main_rs.get(a[0]) or pascal_string(a[0])
        columns.append({'caption': cap, 'width': int(a[1]), 'kind': a[2][2:].lower(),
                        'field': key(a[3]) if len(a) > 3 and a[2] == 'ckField' else '',
                        'numeric': len(a) > 4 and a[4] == 'True'})
        if len(columns) and 'ckFolder' in a[2]:
            break

    data = {'actions': actions, 'menus': menus, 'popup': popup, 'toolbar': toolbar, 'folderbar': folderbar,
            'columns': columns, 'fieldCaptions': field_captions, 'renameVars': str_list('RenameVars'),
            'f2tVars': str_list('F2TVars'), 'tagTypes': str_list('TagTypeTokens'), 'rs': main_rs}
    js = ("// GENERATED by tools/mkmenu.py from src/mainform.pas - do not edit.\n"
          "(function (root, factory) {\n"
          "  const m = factory();\n"
          "  if (typeof module === 'object' && module.exports) module.exports = m;\n"
          "  else root.MENUDATA = m;\n"
          "})(typeof self !== 'undefined' ? self : this, function () {\n"
          "  return " + json.dumps(data, ensure_ascii=False, indent=1) + ";\n});\n")
    open(OUT, 'w', encoding='utf-8', newline='\n').write(js)
    print(f'{len(actions)} actions, {len(menus)} menus, {len(popup)} popup items, {len(columns)} columns, '
          f'{len(toolbar)} toolbar entries, {len(folderbar)} folder buttons -> {OUT}')


if __name__ == '__main__':
    main()
