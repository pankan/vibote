#!/usr/bin/env python3
"""Check static page IDs, local assets and fragment links without network access."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote

root = Path(__file__).resolve().parent.parent / 'docs'
class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.links = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, f"Duplicate ID: {attrs['id']}"
            self.ids.add(attrs['id'])
        for key in ('href', 'src'):
            if key in attrs:
                self.links.append(attrs[key])

page = Page()
page.feed((root / 'index.html').read_text())
for link in page.links:
    url = urlsplit(link)
    if url.scheme or url.netloc:
        continue
    if url.path:
        assert not url.path.startswith('/'), f'Not GitHub project Pages compatible: {link}'
        assert (root / unquote(url.path)).is_file(), f'Missing asset: {link}'
    elif url.fragment:
        assert url.fragment in page.ids, f'Missing anchor: {link}'
assert 'install-mic.sh' not in (root / 'index.html').read_text(), 'Users should install the mic in-app'
print('Website assets, anchors and project Pages paths passed')
