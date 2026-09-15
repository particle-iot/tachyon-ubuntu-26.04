#!/bin/bash

# Builds the Tachyon Ubuntu 26.04 base rootfs image. Must run INSIDE a
# privileged ubuntu:26.04 container (see ci-scripts/build.sh, the host-side
# wrapper): livecd-rootfs/live-build are installed from the running system's
# archive, so the build environment's series must equal the target series.
# The repo is expected to be mounted read-write at the path this script lives
# under; output lands in <repo>/build/rootfs.img.xz.

case "$1" in
    desktop)
        export PROJECT=ubuntu
        export SUBPROJECT=desktop-preinstalled
        export IMAGE_SIZE=$((5*1024*1024*1024)) # 5GB
        ;;
    headless)
        export PROJECT=ubuntu-cpc
        export IMAGE_SIZE=$((4*1024*1024*1024)) # 4GB
        ;;
    *)
        echo "Unknown image type"
        exit 1
        ;;
esac

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root (inside the build container)" >&2
    exit 1
fi

DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

cd "$DIR"

export DEBIAN_FRONTEND=noninteractive

# qemu-user-static is a virtual package on resolute; qemu-user-binfmt provides
# it and ships /usr/bin/qemu-aarch64 (no -static suffix). Only used by
# live-build for foreign-arch bootstrap, which a native arm64 build never hits.
apt-get update -y
apt-get upgrade -y
apt-get install livecd-rootfs qemu-user-binfmt binfmt-support patch wget ca-certificates xz-utils -y

# Patch buggy minimize-manual
patch /usr/share/livecd-rootfs/minimize-manual $DIR/stuff/minimize-manual.patch
# Patch lb_chroot_apt to retry
patch /usr/lib/live/build/lb_chroot_apt $DIR/stuff/lb_chroot_apt.patch

patch /usr/lib/live/build/lb_binary_package-lists $DIR/stuff/lb_binary_package-lists.patch

patch /usr/share/livecd-rootfs/live-build/ubuntu-cpc/hooks.d/chroot/999-ubuntu-image-customization.chroot $DIR/stuff/999-ubuntu-image-customization.chroot.patch
patch /usr/share/livecd-rootfs/live-build/auto/config $DIR/stuff/config.patch
patch /usr/share/livecd-rootfs/live-build/ubuntu-cpc/hooks.d/base/disk-image-uefi.binary $DIR/stuff/disk-image-uefi.patch

patch /usr/share/livecd-rootfs/live-build/functions $DIR/stuff/functions.patch

mkdir -p build
cd build

cp -r "$(dpkg -L livecd-rootfs | grep "auto$")" auto

export SUITE=resolute

export RELEASE_NAME="Ubuntu 26.04 LTS (Resolute Raccoon)"
export RELEASE_VERSION="26.04"
export KERNEL_FLAVOR="particle"
# The base installs the LATEST linux-particle from the noble-stable pocket added
# below (unpinned, same mechanism as 24.04). ABI is 1058. As of 2026-09-15 that
# is 6.8.0-1058.59+particle9; this build is cut to pick it up so 26.04's baked
# kernel matches 24.04 (the previous 31-f5ca035 base baked +particle8, and
# 29-29469e9 before it baked +particle6). The composer pins the exact kernel deb,
# and check-pinned-packages fails if this base ever drifts from it — so re-cut the
# base whenever the pinned kernel moves.

export ARCH=arm64
export IMAGEFORMAT=ext4
export IMAGE_HAS_HARDCODED_PASSWORD=1
export IMAGE_FORCE_HOOKS=true
export IMAGE_TARGETS=disk-image-non-cloud,disk1-img-xz

# Use the generic Ubuntu ports mirror unless the caller overrides it. Do NOT
# region-pin here: the mirror baked in below by livecd-rootfs is also what
# shipped devices apt against, and a region pool degrading has taken builds
# down before (see tachyon-overlays/use-generic-ubuntu-mirror, 2026-08-26).
export APT_MIRROR="${APT_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}"

unset DEBIAN_FRONTEND

sed -i '1s/^/set -x\n/' $HOME/.bashrc
mv /bin/sh /bin/sh.orig
cat << 'EOF' > /bin/sh
#!/bin/sh.orig

exec /bin/sh.orig -x "$@"
EOF
chmod +x /bin/sh

lb config \
    --architecture arm64 \
    --bootstrap-qemu-arch arm64 \
    --bootstrap-qemu-static /usr/bin/qemu-aarch64 \
    --archive-areas "main restricted universe multiverse" \
    --parent-archive-areas "main restricted universe multiverse" \
    --mirror-bootstrap "${APT_MIRROR}" \
    --parent-mirror-bootstrap "${APT_MIRROR}" \
    --mirror-chroot-security "${APT_MIRROR}" \
    --parent-mirror-chroot-security "${APT_MIRROR}" \
    --mirror-binary-security "${APT_MIRROR}" \
    --parent-mirror-binary-security "${APT_MIRROR}" \
    --mirror-binary "${APT_MIRROR}" \
    --parent-mirror-binary "${APT_MIRROR}" \
    --mirror-chroot "${APT_MIRROR}" \
    --parent-mirror-chroot "${APT_MIRROR}" \
    --keyring-packages ubuntu-keyring \
    --linux-flavours "${KERNEL_FLAVOR}" \
    --initramfs none \
    --system normal

# Add some default packages
cat >> config/package-lists/particle-ubuntu.list.chroot <<EOF
software-properties-common
network-manager
EOF
cp -a config/package-lists/particle-ubuntu.list.chroot config/package-lists/particle-ubuntu.list.binary

# Add particle repo
# TODO: migrate to a resolute-stable pocket once one is published; the noble
# debs (kernel included) are series-portable and install cleanly on resolute.
cat >> config/archives/particle-ubuntu.list.chroot <<EOF
deb [signed-by=/etc/apt/trusted.gpg.d/particle.key.gpg] http://packages.particle.io/ubuntu noble-stable main
EOF
cp -a config/archives/particle-ubuntu.list.chroot config/archives/particle-ubuntu.list.binary

wget -O config/archives/particle.key https://packages.particle.io/public-keyring.gpg

touch config/universe-enabled

lb build --verbose --debug

if [ "$PROJECT" == "ubuntu" ]; then
    xz -T4 -c binary/boot/disk-uefi.ext4 > $DIR/build/rootfs.img.xz
else
    mv livecd.ubuntu-cpc.disk1.img.xz $DIR/build/rootfs.img.xz
fi

exit 0
