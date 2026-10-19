# dmgbuild settings for the Lerro drag-to-install disk image.
# Invoked by package_release.sh with -Dapp=<Lerro.app> -Dbackground=<tiff> -Dicon=<icns>.
# Window height adds the 28 pt Finder title bar to the 400 pt background art.

application = defines["app"]  # noqa: F821

format = "ULFO"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]  # noqa: F821
background = defines["background"]  # noqa: F821

window_rect = ((200, 120), (660, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 128
text_size = 13
icon_locations = {
    "Lerro.app": (180, 210),
    "Applications": (480, 210),
}
