#!/usr/bin/env python3
"""Export the completed native screen captures as an offline, portable canvas."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def export(capture_root, destination):
    capture_root = capture_root.resolve()
    data = json.loads((capture_root / 'manifest.json').read_text())
    if data.get('status') != 'Ready' or not data.get('frames'):
        raise ValueError('Only a completed capture can be exported; previous images may be stale.')
    sources = []
    for frame in data['frames']:
        source = (capture_root / frame['image']).resolve()
        if not source.is_relative_to(capture_root) or source.suffix != '.png' or not source.is_file():
            raise ValueError('Invalid or missing capture: ' + frame['id'])
        if not frame['id'].replace('-', '').replace('_', '').isalnum():
            raise ValueError('Invalid frame identifier')
        sources.append(source)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'captures').mkdir(exist_ok=True)
    for frame, source in zip(data['frames'], sources):
        frame['image'] = frame['id'] + '.png'
        shutil.copy2(source, destination / 'captures' / frame['image'])
    data['source'] = 'Current original checkout (includes local edits at capture time)'
    data['sourceHead'] = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    data['status'] = 'Saved snapshot'
    data['limitations'] += ' Saved snapshot; GitHub changes only after refreshed captures are committed and pushed.'
    (destination / 'manifest.json').write_text(json.dumps(data, indent=2) + '\n')
    page = (ROOT / 'tools/live-preview/index.html').read_text()
    page = page.replace("fetch('/manifest.json'", "fetch('./manifest.json'")
    page = page.replace("im.src='/captures/'", "im.src='./captures/'")
    page = page.replace("const m=await(await fetch('./manifest.json',{cache:'no-store'})).json();", 'const m=window.KURO_SNAPSHOT;')
    page = page.replace('<script>', '<script src="snapshot.js"></script>\n<script>', 1)
    page = page.replace('setInterval(poll,2000);', '')
    (destination / 'index.html').write_text(page)
    (destination / 'snapshot.js').write_text('window.KURO_SNAPSHOT = ' + json.dumps(data).replace('<','\\u003c') + ';\n')
    print(f'Exported {len(sources)} frames to {destination}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--captures', type=Path, default=Path('/tmp/kuro-screen-canvas'))
    parser.add_argument('--output', type=Path, default=ROOT / 'tools/screen-canvas')
    args = parser.parse_args()
    export(args.captures, args.output)
