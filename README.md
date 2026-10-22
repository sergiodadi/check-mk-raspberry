# check-mk-raspberry

Checkmk packages for **Raspberry Pi 64-bit (arm64)**, built from the official Checkmk sources.

Checkmk does not publish ARM packages. This repository provides `.deb` packages so that a Checkmk site can run on a Raspberry Pi.

## Latest packages

| Family | Latest release | Package |
|---|---|---|
| **Debian** (Raspberry Pi OS) | [2.5.0p17 — Debian 13 trixie](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p17-trixie) | `check-mk-community-2.5.0p17_0.trixie_arm64.deb` |
| **Ubuntu** | [2.5.0p16 — Ubuntu 26.04 resolute](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p16-resolute) | `check-mk-community-2.5.0p16_0.resolute_arm64.deb` |

GitHub marks only one release as *Latest*; use this table to find the latest package for your distribution.

## Available packages

| Checkmk | Edition | Target | Package |
|---|---|---|---|
| **2.5.0p17** | Community | Debian 13 / Raspberry Pi OS **trixie**, **arm64** | `check-mk-community-2.5.0p17_0.trixie_arm64.deb` |
| **2.5.0p16** | Community | Debian 12 / Raspberry Pi OS **bookworm**, **arm64** | `check-mk-community-2.5.0p16_0.bookworm_arm64.deb` |
| **2.5.0p16** | Community | Debian 13 / Raspberry Pi OS **trixie**, **arm64** | `check-mk-community-2.5.0p16_0.trixie_arm64.deb` |
| **2.5.0p16** | Community | Ubuntu **24.04 noble**, **arm64** | `check-mk-community-2.5.0p16_0.noble_arm64.deb` |
| **2.5.0p16** | Community | Ubuntu **26.04 resolute**, **arm64** | `check-mk-community-2.5.0p16_0.resolute_arm64.deb` |
| **2.5.0p15** | Community | Debian 12 / Raspberry Pi OS **bookworm**, **arm64** | `check-mk-community-2.5.0p15_0.bookworm_arm64.deb` |
| **2.5.0p15** | Community | Debian 13 / Raspberry Pi OS **trixie**, **arm64** | `check-mk-community-2.5.0p15_0.trixie_arm64.deb` |
| **2.5.0p15** | Community | Ubuntu **24.04 noble**, **arm64** | `check-mk-community-2.5.0p15_0.noble_arm64.deb` |
| **2.5.0p15** | Community | Ubuntu **26.04 resolute**, **arm64** | `check-mk-community-2.5.0p15_0.resolute_arm64.deb` |
| **2.4.0p37** | Raw | Debian 13 / Raspberry Pi OS **trixie**, **arm64** | `check-mk-raw-2.4.0p37_0.trixie_arm64.deb` |
| **2.4.0p37** | Raw | Debian 12 / Raspberry Pi OS **bookworm**, **arm64** | `check-mk-raw-2.4.0p37_0.bookworm_arm64.deb` |
| **2.3.0p50** | Raw | Debian 12 / Raspberry Pi OS **bookworm**, **arm64** | `check-mk-raw-2.3.0p50_0.bookworm_arm64.deb` |

Download them from the [Releases](https://github.com/sergiodadi/check-mk-raspberry/releases) page.

All packages are tested on a **Raspberry Pi 5 Model B (8 GB)** or a **Raspberry Pi 4** running Debian 12 bookworm (Debian 13 trixie for the trixie packages; the Ubuntu packages in a clean Ubuntu 24.04 or 26.04 system on the same Pi).
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

On Debian 13 trixie, install with `apt install ./<package>.deb php8.4-cgi` (see the release notes).

## Building the package yourself

The Checkmk 2.5 packages are built from the official Checkmk sources with two commented scripts and an ARM64 patch,
published in the [`build/`](build/) directory. On a 64-bit Raspberry Pi (8 GB of RAM, about 60 GB of free disk) or any
other arm64 machine, a single command builds the package for Debian 12, Debian 13, Ubuntu 24.04 or Ubuntu 26.04 (about 3 hours on a Raspberry Pi 5):

```
sudo apt install mmdebstrap git curl
git clone https://github.com/sergiodadi/check-mk-raspberry.git && cd check-mk-raspberry
sudo ./build/build-checkmk.sh 2.5.0p17 trixie /srv/checkmk-build
```

All steps, requirements, options and tests are explained in **[BUILD.md](BUILD.md)**.

To build **Checkmk 2.4 Raw** for Debian 13 trixie, use `build/build-checkmk-2.4.sh` (see [BUILD.md, section 9](BUILD.md#9-checkmk-24-raw-for-debian-13-trixie)).

## Sources

- Official Checkmk sources: https://github.com/Checkmk/checkmk
- Checkmk is licensed under the GNU GPL v2.

## Release history

| Date | Version | Target |
|---|---|---|
| 2026-10 | [2.5.0p17-trixie](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p17-trixie) (Community) | trixie arm64 |
| 2026-10 | [2.5.0p16-noble](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p16-noble) (Community) | Ubuntu 24.04 noble arm64 |
| 2026-10 | [2.5.0p16-bookworm](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p16-bookworm) (Community) | bookworm arm64 |
| 2026-10 | [2.4.0p37-trixie](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.4.0p37-trixie) (Raw) | trixie arm64 |
| 2026-10 | [2.5.0p16-resolute](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p16-resolute) (Community) | Ubuntu 26.04 resolute arm64 |
| 2026-10 | [2.5.0p16-trixie](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p16-trixie) (Community) | trixie arm64 |
| 2026-10 | [2.5.0p15-resolute](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p15-resolute) (Community) | Ubuntu 26.04 resolute arm64 |
| 2026-10 | [2.5.0p15-noble](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p15-noble) (Community) | Ubuntu 24.04 noble arm64 |
| 2026-10 | [2.5.0p15-trixie](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p15-trixie) (Community) | trixie arm64 |
| 2026-10 | [2.5.0p15](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p15) (Community) | bookworm arm64 |
| 2026-10 | [2.4.0p37](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.4.0p37) (Raw) | bookworm arm64 |
| 2026-10 | [2.5.0p14](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.5.0p14) (Community) | bookworm arm64 |
| 2026-10 | [2.3.0p50](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.3.0p50) (Raw) | bookworm arm64 |
| 2022-03 to 2022-07 | [2.0.0p17](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.0.0p17) to [2.0.0p27](https://github.com/sergiodadi/check-mk-raspberry/releases/tag/2.0.0p27) (Raw) | buster armhf (32-bit), no longer updated |

The 2.0.0 releases were built with the scripts of [chrisss404](https://github.com/chrisss404/check-mk-arm); thanks to him.

## Credits

These packages were built, tested and published with the help of **Claude**, the AI assistant by [Anthropic](https://www.anthropic.com/).
