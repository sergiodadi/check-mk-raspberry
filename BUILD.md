# Building the Checkmk 2.5 arm64 package yourself

This page explains how to build the Checkmk **2.5 Community** `.deb` package for **arm64** (Raspberry Pi 4/5 and other
64-bit ARM machines) from the official Checkmk sources — the same way the packages of this repository are built.
You do not need to know Bazel or Debian packaging: two scripts do the work, and every step is explained below.

The scripts and the patch are in the [`build/`](build/) directory:

| File | Role |
|---|---|
| [`build/build-checkmk.sh`](build/build-checkmk.sh) | Prepares everything and builds the package (all steps below) |
| [`build/checkmk-2.5.0p15-arm64.patch`](build/checkmk-2.5.0p15-arm64.patch) | Changes needed to build Checkmk on ARM64 (44 files of the official sources) |
| [`build/test-install.sh`](build/test-install.sh) | Tests the package in a clean, temporary system |

## Verified procedure

This procedure was verified exactly as written: a complete build from an empty work directory, without any cache, on a
**Raspberry Pi 5 (8 GB) running Debian 13**, target `trixie`, on 15-16 October 2026. It took **23 hours** (Bazel: 19,513
actions, no error). The resulting package has the same file list and the same dependencies as the published
`check-mk-community-2.5.0p15_0.trixie_arm64.deb`, and `test-install.sh` passed (installation, site running, login,
Linux and Windows agents offered).
The current script (with the development packages of Checkmk's build machines and the net-snmp fix) was verified on
16-17 October 2026 with a complete rebuild for `trixie` (21 hours, no error): the package has the same files and
dependencies as the official Checkmk package except one Agent Bakery file (see section 7), and `test-install.sh` passed.

**Note on build times (19 October 2026):** the build times given above (21 to 23 hours) were caused by a temporary
internal network issue on our build machine, now fixed. They do not reflect the build itself: with a working network,
a complete build from scratch takes **about 3 hours** on the same Raspberry Pi 5 (8 GB) — for example 184 minutes for
2.5.0p16 (trixie) and 188 minutes for 2.5.0p15 (resolute).

## 1. What you need

| | |
|---|---|
| Machine | 64-bit ARM (arm64/aarch64) with **8 GB of RAM** — e.g. a Raspberry Pi 5 8 GB. A Pi 4 8 GB works too, but is slower. |
| System | Debian 12/13 or Raspberry Pi OS **64-bit** (the target distribution can be different: the build runs in its own system) |
| Disk | **About 40 GB** used by the build (36 GB measured for trixie); keep **60 GB free** to be safe. Fast storage recommended: SSD/NVMe rather than an SD card |
| Time | **About 3 hours** on a Raspberry Pi 5 (8 GB) for a first build. A newer version built in the same work directory is faster: only what changed is rebuilt |
| Network | About 3 GB of downloads (sources, build system, Bazel dependencies, official agents) |
| Rights | root (`sudo`) |

Supported targets:

| Target | Distribution name | Status |
|---|---|---|
| Debian 12 / Raspberry Pi OS bookworm | `bookworm` | built and published |
| Debian 13 / Raspberry Pi OS trixie | `trixie` | built, published, real test on a Raspberry Pi 5 |
| Ubuntu 24.04 LTS | `noble` | built and published |
| Ubuntu 26.04 LTS | `resolute` | tested (build and installation test; built with gcc 14, like the official Checkmk packages) |

## 2. Install the tools

```
sudo apt install mmdebstrap git curl
sudo apt install ubuntu-keyring      # only if you build for Ubuntu (noble, resolute)
```

## 3. Get the scripts

```
git clone https://github.com/sergiodadi/check-mk-raspberry.git
cd check-mk-raspberry
```

## 4. Build

Choose a work directory with 60 GB free, then run (example for Debian 13 trixie):

```
sudo ./build/build-checkmk.sh 2.5.0p15 trixie /srv/checkmk-build
```

The build takes about 3 hours. To keep it running after you close your SSH session, use `tmux` or `screen`, or start it
as a background service (it also keeps the Raspberry Pi responsive):

```
sudo systemd-run --unit=checkmk-build --property=MemoryMax=6G --nice=10 \
     /path/to/check-mk-raspberry/build/build-checkmk.sh 2.5.0p15 trixie /srv/checkmk-build
sudo tail -f /srv/checkmk-build/trixie/build-2.5.0p15.log      # follow the progress
```

The script runs these steps, and logs everything in `/srv/checkmk-build/trixie/build-2.5.0p15.log`:

1. **Build system** — creates a clean Debian or Ubuntu arm64 system (a *chroot*) with all the compilers and libraries
   needed. Your own system is not modified (only `mmdebstrap`, `git` and `curl` are installed on it).
2. **Official sources** — downloads the Checkmk sources of the requested version from
   [github.com/Checkmk/checkmk](https://github.com/Checkmk/checkmk) (git tag `v2.5.0p15`).
3. **ARM64 patch** — applies `checkmk-2.5.0p15-arm64.patch`. Checkmk only builds for x86_64: the patch changes the
   architecture of the package, the compiler and library paths of the third-party components (OpenSSL, Python,
   net-snmp, glib, rrdtool, Nagios…) and their checksums, and the Rust settings. The gcc version is then adapted to
   the target distribution (12 for bookworm, 13 for noble, 14 for trixie).
4. **Agent files** — downloads the official Checkmk 2.5.0p15 package (amd64) from download.checkmk.com and copies its
   prebuilt agent files into the sources: Linux agent packages (amd64 and arm64), Windows agent `.msi` and its signed
   plug-ins, `cmk-agent-ctl`, `mk-oracle`. Checkmk builds these files separately (some on Windows), not from the
   sources; they do not depend on the server architecture. Thanks to this step, the *Setup > Agents* page of your
   site offers the same agents as an official Checkmk server.
5. **Bazel build** — Checkmk is built with [Bazel](https://bazel.build). The script downloads `bazelisk` (checksum
   verified), which itself downloads the Bazel version required by Checkmk. About 19,500 build actions follow.
6. **Result** — the package is copied to `/srv/checkmk-build/output/`, with its SHA-256 checksum:
   `check-mk-community-2.5.0p15_0.trixie_arm64.deb`.

Useful options (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `JOBS` | `2` | Parallel build jobs. 2 is safe with 8 GB of RAM; use 1 if the build runs out of memory |
| `MAINTAINER` | the one of the patch | `Maintainer` field of your package, e.g. `MAINTAINER="Jane Doe <jane@example.org>"` |
| `PREPARE_ONLY` | `0` | `1` = run steps 1 to 4 only (useful to check everything before starting the long build) |

Example: `sudo JOBS=1 MAINTAINER="Jane Doe <jane@example.org>" ./build/build-checkmk.sh 2.5.0p15 noble /srv/checkmk-build`

**Normal messages**: at the beginning, Bazel prints many warnings like
`Download from https://bazel-registry.lan.checkmk.net/... failed: ... Unknown host`. The official sources first try
Checkmk's internal mirror (reachable only inside their company), then the public address: these warnings are harmless.

**If something goes wrong**: read the end of the log file, fix the cause (disk full, network…) and run the same
command again. Steps already done are skipped and the Bazel cache is kept, so the build resumes where it stopped.
A `Ctrl-C` or a stop of the service is safe: the script always unmounts what it mounted. If the preparation itself was
interrupted (or the patch did not apply), the script refuses the incomplete source directory and tells you to delete
it (`rm -rf <work dir>/<distribution>/source-<version>`) before running again.

## 5. Test the package

```
sudo ./build/test-install.sh trixie /srv/checkmk-build/output/check-mk-community-2.5.0p15_0.trixie_arm64.deb
```

The test creates a temporary clean system, installs the package with `apt`, creates and starts a site, logs in as
`cmkadmin` and checks that the Linux and Windows agents are offered. Expected result: `apt: code 0`, an empty
`dpkg --audit`, `Overall state: running`, login `HTTP 302`, and the agent files listed. The temporary system is then
deleted. (It uses port 5000 on 127.0.0.1.)

## 6. Install

```
sha256sum check-mk-community-2.5.0p15_0.trixie_arm64.deb      # compare with the .sha256 file
sudo apt install ./check-mk-community-2.5.0p15_0.trixie_arm64.deb
sudo omd create mysite
sudo omd start mysite
```

On Debian 13 trixie, add `php8.4-cgi` to the `apt install` command (see the release notes of the trixie package).
To update an existing site: install the new package, then `omd update` as described in the
[official documentation](https://docs.checkmk.com/latest/en/update.html).

## 7. Known differences with the official amd64 package

The package contains the same files and the same dependencies as the official Checkmk package, with two exceptions:

- `cmk/base/cee/plugins/bakery/bakery_api/v1/__init__.py` is missing: it is a compatibility file for the Agent Bakery
  of the commercial editions and is not part of the public sources. It is not used by the Community edition.
- An unneeded directory `var/cache/bazel-cmk/…` (a few build files of rrdtool) is included by mistake; it is harmless.

Packages published before 17 October 2026 also lacked a few optional components (`check_dig`, `check_dns`,
`check_by_ssh`, `check_mysql`, `snmppcap`, the Python modules `netsnmp`, `_lzma`, `_tkinter`…), because the build
system lacked some development packages and the Python bindings of net-snmp were skipped. Both are fixed in the
current script and patch.

## 8. Other versions

The patch is made for **2.5.0p15**. It may also apply to a later 2.5.0 patch release (this has not been tested):
copy it to `build/checkmk-<version>-arm64.patch` and run the script with the new version. If `git apply` fails,
the changed files must be adapted by hand. New patches will be published here with new packages.

**Use the same work directory for the next version.** Each version gets its own source directory
(`<work dir>/<distribution>/source-<version>`), while the build system and the Bazel cache are shared: the downloads
and the components that did not change are reused, so a newer version should build faster than the first one (not measured yet).
Before building, the script checks that the sources really are those of the requested version.

## Credits

Built from the official [Checkmk](https://checkmk.com) sources (GNU GPL v2). The ARM64 adaptation and these scripts
were made with the help of **Claude**, the AI assistant by [Anthropic](https://www.anthropic.com/).
