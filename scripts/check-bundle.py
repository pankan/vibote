#!/usr/bin/env python3
"""Verify release bundle versions, signatures and required architectures."""
from pathlib import Path
import plistlib
import subprocess

root = Path(__file__).resolve().parent.parent
app = root / 'build/Vibote.app'
version = (root / 'VERSION').read_text().strip()
for bundle, executable in [(app, 'Vibote'), (app / 'Contents/Resources/ViboteMic.driver', 'ViboteMic')]:
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleShortVersionString'] == version
    assert info['CFBundleVersion'] == version
    binary = bundle / 'Contents/MacOS' / executable
    architectures = set(subprocess.check_output(['xcrun', 'lipo', '-archs', str(binary)], text=True).split())
    assert architectures == {'arm64', 'x86_64'}, f'{executable}: {architectures}'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
assert (app / 'Contents/Resources/install-mic-from-app.sh').is_file()
print(f'Verified {version}: signed universal app and bundled driver')
