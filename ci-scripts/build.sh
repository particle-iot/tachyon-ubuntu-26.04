#!/bin/bash

# Host-side entry point: runs the real build (ci-scripts/container-build.sh)
# inside a privileged ubuntu:26.04 container. livecd-rootfs/live-build come
# from the build environment's own archive, so containerising pins the build
# environment to the target series regardless of the host/runner distro, and
# keeps container-build.sh's global mutations (/bin/sh tracing wrapper, apt
# upgrade) off the host. --privileged is required for the loop devices and
# chroot mounts lb build uses.
#
# Usage: ci-scripts/build.sh <headless|desktop>
# Output: <repo>/build/rootfs.img.xz
# Env: APT_MIRROR (optional) — Ubuntu ports mirror override, passed through.

set -euo pipefail

VARIANT="${1:?usage: build.sh <headless|desktop>}"

DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

docker run --rm --privileged \
    -v "${DIR}:/repo" \
    -w /repo \
    ${APT_MIRROR:+-e APT_MIRROR="${APT_MIRROR}"} \
    ubuntu:26.04 \
    bash /repo/ci-scripts/container-build.sh "${VARIANT}"
