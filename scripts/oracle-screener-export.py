#!/usr/bin/env python3
"""Publish one completed Oracle simulator trace for the local Screener MCP."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import uuid

BUNDLE = 'ru.egormerkushev.oracle.screener'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='Exact iOS Simulator UUID')
    parser.add_argument('--trace', required=True, type=uuid.UUID, help='Completed trace UUID')
    args = parser.parse_args()
    container = Path(subprocess.run(
        ['xcrun', 'simctl', 'get_app_container', args.device, BUNDLE, 'data'],
        check=True, capture_output=True, text=True).stdout.strip())
    source = container / 'Library/Caches/OracleScreener/Traces' / (str(args.trace).upper() + '.vtrace')
    records = [json.loads(line) for line in (source / 'timeline.jsonl').read_text().splitlines()]
    manifest = json.loads((source / 'manifest.json').read_text())
    if str(manifest.get('sessionID', '')).upper() != str(args.trace).upper():
        raise SystemExit('Trace manifest does not match the requested UUID')
    if not records or records[-1].get('kind') != 'sessionEnded':
        raise SystemExit('Trace is not complete; wait for recording to stop')
    if [r['sequence'] for r in records] != list(range(len(records))):
        raise SystemExit('Trace has missing or reordered records')
    if not any(r.get('kind') == 'keyframe' for r in records):
        raise SystemExit('Trace contains no frames')
    if any(r.get('name') == 'oracle.capture.failed' for r in records):
        raise SystemExit('Trace contains a capture failure; inspect it before export')
    root = Path.home() / 'Library/Caches/Screener/Traces'
    root.mkdir(parents=True, exist_ok=True)
    dest = root / source.name
    if dest.exists():
        raise SystemExit('Trace already exists; refusing to overwrite: ' + str(dest))
    shutil.copytree(source, dest)
    print('Exported:', dest)
    print('Frames:', sum(r.get('kind') == 'keyframe' for r in records))
    print('Inspect through Screener MCP using session:', str(args.trace).upper())


if __name__ == '__main__':
    main()
