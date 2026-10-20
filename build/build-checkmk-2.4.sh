#!/bin/bash
# =====================================================================================================================
# build-checkmk-2.4.sh - build a Checkmk 2.4 Raw .deb package for arm64 (Raspberry Pi 4/5 and other 64-bit ARM machines)
#
# Usage (as root, on an arm64 Debian or Raspberry Pi OS machine):
#     ./build-checkmk-2.4.sh <version> <distribution> [work directory]
#     ./build-checkmk-2.4.sh 2.4.0p37 trixie /srv/checkmk-build
#
#   <version>       Checkmk 2.4 version, e.g. 2.4.0p37 (a matching patch build/checkmk-<version>-arm64.patch must exist)
#   <distribution>  trixie (Debian 13). For Debian 12 bookworm, use the published 2.4.0p37 bookworm package.
#   [work dir]      where everything is stored (default: ./work). Needs about 60 GB of free space.
#
# Checkmk 2.4 is packaged with "make deb" (Bazel builds the components, debuild assembles the package), unlike 2.5
# (pure Bazel, see build-checkmk.sh). What the script does (each step is skipped if it was already done, so you can simply
# run it again after a problem):
#   1. creates a clean build system for the target distribution (a "chroot", made with mmdebstrap) - the host is not modified
#   2. installs the build tools in it: bazelisk, Rust (rustup), Node.js 22 - all downloaded and checked (SHA-256)
#   3. downloads the official Checkmk sources (git tag v<version>) and applies the ARM64 patch
#   4. downloads the official Checkmk package of the same version (amd64): its prebuilt agent files (Linux agent .deb/.rpm,
#      Windows agent .msi...) cannot be built from the sources; its dependencies are installed in the build system
#   5. prepares Snap7 (its 2.4 download rule has no URL any more) from the official 7z archive, with an ARM64 makefile
#   6. builds the components with Bazel, then the package with "make deb" (about 4 hours on a Raspberry Pi 5, 8 GB)
#   7. copies the result to <work dir>/output/check-mk-raw-<version>_0.<distribution>_arm64.deb
#
# Optional environment variables:
#   JOBS=2              number of parallel Bazel jobs (2 is safe with 8 GB of RAM; do not go above 3)
#   MAINTAINER="Name <mail>"   the "Maintainer" field of the package (default: the one of the patch)
#
# License: GPL v2, like Checkmk. Based on the official Checkmk sources: https://github.com/Checkmk/checkmk
# =====================================================================================================================
V=${1:-}; DIST=${2:-}; WORK=$(realpath -m "${3:-./work}")
HERE=$(cd "$(dirname "$0")" && pwd); PATCH=$HERE/checkmk-$V-arm64.patch
JOBS=${JOBS:-2}
BAZELISK_VERSION=v1.29.0     # bazelisk downloads the Bazel version required by Checkmk (file .bazelversion)
BAZELISK_SHA256=e20e8b0f4f240091b7a55bf17b9398bd4f40ee70ae0208dff95dd4c445fb4010   # official checksum of bazelisk-linux-arm64
RUST_VERSION=1.99.0
NODE_VERSION=v22.23.3; NODE_SHA256=a44aeb94849a299b22df10b9e622ec2f605c2183501bc40590705131de7c740f   # node-<v>-linux-arm64.tar.xz
SNAP7_VERSION=1.4.2;   SNAP7_SHA256=1f4270cde8684957770a10a1d311c226e670d9589c69841a9012e818f7b9f80e   # snap7-full-<v>.7z

case "$DIST" in
  trixie) DISTRO_MK=DEBIAN_13; JDK=openjdk-21-jdk-headless; MIRROR=http://deb.debian.org/debian;;
  *) echo "usage: $0 <version> trixie [work directory]"; exit 2;;
esac
case "$V" in 2.4.*) ;; *) echo "usage: $0 <2.4 version> trixie [work directory] (for 2.5, use build-checkmk.sh)"; exit 2;; esac

C=$WORK/$DIST/chroot            # the build system (about 45 GB at the end, including the Bazel cache)
HW=$WORK/$DIST/home             # mounted on /home/checkmk in the build system: sources, Bazel cache, downloads, tools
CW=/home/checkmk                # the Checkmk build expects its workspace below /home (binary path rewriting of OpenSSL)
SRC=$CW/source-$V               # path inside the build system (on the host: $HW/source-$V)
OUT=$WORK/output; LOG=$WORK/$DIST/build-$V.log
mkdir -p "$WORK/$DIST" "$HW" "$OUT"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
die() { log "ERROR: $*"; exit 1; }

# ---- 0. checks on the host -------------------------------------------------------------------------------------------
[ "$(id -u)" = 0 ] || die "run this script as root (sudo)"
[ "$(dpkg --print-architecture)" = arm64 ] || die "this script must run on an arm64 machine (64-bit OS)"
[ -f "$PATCH" ] || die "patch not found: $PATCH"
for t in mmdebstrap git curl; do command -v $t >/dev/null || die "missing tool '$t': apt install mmdebstrap git curl"; done
FREE=$(df --output=avail -BG "$WORK" | tail -1 | tr -dc 0-9)
[ "$FREE" -ge 60 ] || log "WARNING: only ${FREE} GB free in $WORK, about 60 GB are needed"
[ "$(free -g | awk '/Mem:/{print $2}')" -ge 7 ] || log "WARNING: less than 8 GB of RAM, the build may fail (use JOBS=1)"

# Mounts needed inside the chroot. They are always removed at the end, even after an error or Ctrl-C.
umnt() { for m in home/checkmk dev/shm dev/pts dev sys proc; do mountpoint -q "$C/$m" && umount "$C/$m"; done; }
trap 'umnt' EXIT; trap 'log "stopped"; exit 143' TERM INT
umnt
# The build system gets its own small /dev (not the one of the host): some configure scripts run as root would
# otherwise change the permissions of the host's /dev/null.
mount_all() {
  cp /etc/resolv.conf "$C/etc/"; mkdir -p "$C$CW"
  mount --bind /proc "$C/proc"; mount --bind /sys "$C/sys"; mount -t tmpfs -o mode=755,nosuid devtmp "$C/dev"
  for d in null:3 zero:5 full:7 random:8 urandom:9; do mknod -m 666 "$C/dev/${d%:*}" c 1 "${d#*:}"; done; mknod -m 666 "$C/dev/tty" c 5 0
  mkdir -p "$C/dev/pts" "$C/dev/shm"; ln -s pts/ptmx "$C/dev/ptmx"; ln -s /proc/self/fd "$C/dev/fd"
  mount -t devpts -o newinstance,ptmxmode=666 devpts "$C/dev/pts"; mount -t tmpfs -o mode=1777 shm "$C/dev/shm"
  mount --bind "$HW" "$C$CW"
}
IN() { chroot "$C" /usr/bin/env -i HOME=/root TERM=dumb LANG=C.UTF-8 LC_ALL=C.UTF-8 \
         PATH=/usr/local/bin:/root/.cargo/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c "$1"; }

# ---- 1. build system (chroot) ----------------------------------------------------------------------------------------
PKGS=apache2-dev,autoconf,automake,bison,build-essential,ca-certificates,cmake,curl,debhelper,devscripts,fakeroot,flex,g++,gawk,gcc,\
git,gettext,libbz2-dev,libffi-dev,libfile-find-rule-perl,libgdbm-dev,libgdbm-compat4,libgsf-1-dev,libjpeg-dev,libkrb5-dev,libldap2-dev,\
libltdl-dev,liblzma-dev,libmariadb-dev-compat,libncurses-dev,libpango1.0-dev,libcairo2-dev,libglib2.0-dev,libgnutls28-dev,libcrypt-dev,\
libpcap-dev,libperl-dev,libpq-dev,libreadline-dev,librrd-dev,libsasl2-dev,libsqlite3-dev,libssl-dev,libtool,libtool-bin,libxml2-dev,\
libxslt1-dev,make,ninja-build,$JDK,patchelf,perl,pkg-config,python3,python3-dev,python3-pip,python3-venv,rsync,tk-dev,\
unzip,uuid-dev,zip,zlib1g-dev,zstd,file,locales,xz-utils,bzip2,p7zip-full,\
bind9-dnsutils,openssh-client,default-libmysqlclient-dev,libxmlsec1-dev,libnss3-dev,libfreeradius-dev,libevent-dev,libgd-dev,\
libcurl4-openssl-dev,libmpfr-dev,libmcrypt-dev,dietlibc-dev,gtk-doc-tools,texinfo,netcat-openbsd,rpcbind,smbclient,iputils-ping,iproute2,libwebp-dev
if [ ! -x "$C/usr/bin/apt-get" ]; then
  log "1. creating the $DIST arm64 build system in $C (10-20 min)"
  mmdebstrap --arch=arm64 --variant=buildd --components=main --include=$PKGS "$DIST" "$C" "$MIRROR" >> "$LOG" 2>&1 \
    || die "mmdebstrap failed (see $LOG)"
fi
log "   build system: $(. "$C/etc/os-release"; echo "$PRETTY_NAME"), $(chroot "$C" gcc --version | head -1)"
mount_all

# ---- 2. build tools ----------------------------------------------------------------------------------------------------
dl() {  # dl <url> <file> <sha256>: download once, then check the checksum
  [ -f "$2" ] || { curl -f -s -L -o "$2.tmp" "$1" && mv "$2.tmp" "$2"; } || die "download failed: $1"
  echo "$3  $2" | sha256sum -c --quiet || die "checksum mismatch: $2 (delete it and run again)"
}
if [ ! -x "$C/usr/local/bin/bazel" ]; then
  dl "https://github.com/bazelbuild/bazelisk/releases/download/$BAZELISK_VERSION/bazelisk-linux-arm64" "$HW/bazelisk-linux-arm64" "$BAZELISK_SHA256"
  install -m 755 "$HW/bazelisk-linux-arm64" "$C/usr/local/bin/bazel"     # the Makefiles call /usr/local/bin/bazel
fi
if [ ! -x "$C/root/.cargo/bin/cargo" ]; then
  log "2. installing Rust $RUST_VERSION (rustup)"
  IN "curl -f -s -L -o /tmp/rustup-init https://static.rust-lang.org/rustup/dist/aarch64-unknown-linux-gnu/rustup-init && \
      curl -f -s -L https://static.rust-lang.org/rustup/dist/aarch64-unknown-linux-gnu/rustup-init.sha256 | sed 's# .*\$#  /tmp/rustup-init#' | sha256sum -c --quiet && \
      chmod 755 /tmp/rustup-init && /tmp/rustup-init -y -q --no-modify-path --profile minimal --default-toolchain $RUST_VERSION && rm /tmp/rustup-init" \
    >> "$LOG" 2>&1 || die "installation of Rust failed (see $LOG)"
fi
NODE=node-$NODE_VERSION-linux-arm64
if [ ! -x "$HW/$NODE/bin/node" ]; then
  log "2. installing Node.js $NODE_VERSION"
  dl "https://nodejs.org/dist/$NODE_VERSION/$NODE.tar.xz" "$HW/$NODE.tar.xz" "$NODE_SHA256"
  tar -xJf "$HW/$NODE.tar.xz" -C "$HW" || die "extraction of Node.js failed"
fi
for t in node npm npx; do ln -sfn "$CW/$NODE/bin/$t" "$C/usr/local/bin/$t"; done
# The system libcurl used by /usr/bin/cmake needs OpenSSL >= 3.3, but Checkmk's pip rules put their own OpenSSL 3.0 in
# LD_LIBRARY_PATH: cmake is started without it.
printf '#!/bin/sh\nunset LD_LIBRARY_PATH\nexec /usr/bin/cmake "$@"\n' > "$C/usr/local/bin/cmake"; chmod 755 "$C/usr/local/bin/cmake"
log "   tools: bazelisk $BAZELISK_VERSION, $(IN 'rustc --version'), node $(IN 'node --version')"

# ---- 3. official sources and ARM64 patch -------------------------------------------------------------------------------
H=$HW/source-$V
if [ -d "$H" ] && [ ! -f "$H/.arm64-prepared" ]; then
  die "$H was not completely prepared (interrupted, or the patch did not apply): delete it with 'rm -rf $H' and run again"
fi
if [ ! -d "$H/.git" ]; then
  log "3. downloading the official Checkmk sources, tag v$V, and applying $(basename "$PATCH")"
  git clone -q --depth 1 --branch "v$V" https://github.com/Checkmk/checkmk.git "$H" >> "$LOG" 2>&1 || die "git clone failed"
  (cd "$H" && git apply --whitespace=nowarn "$PATCH") >> "$LOG" 2>&1 || die "the patch does not apply (wrong version?)"
  if [ -n "${MAINTAINER:-}" ]; then
    sed -i "s|^Maintainer: .*|Maintainer: $MAINTAINER|" "$H/omd/debian/control.in"; log "   maintainer: $MAINTAINER"
  fi
  cat > "$H/user.bazelrc" <<EOF
startup --output_user_root=$CW/bazel-cache
startup --host_jvm_args=-Xmx1g
common --jobs=$JOBS
common --repository_cache=$CW/repository-cache
common --action_env=PYTHONDONTWRITEBYTECODE=1
common --host_action_env=PYTHONDONTWRITEBYTECODE=1
EOF
  touch "$H/.arm64-prepared"
fi
TAG=$(git -C "$H" -c safe.directory='*' describe --tags --exact-match 2>/dev/null)
[ "$TAG" = "v$V" ] || die "the sources in $H are not those of v$V (found: ${TAG:-none}); delete this directory and run again"

# ---- 4. official package: prebuilt agent files and dependencies ---------------------------------------------------------
OFF=check-mk-raw-${V}_0.${DIST}_amd64.deb; T=$WORK/official; mkdir -p "$T"
[ -f "$T/$OFF" ] || curl -f -s -L -o "$T/$OFF" "https://download.checkmk.com/checkmk/$V/$OFF" || die "download of $OFF failed"
if [ ! -f "$H/agents/windows/check_mk_agent.msi" ]; then
  log "4. copying the prebuilt agent files from the official $V package"
  X=$T/extract; rm -rf "$X"; mkdir -p "$X"
  dpkg-deb --fsys-tarfile "$T/$OFF" | tar -x -C "$X" --wildcards '*/share/check_mk/agents/*' '*/share/doc/bill-of-materials.json' \
    || die "extraction of the official package failed"
  A=$(echo "$X"/opt/omd/versions/*/share/check_mk/agents)
  cp -p "$A/check-mk-agent_${V}-1_all.deb" "$A/check-mk-agent-${V}-1.noarch.rpm" "$H/agents/"     # Linux agent packages
  mkdir -p "$H/agents/linux"; cp -p "$A"/linux/* "$H/agents/linux/"                              # cmk-agent-ctl, mk-sql
  for f in check_mk.user.yml check_mk_agent.msi mk-sql.exe robotmk_ext.exe python-3.cab unsign-msi.patch windows_files_hashes.txt; do
    cp -p "$A/windows/$f" "$H/agents/windows/"                                                 # Windows agent
  done
  cp -p "$X"/opt/omd/versions/*/share/doc/bill-of-materials.json "$H/omd/bill-of-materials.json"
  rm -rf "$X"; log "   agent files copied"
fi
# The OMD Apache package links the Apache modules of the system and reads /opt/<distro>.mk; the runtime dependencies of
# the official package are installed in the build system (as on Checkmk's own build machines).
cp -p "$H/omd/distros/$DISTRO_MK.mk" "$C/opt/$DIST.mk"
if [ ! -f "$C/usr/lib/apache2/modules/mod_mpm_prefork.so" ] || [ ! -x "$C/usr/bin/htpasswd" ]; then
  log "4. installing the dependencies of the official package in the build system"
  DEPS=$(dpkg-deb -f "$T/$OFF" Depends | tr ',' '\n' | sed 's/|.*//; s/(.*)//; s/ //g' | grep -v '^$' | tr '\n' ' ')
  printf '#!/bin/sh\nexit 101\n' > "$C/usr/sbin/policy-rc.d"; chmod 755 "$C/usr/sbin/policy-rc.d"   # no service starts in the chroot
  IN "apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $DEPS" >> "$LOG" 2>&1 \
    || die "installation of the dependencies failed (see $LOG)"
fi

# ---- 5. Snap7 ----------------------------------------------------------------------------------------------------------
S7=$HW/snap7-$SNAP7_VERSION
if [ ! -f "$S7/WORKSPACE" ]; then
  log "5. preparing Snap7 $SNAP7_VERSION"
  dl "https://sourceforge.net/projects/snap7/files/$SNAP7_VERSION/snap7-full-$SNAP7_VERSION.7z/download" "$HW/snap7-full-$SNAP7_VERSION.7z" "$SNAP7_SHA256"
  rm -rf "$S7" "$HW/snap7-full-$SNAP7_VERSION"
  IN "cd $CW && 7z x -y snap7-full-$SNAP7_VERSION.7z" >> "$LOG" 2>&1 || die "extraction of Snap7 failed"
  mv "$HW/snap7-full-$SNAP7_VERSION" "$S7"
  (cd "$S7" && rm -rf doc examples LabVIEW release rich-demos utility win-clean.bat)   # only the sources are needed
  sed -e 's/^TargetCPU *:=.*/TargetCPU  :=aarch64/' -e 's/-mword-relocations //' -e 's/^CXXFLAGS *:= -O3 -g/CXXFLAGS   := -O3/' \
    "$S7/build/unix/arm_v7_linux.mk" > "$S7/build/unix/aarch64_linux.mk"
  cat > "$S7/BUILD" <<'EOF'
load("@rules_foreign_cc//foreign_cc:defs.bzl", "make")

filegroup(
    name = "all_srcs",
    srcs = glob(["**/*"], exclude = ["bazel-*", "Makefile"]),
)

make(
    name = "snap7",
    args = ["-j4", "-C build/unix -f aarch64_linux.mk", "LibInstall=$INSTALLDIR"],
    lib_source = ":all_srcs",
    out_lib_dir = "",
    out_shared_libs = ["libsnap7.so"],
    postfix_script = """
      patchelf --set-soname libsnap7.so $$INSTALLDIR/libsnap7.so
    """,
    visibility = ["//visibility:public"],
)
EOF
  touch "$S7/WORKSPACE"
fi

# ---- 6. build ----------------------------------------------------------------------------------------------------------
log "6. build: Bazel components, frontends, make deb ($JOBS jobs) - this takes about 4 hours, progress in $LOG"
T0=$(date +%s)
# MAKE is passed to debuild: "make deb" must run without -j (some install targets of omd/Makefile do not depend on each
# other and break the package layout when run in parallel).
IN "set -euo pipefail
export BAZEL_EXTRA_ARGS='--jobs=$JOBS --lockfile_mode=update --override_repository=snap7=$CW/snap7-$SNAP7_VERSION --action_env=PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin --host_action_env=PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PYTHONDONTWRITEBYTECODE=1 GRPC_PYTHON_BUILD_EXT_COMPILER_JOBS=$JOBS NPY_NUM_BUILD_JOBS=$JOBS
cd $SRC
./scripts/run-bazel.sh build --cmk_version=$V //omd:deps_install_cre
if [ ! -d packages/cmk-frontend/dist ] || [ ! -d packages/cmk-frontend-vue/dist ]; then make cmk-frontend-build frontend-vue-build; fi
MAKE=make make deb" >> "$LOG" 2>&1; RC=$?
IN "cd $SRC && bazel shutdown" >> "$LOG" 2>&1; sleep 5      # frees the mounts
log "   end of the build: code $RC, $(( ($(date +%s) - T0) / 60 )) min"
[ $RC = 0 ] || { grep -a -E "^ERROR|error:|\*\*\*" "$LOG" | tail -8; die "the build failed (see $LOG; you can fix and run the script again, the cache is kept)"; }

# ---- 7. result ---------------------------------------------------------------------------------------------------------
P=$H/check-mk-raw-${V}_0.${DIST}_arm64.deb
[ -f "$P" ] || die "package not found after the build: $P"
cp "$P" "$OUT/" && (cd "$OUT" && sha256sum "$(basename "$P")" > "$(basename "$P").sha256")
log "7. package: $OUT/$(basename "$P") ($(du -h "$OUT/$(basename "$P")" | cut -f1)) - test it with: ./test-install.sh $DIST $OUT/$(basename "$P")"
