# wslpanel

[Português](README.md) · [Español](README-ES.md)

A panel for the WSL distro: CPU, memory, disk, `/tmp` and `/var/log`, refreshed once a second, plus the packages installed by dpkg. Version **0.2.0** (2026-11-18) is shown in the footer.

Repository: <https://github.com/araguaci/wslpanel>

![WSL Panel with Resources, Processes, Docker, Logs and Programs](docs/wslpanel-dev.jpg)

## Features

- **Resources** (home): CPU percent, load, one bar per core, RAM, swap, disk for `/`, and the size of `/tmp` and `/var/log`, with the recent history.
- **Clean /tmp**: asks for confirmation, then deletes ordinary files and directories. Graphical session sockets stay: `.X11-unix`, `.ICE-unix`, `.XIM-unix` and `.font-unix`.
- **Clean logs**: asks for confirmation and removes only rotated files (`.gz`, `.xz`, `.bz2`, `.old`, or a name ending in `.<digits>`, such as `syslog.1`). The live log stays. Without permission, the panel reports it and does not ask for a password.
- **Processes**: name, PID, CPU share, RSS and state, read from `/proc`. End sends SIGTERM after confirmation. Process 1 and this panel stay.
- **Docker**: the tab appears only when the `docker` client is installed. It lists each running container, with CPU and memory read from the cgroup, PIDs and the `docker ps` status.
- **Logs**: the end of the text files in `/var/log` (one level down as well, such as `apt/history.log`). The line count starts at 50 and steps by 50, up to 2000. Compressed files and the binary `wtmp`, `btmp`, `lastlog` and `faillog` stay out.
- **Programs**: packages in this Debian or Ubuntu distro. Search, filters (programs, manual, all, updates, orphans, libraries) and sort by name, size or install date. The detail shows version, origin, size, dependencies and which packages require it.
- Upgrade, remove and clean orphans ask in a dialog and run `sudo -n apt-get`. The password is not stored: when sudo asks for one, the command is shown in the footer, with **Copy**. An essential package, or one with required priority, cannot be removed.
- **Theme**: Auto follows the system. Light and Dark sit in the footer, beside PT, EN and ES.
- **Languages**: Portuguese (pt_BR), English and Spanish. The language follows `WSLPANEL_LANG`, then `LC_ALL`, `LC_MESSAGES` and `LANG`. Otherwise the interface opens in Portuguese. The PT, EN and ES buttons in the footer apply for the session.
- The footer shows `wslpanel`, the version from `build.zig.zon` and the release date.

What has landed and what comes next is in [docs/PLANO.md](docs/PLANO.md).

## Requirements

- Linux, including a Debian or Ubuntu distro on WSL2. The Programs tab reads `/var/lib/dpkg/status`.
- [Zig 0.17.0](https://ziglang.org/download/0.17.0/).
- GTK 3 (`libgtk-3-0`) for the window. On WSL2, WSLg sets `DISPLAY`.
- `sudo` for package actions. Cleaning `/tmp` and `/var/log` uses the user's own permissions.

## Install and run

```sh
git clone https://github.com/araguaci/wslpanel
cd wslpanel
zig build -Doptimize=ReleaseSafe
./zig-out/bin/wslpanel
```

The first build downloads [nanoui](https://github.com/justrach/nanoui) (MIT, Rach Pradhan), at the revision pinned in `build.zig.zon`.

On Debian or Ubuntu:

```sh
sudo apt-get update
sudo apt-get install -y libgtk-3-0
```

Zig 0.17.0, if it is not on `PATH` yet:

```sh
# https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz
tar -xJf zig-x86_64-linux-0.17.0.tar.xz -C "$HOME/.local"
export PATH="$HOME/.local/zig-x86_64-linux-0.17.0:$PATH"
```

Another language for this run:

```sh
WSLPANEL_LANG=en ./zig-out/bin/wslpanel
WSLPANEL_LANG=es ./zig-out/bin/wslpanel
WSLPANEL_LANG=pt_BR ./zig-out/bin/wslpanel
```

## Development

```sh
zig build test
zig build
./zig-out/bin/wslpanel --nanoui-snapshot=/tmp/wslpanel.png --nanoui-wait=2
```

`--nanoui-wait=2` lets the meter take a one-second `/proc/stat` delta before the snapshot. No window is shown.

The published version is the one in `build.zig.zon`. The footer date lives in `src/meta.zig`. History is in [CHANGELOG.md](CHANGELOG.md). The version, changelog and release steps are in [docs/RELEASE.md](docs/RELEASE.md).

## License

MIT. See [LICENSE](LICENSE). The interface is drawn with nanoui, which has its own MIT license.
