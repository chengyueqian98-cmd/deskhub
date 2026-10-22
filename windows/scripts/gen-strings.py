#!/usr/bin/env python3
"""从 Mac 版的英文对照表生成 DeskHub.Core/StringsMac.g.cs，并检查 Windows 代码里 L("…") 用到的文字是不是都有英文。
用法（在 windows/ 目录）：python3 scripts/gen-strings.py        生成 + 检查
                         python3 scripts/gen-strings.py --check 只检查（CI 用）"""
import re, json, glob, sys, os
sys.stdout.reconfigure(encoding="utf-8")   # Windows 控制台默认不是 UTF-8
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.dirname(here)
mac_swift = os.path.join(root, '..', 'Sources', 'Core', 'StringsEN.swift')
out = os.path.join(root, 'DeskHub.Core', 'StringsMac.g.cs')
if '--check' not in sys.argv and os.path.exists(mac_swift):
    src = open(mac_swift, encoding='utf-8').read()
    pairs = re.findall(r'^\s*("(?:[^"\\]|\\.)*")\s*:\s*("(?:[^"\\]|\\.)*"),?\s*$', src, re.M)
    def unswift(s):
        s = s[1:-1]
        s = re.sub(r'\\u\{([0-9a-fA-F]+)\}', lambda m: chr(int(m.group(1), 16)), s)
        return s.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')
    d = {}
    for k, v in pairs: d[unswift(k)] = unswift(v)
    lines = ['// 自动从 Mac 版 Sources/Core/StringsEN.swift 生成（scripts/gen-strings.py），Windows 独有的文字在 StringsWin.cs。', 'namespace DeskHub.Core;', '', 'public static partial class Strings', '{', '    static readonly Dictionary<string, string> Mac = new()', '    {']
    lines += ['        [%s] = %s,' % (json.dumps(k, ensure_ascii=False), json.dumps(v, ensure_ascii=False)) for k, v in d.items()]
    lines += ['    };', '}', '']
    open(out, 'w', encoding='utf-8').write('\n'.join(lines))
have = set()
for f in (out, os.path.join(root, 'DeskHub.Core', 'StringsWin.cs')):
    have |= set(json.loads(m) for m in re.findall(r'^\s*\[("(?:[^"\\]|\\.)*")\]\s*=', open(f, encoding='utf-8').read(), re.M))
missing = []
for f in glob.glob(os.path.join(root, 'DeskHub', '*.cs')) + glob.glob(os.path.join(root, 'DeskHub.Core', '*.cs')):
    if os.path.basename(f).startswith('Strings'): continue
    for m in re.findall(r'(?<![.\w])L\(\s*("(?:[^"\\]|\\.)*")', open(f, encoding='utf-8').read()):
        k = json.loads(m)
        if re.search(r'[\u4e00-\u9fff]', k) and k not in have and k not in missing: missing.append(k)
if missing:
    print('这些文字还没有英文：'); [print('  ', json.dumps(k, ensure_ascii=False)) for k in missing]; sys.exit(1)
print('英文对照表齐全')
