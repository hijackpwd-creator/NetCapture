#!/usr/bin/env python3
import argparse, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "Config" / "targets.json"
PLIST = ROOT / "NetCapture.plist"
HEADER = ROOT / "Tweak" / "Generated" / "NCTargetConfig.h"

SAFE = re.compile(r"^[A-Za-z0-9._+-]+$")

def parse_csv(value):
    if value is None:
        return None
    out=[]
    seen=set()
    for item in value.split(','):
        item=item.strip()
        if not item:
            continue
        if not SAFE.fullmatch(item):
            raise SystemExit(f"invalid target value: {item!r}")
        if item not in seen:
            seen.add(item); out.append(item)
    return out

def validate_list(name, values):
    if not isinstance(values, list):
        raise SystemExit(f"{name} must be an array")
    out=[]; seen=set()
    for item in values:
        if not isinstance(item, str) or not item or not SAFE.fullmatch(item):
            raise SystemExit(f"invalid {name} item: {item!r}")
        if item not in seen:
            seen.add(item); out.append(item)
    return out

def objc(s):
    return '@"' + s.replace('\\','\\\\').replace('"','\\"') + '"'

def plist_array(name, values):
    if not values:
        return ""
    lines=[f"    {name} = ("]
    for v in values:
        lines.append(f'      "{v}",')
    lines[-1] = lines[-1].rstrip(',')
    lines.append("    );")
    return "\n".join(lines) + "\n"

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--bundles', help='comma-separated bundle identifiers')
    ap.add_argument('--executables', help='comma-separated executable names')
    ap.add_argument('--write-config', action='store_true')
    args=ap.parse_args()

    data=json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    bundles=parse_csv(args.bundles)
    executables=parse_csv(args.executables)
    if bundles is None: bundles=validate_list('bundles', data.get('bundles', []))
    if executables is None: executables=validate_list('executables', data.get('executables', []))
    if not bundles and not executables:
        raise SystemExit('at least one bundle or executable target is required')

    if args.write_config:
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        CONFIG.write_text(json.dumps({'bundles':bundles,'executables':executables}, indent=2) + '\n')

    plist = "{\n  Filter = {\n" + plist_array('Bundles', bundles) + plist_array('Executables', executables) + "  };\n}\n"
    PLIST.write_text(plist)

    HEADER.parent.mkdir(parents=True, exist_ok=True)
    bvals=', '.join(objc(x) for x in bundles)
    evals=', '.join(objc(x) for x in executables)
    header=f'''#pragma once\n#import <Foundation/Foundation.h>\n\nNS_ASSUME_NONNULL_BEGIN\n\nstatic inline NSArray<NSString *> *NCCaptureConfiguredBundles(void) {{\n    return @[{bvals}];\n}}\n\nstatic inline NSArray<NSString *> *NCCaptureConfiguredExecutables(void) {{\n    return @[{evals}];\n}}\n\nNS_ASSUME_NONNULL_END\n'''
    HEADER.write_text(header)
    print('Configured bundles:', ', '.join(bundles) or '(none)')
    print('Configured executables:', ', '.join(executables) or '(none)')

if __name__ == '__main__': main()
