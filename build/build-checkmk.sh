#!/bin/bash
# =====================================================================================================================
# build-checkmk.sh - build a Checkmk Community .deb package for arm64 (Raspberry Pi 4/5 and other 64-bit ARM machines)
#
# Usage (as root, on an arm64 Debian or Raspberry Pi OS machine):
#     ./build-checkmk.sh <version> <distribution> [work directory]
#     ./build-checkmk.sh 2.5.0p15 trixie /srv/checkmk-build
#
#   <version>       Checkmk version, e.g. 2.5.0p15 (a matching patch build/checkmk-<version>-arm64.patch must exist)
#   <distribution>  bookworm (Debian 12), trixie (Debian 13), noble (Ubuntu 24.04), resolute (Ubuntu 26.04, not tested)
#   [work dir]      where everything is stored (default: ./work). Needs about 60 GB of free space.
#
# What the script does (each step is skipped if it was already done, so you can simply run it again after a problem):
#   1. creates a clean build system for the target distribution (a "chroot", made with mmdebstrap) - the host is not modified
#   2. downloads the official Checkmk sources (git tag v<version>)
#   3. applies the ARM64 patch (build/checkmk-<version>-arm64.patch) and adapts the gcc version to the distribution
#   4. downloads the official Checkmk package of the same version (amd64) and copies its prebuilt agent files
#      (Linux agent .deb/.rpm, Windows agent .msi, signed plug-ins, mk-oracle): they cannot be built from the sources
#   5. builds the package with Bazel (about 20-24 hours on a Raspberry Pi 5, 8 GB)
#   6. copies the result to <work dir>/output/check-mk-community-<version>_0.<distribution>_arm64.deb
#
# Optional environment variables:
#   JOBS=2              number of parallel Bazel jobs (2 is safe with 8 GB of RAM; do not go above 3)
#   MAINTAINER="Name <mail>"   the "Maintainer" field of the package (default: the one of the patch)
#   PREPARE_ONLY=1      stop before the Bazel build (steps 1 to 4 only, plus the download of bazelisk)
#
# License: GPL v2, like Checkmk. Based on the official Checkmk sources: https://github.com/Checkmk/checkmk
# =====================================================================================================================
set -u
V=${1:-}; DIST=${2:-}; WORK=$(realpath -m "${3:-./work}")
HERE=$(cd "$(dirname "$0")" && pwd); PATCH=$HERE/checkmk-$V-arm64.patch
JOBS=${JOBS:-2}
BAZELISK_VERSION=v1.29.0     # bazelisk downloads the Bazel version required by Checkmk (file .bazelversion)
BAZELISK_SHA256=e20e8b0f4f240091b7a55bf17b9398bd4f40ee70ae0208dff95dd4c445fb4010   # official checksum of bazelisk-linux-arm64

# ---- distribution settings: Bazel "distro" name, gcc version, Java version, package mirror ---------------------------
case "$DIST" in
  bookworm) DISTRO=debian-12;    GCC=12; JDK=openjdk-17-jdk-headless; MIRROR=http://deb.debian.org/debian;          COMP=main;;
  trixie)   DISTRO=debian-13;    GCC=14; JDK=openjdk-21-jdk-headless; MIRROR=http://deb.debian.org/debian;          COMP=main;;
  noble)    DISTRO=ubuntu-24.04; GCC=13; JDK=openjdk-21-jdk-headless; MIRROR=http://ports.ubuntu.com/ubuntu-ports; COMP=main,universe;;
  resolute) DISTRO=ubuntu-26.04; GCC=15; JDK=openjdk-21-jdk-headless; MIRROR=http://ports.ubuntu.com/ubuntu-ports; COMP=main,universe;;
  *) echo "usage: $0 <version> <bookworm|trixie|noble|resolute> [work directory]"; exit 2;;
esac
[ -n "$V" ] || { echo "usage: $0 <version> <distribution> [work directory]"; exit 2; }

C=$WORK/$DIST/chroot            # the build system (about 40 GB at the end, including the Bazel cache)
SRC=$WORK/$DIST/source          # the Checkmk sources (about 0.5 GB)
OUT=$WORK/output; LOG=$WORK/$DIST/build-$V.log
mkdir -p "$WORK/$DIST" "$OUT"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
die() { log "ERROR: $*"; exit 1; }

# ---- 0. checks on the host -------------------------------------------------------------------------------------------
[ "$(id -u)" = 0 ] || die "run this script as root (sudo)"
[ "$(dpkg --print-architecture)" = arm64 ] || die "this script must run on an arm64 machine (64-bit OS)"
[ -f "$PATCH" ] || die "patch not found: $PATCH"
for t in mmdebstrap git curl; do command -v $t >/dev/null || die "missing tool '$t': apt install mmdebstrap git curl"; done
KEYRING=
if [ "${DISTRO%%-*}" = ubuntu ]; then
  KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg
  [ -f $KEYRING ] || die "Ubuntu keyring missing: apt install ubuntu-keyring"
fi
FREE=$(df --output=avail -BG "$WORK" | tail -1 | tr -dc 0-9)
[ "$FREE" -ge 60 ] || log "WARNING: only ${FREE} GB free in $WORK, about 60 GB are needed"
[ "$(free -g | awk '/Mem:/{print $2}')" -ge 7 ] || log "WARNING: less than 8 GB of RAM, the build may fail (use JOBS=1)"

# Mounts needed inside the chroot. They are always removed at the end, even after an error or Ctrl-C.
umnt() { for m in build/source usr/local/bin/bazel dev/shm dev/pts dev sys proc; do mountpoint -q "$C/$m" && umount "$C/$m"; done; }
trap 'umnt' EXIT; trap 'log "stopped"; exit 143' TERM INT
umnt

# ---- 1. build system (chroot) ----------------------------------------------------------------------------------------
# Packages needed by the Checkmk build (compilers, Java for Bazel, development libraries...).
PKGS=apache2-dev,autoconf,automake,bison,build-essential,ca-certificates,cmake,curl,flex,g++,gcc,gettext,git,libcairo2-dev,libffi-dev,\
libfile-find-rule-perl,libglib2.0-dev,libgnutls28-dev,libgsf-1-dev,libjpeg-dev,libkrb5-dev,libldap2-dev,libltdl-dev,libncurses-dev,\
libpango1.0-dev,libperl-dev,libpng-dev,libpq-dev,libreadline-dev,libsasl2-dev,libsqlite3-dev,libssl-dev,libtool,libxml2-dev,libxslt1-dev,\
make,ninja-build,$JDK,p7zip-full,patchelf,perl,pkg-config,python3,python3-dev,python3-venv,rsync,unzip,zip,zlib1g-dev,zstd,libcrypt-dev,\
file,locales,bzip2,xz-utils
if [ ! -x "$C/usr/bin/apt-get" ]; then
  log "1. creating the $DIST arm64 build system in $C (10-20 min)"
  mmdebstrap --arch=arm64 --variant=buildd --components=$COMP ${KEYRING:+--keyring=$KEYRING} --include=$PKGS "$DIST" "$C" "$MIRROR" >> "$LOG" 2>&1 \
    || die "mmdebstrap failed (see $LOG)"
fi
log "   build system: $(. "$C/etc/os-release"; echo "$PRETTY_NAME"), $(chroot "$C" gcc --version | head -1)"

# ---- 2. official sources -----------------------------------------------------------------------------------------------
if [ ! -d "$SRC/.git" ]; then
  log "2. downloading the official Checkmk sources, tag v$V"
  git clone -q --depth 1 --branch "v$V" https://github.com/Checkmk/checkmk.git "$SRC" >> "$LOG" 2>&1 || die "git clone failed"

  # ---- 3. ARM64 patch ------------------------------------------------------------------------------------------------
  log "3. applying the ARM64 patch $(basename "$PATCH")"
  (cd "$SRC" && git apply --whitespace=nowarn "$PATCH") >> "$LOG" 2>&1 || die "the patch does not apply (wrong version?)"
  # The patch was made with gcc 14 (Debian 13). Only the ARM64 toolchain settings are adapted to the gcc version of the
  # target distribution; the x86_64 settings of the official sources (also "gcc-14") must stay unchanged.
  if [ "$GCC" != 14 ]; then
    B=$SRC/bazel
    # 1. the "usr" C/C++ library repository uses the system compiler
    sed -i -E "s#(gcc_path = \"/usr/bin/gcc)-14\"#\1-$GCC\"#" "$B/module/gcc.MODULE.bazel"
    # 2. the compiler used to build Python
    sed -i -E "s#(\"CC\": \"gcc)-14\"#\1-$GCC\"#" "$B/module/py.MODULE.bazel"
    # 3. the aarch64 toolchain added by the patch (one-line settings starting with a single space)
    sed -i -E "/^ (tool_paths|cxx_builtin_include_directories)=/ { s#(gcc-ar|gcc-nm|cpp|gcc)-14\"#\1-$GCC\"#g; s#aarch64-linux-gnu/14/#aarch64-linux-gnu/$GCC/#g }" \
      "$B/toolchains/cc/gcc/local/BUILD"
    log "   gcc 14 -> gcc $GCC: ARM64 toolchain settings adapted"
  fi
  if [ -n "${MAINTAINER:-}" ]; then
    sed -i -E "s|^(    maintainer = )\".*\",|\1\"$MAINTAINER\",|" "$SRC/omd/BUILD"; log "   maintainer: $MAINTAINER"
  fi
fi

# ---- 4. prebuilt agent files from the official package ------------------------------------------------------------------
# Checkmk builds its agents (Windows .msi, Linux agent packages...) separately, not from the sources.
# They do not depend on the server architecture: the official amd64 package contains the agents for amd64 and arm64.
if [ ! -f "$SRC/agents/windows/check_mk_agent.msi" ]; then
  log "4. copying the prebuilt agent files from the official $V package"
  OFF=check-mk-community-${V}_0.${DIST}_amd64.deb; T=$WORK/official; mkdir -p "$T"
  [ -f "$T/$OFF" ] || curl -f -s -L -o "$T/$OFF" "https://download.checkmk.com/checkmk/$V/$OFF" || die "download of $OFF failed"
  X=$T/extract; rm -rf "$X"; mkdir -p "$X"
  dpkg-deb --fsys-tarfile "$T/$OFF" | tar -x -C "$X" --wildcards '*/share/check_mk/agents/*' '*/lib/python3/cmk/plugins/oracle/agents/mk-oracle*' \
    || die "extraction of the official package failed"
  A=$(echo "$X"/opt/omd/versions/*/share/check_mk/agents); O=$(echo "$X"/opt/omd/versions/*/lib/python3/cmk/plugins/oracle/agents)
  cp -p "$A"/check-mk-agent*.deb "$A"/check-mk-agent*.rpm "$SRC/agents/"                         # Linux agent packages (amd64 + arm64)
  mkdir -p "$SRC/agents/linux"; cp -p "$A"/linux/* "$SRC/agents/linux/"                          # cmk-agent-ctl (x86_64 + aarch64), mk-sql
  for f in check_mk.user.yml check_mk_agent.msi mk-sql.exe robotmk_ext.exe unsign-msi.patch windows_files_hashes.txt; do
    cp -p "$A/windows/$f" "$SRC/agents/windows/"                                               # Windows agent
  done
  cp -p "$A/windows/python-3.cab" "$SRC/agents/windows/python-3.cab.prebuilt"                  # used instead of building it
  mkdir -p "$SRC/agents/windows/plugins/.signed"; cp -p "$A"/windows/plugins/*.ps1 "$SRC/agents/windows/plugins/.signed/"   # signed plug-ins
  cp -p "$O/mk-oracle" "$SRC/omd/packages/mk-oracle/mk-oracle.rhel8"                           # Oracle plug-in binaries
  for x in aix exe solaris; do cp -p "$O/mk-oracle.$x" "$SRC/omd/packages/mk-oracle/"; done
  rm -rf "$X"; log "   agent files copied: $(ls "$SRC"/agents/check-mk-agent* "$SRC"/agents/linux/* "$SRC"/agents/windows/plugins/.signed/* "$SRC"/omd/packages/mk-oracle/mk-oracle.* | wc -l) (expected: 40)"
fi

# ---- 5. Bazel build ----------------------------------------------------------------------------------------------------
BZ=$WORK/bin/bazel
if [ ! -x "$BZ" ]; then
  mkdir -p "$WORK/bin"; curl -f -s -L -o "$BZ.tmp" "https://github.com/bazelbuild/bazelisk/releases/download/$BAZELISK_VERSION/bazelisk-linux-arm64" \
    || die "download of bazelisk failed"
  echo "$BAZELISK_SHA256  $BZ.tmp" | sha256sum -c --quiet || die "bazelisk checksum mismatch"
  chmod 755 "$BZ.tmp"; mv "$BZ.tmp" "$BZ"
fi
[ "${PREPARE_ONLY:-0}" = 1 ] && { log "PREPARE_ONLY=1: everything is ready, stopping before the Bazel build"; exit 0; }
cp /etc/resolv.conf "$C/etc/"; mkdir -p "$C/build/source" "$C/usr/local/bin"; touch "$C/usr/local/bin/bazel"
mount --bind /proc "$C/proc"; mount --bind /sys "$C/sys"; mount --bind /dev "$C/dev"; mount --bind /dev/pts "$C/dev/pts"
mount --bind /dev/shm "$C/dev/shm"; mount --bind "$SRC" "$C/build/source"; mount --bind "$BZ" "$C/usr/local/bin/bazel"
IN() { chroot "$C" /usr/bin/env -i HOME=/root TMPDIR=/tmp PATH=/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 CARGO_BAZEL_REPIN=true /bin/bash -c "cd /build/source && $1"; }
log "5. Bazel build //omd:deb_community, distro $DISTRO, $JOBS jobs - this takes about a day, progress in $LOG"
T0=$(date +%s)
IN "bazel --output_user_root=/var/cache/bazel-cmk --host_jvm_args=-Xmx1g build --jobs=$JOBS --keep_going --verbose_failures \
    //omd:deb_community --cmk_version=$V --cmk_edition=community --@cmk//distro=$DISTRO --lockfile_mode=update" >> "$LOG" 2>&1; RC=$?
IN "bazel --output_user_root=/var/cache/bazel-cmk --host_jvm_args=-Xmx1g shutdown" >> "$LOG" 2>&1; sleep 5   # same startup options as the build; frees the mounts
log "   end of the Bazel build: code $RC, $(( ($(date +%s) - T0) / 60 )) min"
[ $RC = 0 ] || { grep -a "^ERROR" "$LOG" | tail -5; die "the build failed (see $LOG; you can fix and run the script again, the cache is kept)"; }

# ---- 6. result -----------------------------------------------------------------------------------------------------------
P=$(find "$C/var/cache/bazel-cmk" -name "check-mk-community-${V}_0.${DIST}_arm64.deb" -type f -newer "$PATCH" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
[ -n "$P" ] || die "package not found after the build"
cp "$P" "$OUT/" && (cd "$OUT" && sha256sum "$(basename "$P")" > "$(basename "$P").sha256")
log "6. package: $OUT/$(basename "$P") ($(du -h "$OUT/$(basename "$P")" | cut -f1)) - test it with: ./test-install.sh $DIST $OUT/$(basename "$P")"
