#!/bin/bash
# =====================================================================================================================
# test-install.sh - test a Checkmk arm64 package in a clean, temporary system (nothing is installed on the host)
#
# Usage (as root, on an arm64 machine):   ./test-install.sh <distribution> <package.deb>
#     ./test-install.sh trixie work/output/check-mk-community-2.5.0p15_0.trixie_arm64.deb
#
# Steps: creates a minimal <distribution> system (mmdebstrap), installs the package with apt (dependencies included),
# checks dpkg, creates and starts a test site, checks the login page, logs in as cmkadmin and checks that the
# Linux and Windows agents are offered on the "Setup > Agents" pages. Then everything is stopped and deleted.
# The site uses port 5000 on 127.0.0.1: do not run it on a machine that already has a Checkmk site on port 5000.
# The generated cmkadmin password is never displayed.
# =====================================================================================================================
set -u
DIST=${1:-}; P=$(realpath -m "${2:-}")
case "$DIST" in
  bookworm|trixie) MIRROR=http://deb.debian.org/debian; COMP=main; KR=;;
  noble|resolute)  MIRROR=http://ports.ubuntu.com/ubuntu-ports; COMP=main,universe; KR=--keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg;;
  *) echo "usage: $0 <bookworm|trixie|noble|resolute> <package.deb>"; exit 2;;
esac
[ -f "$P" ] && [ "$(id -u)" = 0 ] || { echo "usage: $0 <distribution> <package.deb> (as root)"; exit 2; }
C=$(mktemp -d /var/tmp/checkmk-test-XXXX); SITE=buildtest
log() { echo "[$(date '+%T')] $*"; }
umnt() { findmnt -rn -o TARGET | grep "^$C/" | sort -r | while read -r m; do umount "$m"; done; }   # also the tmpfs of the site
cleanup() { chroot "$C" omd stop $SITE >/dev/null 2>&1; sleep 2; umnt; findmnt -rn -o TARGET | grep -q "^$C" || rm -rf --one-file-system "$C"; }
trap cleanup EXIT

log "1. clean $DIST system in $C"
mmdebstrap --arch=arm64 --variant=apt --components=$COMP $KR --include=ca-certificates,curl,mount "$DIST" "$C" "$MIRROR" >/dev/null 2>&1 \
  || { log "ERROR: mmdebstrap failed"; exit 1; }
mount -t proc proc "$C/proc"; mount -t sysfs sys "$C/sys"; mount --bind /dev "$C/dev"; mount --bind /dev/pts "$C/dev/pts"
mount -t tmpfs -o mode=1777 shm "$C/dev/shm"        # Checkmk (Apache mod_fcgid) needs /dev/shm
cp "$P" "$C/tmp/checkmk.deb"; cp /etc/resolv.conf "$C/etc/"

log "2. apt install of the package (with its dependencies)"
chroot "$C" apt-get -qq update && chroot "$C" env DEBIAN_FRONTEND=noninteractive apt-get -y -qq install /tmp/checkmk.deb >/dev/null 2>&1
log "   apt: code $? ; dpkg --audit: [$(chroot "$C" dpkg --audit 2>&1)] ; $(chroot "$C" omd version 2>&1)"

log "3. omd create / omd start"
chroot "$C" omd create $SITE > "$C/root/create.txt" 2>&1; log "   omd create: code $?"
chroot "$C" omd start $SITE >/dev/null 2>&1;            log "   omd start: code $?"
chroot "$C" omd status $SITE | tail -1

PW=$(grep -o -E "cmkadmin with password: [^ ]+" "$C/root/create.txt" | awk '{print $NF}')
U=http://127.0.0.1:5000/$SITE/check_mk; J=$C/root/cookies
log "4. login page: HTTP $(curl -s -o /dev/null -w '%{http_code}' $U/login.py)"
log "   cmkadmin login: HTTP $(curl -s -o /dev/null -c "$J" -w '%{http_code}' --data-urlencode "_username=cmkadmin" --data-urlencode "_password=$PW" -d "_login=1&_origtarget=index.py" $U/login.py) (302 = OK)"
unset PW
for m in download_agents_linux download_agents_windows; do
  log "   Setup > Agents ($m): $(curl -s -b "$J" "$U/wato.py?mode=$m" | grep -o -E 'check-mk-agent[-_][^"<> ]+\.(deb|rpm)|check_mk_agent\.msi' | sort -u | tr '\n' ' ')"
done
log "5. stop and delete the test system"
