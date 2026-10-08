#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2 or not sys.argv[1].strip():
    print('usage: set_bundle_id.py <bundle-id>', file=sys.stderr)
    raise SystemExit(2)

bundle = sys.argv[1].strip()
if any(c.isspace() for c in bundle) or '/' in bundle:
    print('invalid bundle id', file=sys.stderr)
    raise SystemExit(2)

plist = Path('NetCapture.plist')
text = plist.read_text()
old = '"com.example.NetCaptureTest"'
if old not in text:
    print('warning: default bundle id not found in NetCapture.plist', file=sys.stderr)
text = text.replace(old, f'"{bundle}"')
plist.write_text(text)

tweak = Path('Tweak/Tweak.xm')
text = tweak.read_text()
old_objc = '@"com.example.NetCaptureTest"'
if old_objc not in text:
    print('warning: default bundle id not found in Tweak/Tweak.xm', file=sys.stderr)
text = text.replace(old_objc, '@"' + bundle + '"')
tweak.write_text(text)
print(f'capture bundle set to: {bundle}')
