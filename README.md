# check-mk-raspberry

Checkmk Community packages for **Raspberry Pi 64-bit (arm64)**, built from the official Checkmk sources.

Checkmk does not publish ARM packages. This repository provides `.deb` packages so that a Checkmk site can run on a Raspberry Pi.

## Current package

| Checkmk | Target | Package |
|---|---|---|
| **2.5.0p14** Community | Debian 12 / Raspberry Pi OS **bookworm**, **arm64** (64-bit) | `check-mk-community-2.5.0p14_0.bookworm_arm64.deb` |

Download it from the [Releases](https://github.com/sergiodadi/check-mk-raspberry/releases) page.

Tested on a **Raspberry Pi 5 Model B (8 GB)** running Debian 12 bookworm, as a production remote site since October 2026.

## Installation

```
sha256sum check-mk-community-2.5.0p14_0.bookworm_arm64.deb   # compare with SHA256SUMS of the release
sudo apt install ./check-mk-community-2.5.0p14_0.bookworm_arm64.deb
sudo omd create mysite
sudo omd start mysite
```

To update an existing site, install the new package, then run `omd update` as described in the
[official documentation](https://docs.checkmk.com/latest/en/update.html).

## Sources

- Official Checkmk sources: https://github.com/Checkmk/checkmk
- Checkmk is licensed under the GNU GPL v2.

## Older releases

The 2.0.0p17 to 2.0.0p27 releases target Raspberry Pi OS **buster 32-bit (armhf)**. They are kept for reference and are no longer updated.
Thanks to [chrisss404](https://github.com/chrisss404/check-mk-arm) for the scripts used to build them.
