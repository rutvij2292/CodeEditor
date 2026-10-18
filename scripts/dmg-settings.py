# dmgbuild settings for the Kode installer (see scripts/make-dmg.sh).
import os

application = defines.get("app", "dist/Kode.app")   # noqa: F821  (`defines` is provided by dmgbuild)
appname = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}
badge_icon = None
icon = "Branding/AppIcon.icns"
background = "Branding/dmg-background.tiff"
icon_size = 128
text_size = 13
window_rect = ((200, 160), (660, 400))
default_view = "icon-view"
show_icon_preview = False
icon_locations = {appname: (180, 190), "Applications": (480, 190)}
