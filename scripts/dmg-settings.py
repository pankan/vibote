"""Finder presentation for the Vibote disk image (loaded by dmgbuild)."""
from pathlib import Path

root = Path(defines["root"])
staging = root / ".build" / "dmg-staging"
format = "UDZO"
filesystem = "HFS+"
files = [str(staging / "Vibote.app"), str(staging / ".Installation")]
symlinks = {"Applications": "/Applications"}
background = str(root / ".build" / "dmg-background.tiff")
icon = str(root / "Resources" / "AppIcon.icns")
default_view = "icon-view"
window_rect = ((200, 200), (760, 500))
icon_locations = {"Vibote.app": (190, 236), "Applications": (570, 236)}
icon_size = 128
text_size = 14
label_pos = "bottom"
arrange_by = None
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
hide_extensions = ["Vibote.app"]
