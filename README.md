# check-mk-raspberry

Checkmk packages for **Raspberry Pi 64-bit (arm64)**, built from the official Checkmk sources.

Checkmk does not publish ARM packages. This repository provides `.deb` packages so that a Checkmk site can run on a Raspberry Pi.

## Available packages

| Checkmk | Edition | Target | Package |
|---|---|---|---|
| **2.5.0p15** | Community | Debian 12 / Raspberry Pi OS **bookworm**, **arm64** | `check-mk-community-2.5.0p15_0.bookworm_arm64.deb` |
| **2.4.0p37** | Raw | Debian 12 / Raspberry Pi OS **bookworm**, **arm64** | `check-mk-raw-2.4.0p37_0.bookworm_arm64.deb` |
| **2.3.0p50** | Raw | Debian 12 / Raspberry Pi OS **bookworm**, **arm64** | `check-mk-raw-2.3.0p50_0.bookworm_arm64.deb` |

Download them from the [Releases](https://github.com/sergiodadi/check-mk-raspberry/releases) page.

All packages are built and tested on a **Raspberry Pi 5 Model B (8 GB)**. 2.5.0p14 and 2.3.0p50 run as production sites on Debian 12 bookworm
since October 2026; the other packages are tested by installation in a Debian 12 bookworm arm64 environment.
Several versions can be installed side by side (OMD keeps one directory per version).

## Installation

```
sha256sum <package>.deb            # compare with SHA256SUMS of the release
sudo apt install ./<package>.deb
sudo omd create mysite
sudo omd start mysite
```

To update an existing site, install the new package, then run `omd update` as described in the
[official documentation](https://docs.checkmk.com/latest/en/update.html).

## Sources

- Official Checkmk sources: https://github.com/Checkmk/checkmk
- Checkmk is licensed under the GNU GPL v2.

## Release history

| Date | Version | Target |
|---|---|---|
| 2026-10 | [2.5.0p15](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p15) (Community) | bookworm arm64 |
| 2026-10 | [2.4.0p37](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.4.0p37) (Raw) | bookworm arm64 |
| 2026-10 | [2.5.0p14](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p14) (Community) | bookworm arm64 |
| 2026-10 | [2.3.0p50](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.3.0p50) (Raw) | bookworm arm64 |
| 2022-03 to 2022-07 | [2.0.0p17](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.0.0p17) to [2.0.0p27](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.0.0p27) (Raw) | buster armhf (32-bit), no longer updated |

The 2.0.0 releases were built with the scripts of [chrisss404](https://github.com/chrisss404/check-mk-arm); thanks to him.
