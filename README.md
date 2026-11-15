# Rectify

A single low-level shell script that performs a deep, full-system update on
any mainstream Linux distribution — native package manager plus Flatpak and
Snap — while **asking before removing anything** the system considers
obsolete.

## Features

- Auto-detects the native package manager.
- Runs a deep upgrade (full dependency resolution, obsolete-package handling).
- Previews removals and asks for confirmation before deleting anything.
- Updates Flatpak and Snap when present.
- Optional non-interactive modes for automation.

## Supported package managers

| Manager  | Distributions                                  |
|----------|------------------------------------------------|
| `apt`    | Debian, Ubuntu, Mint, Pop!_OS, Kali, …         |
| `dnf`    | Fedora, RHEL 8+, CentOS Stream, Rocky, Alma     |
| `yum`    | RHEL 7, CentOS 7, older Fedora                 |
| `pacman` | Arch, Manjaro, EndeavourOS, Garuda             |
| `zypper` | openSUSE Leap / Tumbleweed, SLES               |
| `apk`    | Alpine Linux                                   |
| `xbps`   | Void Linux                                     |
| `emerge` | Gentoo, Funtoo                                 |

Flatpak and Snap are updated additionally when installed.

## Requirements

- `bash` 4+
- `sudo` (or run as root)
- The native package manager of your distribution

## Usage

```bash
chmod +x rectify.sh
sudo ./rectify.sh
```

### Options

| Flag             | Effect                                                              |
|------------------|---------------------------------------------------------------------|
| `-y`, `--yes`    | Skip prompts for **upgrades** only. Removal steps still ask.        |
| `--auto-remove`  | Skip prompts for **removals** too. Combine with `-y` for CI/cron.   |
| `-h`, `--help`   | Show help.                                                          |

### Examples

```bash
# Default, interactive — always asks before removing packages
sudo ./rectify.sh

# Non-interactive upgrades, but still asks before any removal
sudo ./rectify.sh -y

# Fully non-interactive (upgrades + removals) — use with caution
sudo ./rectify.sh -y --auto-remove
```

## Behavior around removals

Every step that could delete packages (`apt autoremove`, `dnf autoremove`,
`pacman -Rns`, `xbps-remove -o`, `emerge --depclean`/`--prune`, cache
cleanups, `flatpak uninstall --unused`) first **lists what would be removed**
and prompts:

```
Removal/cleanup step: remove these obsolete packages with 'apt autoremove'?
  Packages will NOT be removed if you answer 'N'.
  Proceed? [y/N]
```

Answering `N` (or pressing Enter) keeps the packages and the script moves on.
Upgrades that would force removals (e.g. `apt full-upgrade`) are previewed the
same way before proceeding.

## Notes

- Back up important data before running on production systems.
- Reboot after the script finishes if the kernel or core libraries were
  updated.
- The script does not enable third-party repositories or install new software;
  it only updates what is already configured.

## License

MIT License

Copyright (c) 2026 Breno Rodrigues Alves

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
