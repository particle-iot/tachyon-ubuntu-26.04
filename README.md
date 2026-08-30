# tachyon-ubuntu-26.04

Builds the **Ubuntu 26.04 LTS (Resolute Raccoon)** base rootfs images for
Particle Tachyon (QCM6490), consumed downstream by
[tachyon-composer](https://github.com/particle-iot/tachyon-composer).
Forked from
[tachyon-ubuntu-24.04](https://github.com/particle-iot/tachyon-ubuntu-24.04).

### Chroot/rootfs

We use [livecd-rootfs](https://launchpad.net/livecd-rootfs) (resolute) to build
the 26.04 rootfs, with the local patches in `stuff/` — see
[`stuff/PATCHES.md`](stuff/PATCHES.md) for what each patch does and how to
re-derive them against a new livecd-rootfs.

### Kernel

There is no Canonical/Qualcomm `linux-qcom` kernel for 26.04, so the images
ship the same Particle 6.8 kernel line as the 24.04 images
([tachyon-ubuntu-24.04-kernel](https://github.com/particle-iot/tachyon-ubuntu-24.04-kernel),
a fork of the noble
[linux-qcom](https://git.codelinaro.org/clo/le/canonical-kernel/ubuntu/source/linux-qcom/noble/-/tree/canonical/master-next)
tree). The kernel and the other Particle debs are pulled from the
`packages.particle.io/ubuntu noble-stable` pocket — the noble-built debs are
series-portable (TODO: migrate to a `resolute-stable` pocket).

### Building

The build runs inside a privileged `ubuntu:26.04` container, so any host with
Docker works (the runner's distro does not need to be 26.04):

```bash
ci-scripts/build.sh headless   # or: desktop
# → build/rootfs.img.xz
```

CI is GitHub Actions (`.github/workflows/build.yml`): builds both variants on
every push/PR and uploads `tachyon-ubuntu-26.04-<variant>-<tag>.img.xz` to
`https://linux-dist.particle.io/{release,prerelease}/`. A GitHub release is
cut on main/tag builds when the repo variable `GHA_CREATE_RELEASE` is `true`.
