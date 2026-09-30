# omarchy-app-extras

Flatpak and AppImage application support for [Omarchy](https://github.com/omacom/omarchy) 4.x:
menu entries to install them, launcher registration that actually makes them
show up in the app search selector, and auto-updates for AppImages tracked
from GitHub releases (optionally prereleases) or direct download URLs.

Everything installs into your own home directory. Nothing under
`/usr/share/omarchy` is touched, so `omarchy update` neither clobbers this nor
is clobbered by it.

## The problem

Omarchy's graphical session exports:

```
XDG_DATA_DIRS=/usr/local/share:/usr/share
```

Flatpak exports its `.desktop` files and icons to `/var/lib/flatpak/exports/share`
(system installs) and `~/.local/share/flatpak/exports/share` (user installs).
Neither is on that list, so the Quickshell app search selector — which builds
its list from `DesktopEntries` in `shell/services/AppLibrary.qml`, resolved once
when the shell process starts — never sees a Flatpak app. You install GIMP from
Flathub, it runs fine from a terminal, and `SUPER + SPACE` acts like it does not
exist.

Check your own session:

```bash
tr '\0' '\n' </proc/$(pgrep -o quickshell)/environ | grep XDG_DATA_DIRS
```

On stock Omarchy that prints `XDG_DATA_DIRS=/usr/local/share:/usr/share`. After
installing this repo and running `omarchy-app-entries-refresh` it prints the
same list with the two Flatpak export roots appended, and the launcher finds the
apps.

AppImages have the adjacent problem: there is no packaging at all. A downloaded
`.AppImage` is a loose executable with no launcher, no icon, and no update path.

## What gets installed

Into `~/.local/bin`:

| Command | What it does |
| --- | --- |
| `omarchy-app-entries-refresh` | Appends the Flatpak export roots to `XDG_DATA_DIRS` for the live session, refreshes the desktop/icon caches, prunes launchers whose AppImage is gone, and restarts the shell only when the running shell is actually missing the roots |
| `omarchy-app-entries-install-env` | Persists the same thing across logins in `~/.config/hypr/envs.lua`, and wires `require("hypr.envs")` into `~/.config/hypr/hyprland.lua` (timestamped backup first) |
| `omarchy-install-flatpak` | One-time setup: `flatpak`, `xdg-desktop-portal-gtk`, the user and system Flathub remotes, and the environment wiring |
| `omarchy-install-flatpak-app` | Search Flathub with `gum`, user-install the pick, register the launcher |
| `omarchy-remove-flatpak-app` | Pick an installed Flatpak, uninstall it, drop unused runtimes |
| `omarchy-install-appimage` | Install an `.AppImage` into `~/Applications`, lift the bundled `.desktop` entry and the largest bundled icon out of the image, write `~/.local/share/applications/appimage-<slug>.desktop` |
| `omarchy-install-appimage-github` | Install straight from a GitHub repo's latest release and record where it came from; `--prerelease` follows prereleases too |
| `omarchy-install-appimage-url` | Install from a direct download URL and record it for re-checking |
| `omarchy-update-appimages` | Check every tracked AppImage for a newer release or build and reinstall the ones that moved |
| `omarchy-appimage-watch` | `enable`/`disable`/`status`/`run` the daily update timer |
| `omarchy-remove-appimage` | Remove an AppImage, its launcher, and its icon |

Also installed:

- `~/.local/lib/omarchy/appimage.sh` — shared release and download helpers
  (GitHub lookups use `gh` when you are authenticated, anonymous `curl`
  otherwise).
- `~/.config/omarchy/hooks/post-update.d/20-flatpak-apps` — `flatpak update`,
  AppImage release check, and a launcher refresh after every `omarchy update`.
- `~/.config/omarchy/hooks/post-boot.d/20-app-entries` — cache refresh and stale
  launcher pruning at login.

### How the AppImage tracking works

Each generated launcher carries the provenance in its own keys:

```
X-AppImage-Source=/home/you/Applications/Cursor-1.2.3-x86_64.AppImage
X-AppImage-Repo=getcursor/cursor
X-AppImage-Release=v1.2.3
X-AppImage-Asset=Cursor-1.2.3-x86_64.AppImage
X-AppImage-Asset-Glob=Cursor-*-x86_64.AppImage
X-AppImage-Published=2026-08-14T09:21:03Z
```

`omarchy-update-appimages` compares **both** `tag_name` and `published_at` —
publish time is what catches rolling tags like `continuous` or `nightly`, where
the tag never changes. The next release's asset is matched with the
version-agnostic glob (`Cursor-1.2.3-x86_64.AppImage` → `Cursor-*-x86_64.AppImage`),
and the superseded binary is deleted after the new one installs.

#### Prereleases

By default an app follows the repo's published *latest* release, falling back
to the newest prerelease only when the project ships nothing else. Install with
`omarchy-install-appimage-github --prerelease owner/repo` (the menu asks) to
follow whichever non-draft release — stable or prerelease — was published most
recently. The choice is stored as `X-AppImage-Prerelease=true` and carried
across updates; reinstall without the flag to go back to stable.

#### Direct download URLs

For apps not published on GitHub, `omarchy-install-appimage-url <url>` records
the link instead of a repo:

```
X-AppImage-Url=https://example.com/download/latest/App-x86_64.AppImage
X-AppImage-Asset=App-2.4.0-x86_64.AppImage
X-AppImage-Url-Stamp=etag:"5f3a-61e2b1c0"
```

Each check sends a `HEAD` request (a one-byte ranged `GET` when the server
refuses `HEAD`), follows redirects, and compares the final response's
validator — `ETag`, else `Last-Modified`, else size — and the served file name
(from `Content-Disposition` or the final URL) with the recorded ones. Either
changing triggers a download and reinstall. Point it at a stable "latest" link;
a URL whose server sends none of those headers is installed without tracking.

`omarchy-appimage-watch enable` writes a systemd **user** timer: `OnCalendar=daily`,
`RandomizedDelaySec=30m`, `Persistent=true`, so a run missed while the laptop was
asleep is caught up at the next boot. It is enabled automatically the first time
you install a tracked AppImage (GitHub repo or download URL).

## Menu rows added

Merged into `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

- **Install > Flatpak > Enable Flatpak** — shown only while `flatpak` is absent
- **Install > Flatpak > Flathub App**
- **Install > AppImage > Enable AppImage** — shown only while `fuse2` is absent
- **Install > AppImage > AppImage File**
- **Install > AppImage > From GitHub Repo**
- **Install > AppImage > From Download URL**
- **Install > AppImage > Auto-Update** — a toggle, checkmarked while the timer is enabled
- **Update > AppImages** — shown only when something is tracked
- **Remove > Flatpak App** — shown only when a Flatpak app is installed
- **Remove > AppImage** — shown only when an AppImage launcher exists

## Install

```bash
git clone https://github.com/alfkonee/omarchy-app-extras.git ~/Code/omarchy-app-extras && ~/Code/omarchy-app-extras/install.sh
```

The installer backs up `omarchy-menu.jsonc` with a timestamp before changing it.
A re-run replaces the rows it merged earlier with the current packaged ones (so
new rows appear after an update), leaves every other row alone, and is a no-op
when nothing changed. It finishes with `omarchy menu refresh`.

## Uninstall

```bash
~/Code/omarchy-app-extras/uninstall.sh
```

Removes the commands, the library, the hooks, and the menu rows, and disables the
update timer. It deliberately leaves your installed apps, Flatpak itself, and the
`~/.config/hypr/envs.lua` environment line in place; the closing message tells you
how to remove those by hand.

## Requirements

- Omarchy 4.x (Arch + Hyprland + the Quickshell shell)
- `jq` and `gum` — both ship with Omarchy
- `fuse2` (AppImages) and `flatpak` (Flatpak apps) are installed on demand via
  `omarchy-pkg-add` the first time you need them; you are not asked to
  pre-install anything
- `gh` is optional: when you are authenticated, release lookups use your token's
  rate limit instead of the anonymous one

## Relationship to upstream Omarchy

This is **not** a fork of Omarchy and not an official add-on. It is the
user-level opt-in for something upstream decided not to carry.

- [omacom/omarchy#870](https://github.com/omacom/omarchy/pull/870) — a PR adding
  Flatpak support to core, declined by the maintainer.
- [omacom/omarchy#1881](https://github.com/omacom/omarchy/issues/1881) — the
  matching request; Flatpak in core is out of scope for the project.
- [omacom/omarchy#8650](https://github.com/omacom/omarchy/issues/8650) — the
  underlying launcher-visibility bug (session `XDG_DATA_DIRS` omits the Flatpak
  export roots) is still open.

Pieces of this work have since been sent upstream, so the parts that belong in
Omarchy proper can land there instead of living here forever:

- [omacom/omarchy#9906](https://github.com/omacom/omarchy/pull/9906) — the
  session `XDG_DATA_DIRS` fix for #8650, as a standalone bug fix.
- [omacom/omarchy#9908](https://github.com/omacom/omarchy/pull/9908) — AppImage
  install/remove as first-class commands and menu rows.
- [omacom/omarchy#9909](https://github.com/omacom/omarchy/pull/9909) — AppImage
  tracking from GitHub releases with a daily update timer (stacked on #9908).
- [omacom/omarchy discussion #9911](https://github.com/omacom/omarchy/discussions/9911)
  — the opt-in Flatpak menu proposal, in the sanctioned Suggestions channel.

If those land, install the corresponding pieces from Omarchy itself and keep
this repo only for whatever upstream declines.

So the packaging decision is upstream's to make and has been made. The bug in
issue #8650 is real either way, and this repo is a way to have Flatpak and
AppImage apps behave like first-class Omarchy apps on your own machine without
patching anything Omarchy owns.

## License

MIT — see [LICENSE](LICENSE).
