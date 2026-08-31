# livecd-rootfs / live-build patches

`ci-scripts/container-build.sh` applies these to the **installed** livecd-rootfs
and live-build files inside the build container before running `lb build`.
They are context diffs against specific package versions, so they need
re-deriving whenever those packages change shape.

**Current baseline (resolute):** `livecd-rootfs 26.04.35`, `live-build 3.0~a57-1ubuntu54`.
Re-derived 2026-08-30 from the noble patches in `tachyon-ubuntu-24.04` (all 7
intents carried over unchanged; none had been absorbed upstream).

## Intent of each patch

| Patch | Target (installed path) | Intent |
|---|---|---|
| `minimize-manual.patch` | `/usr/share/livecd-rootfs/minimize-manual` | Don't fail the build when some packages can't be marked auto — warn and `exit 0`. (Resolute note: the script now uses `${LIVECD_ROOTFS_ROOT}` instead of hardcoded paths; the intent is applied to the final assertion line.) |
| `lb_chroot_apt.patch` | `/usr/lib/live/build/lb_chroot_apt` | Add `Acquire::Retries "20"` to the chroot's apt config for the duration of the build (and remove it in the deconfigure pass) so transient mirror failures don't kill a multi-hour build. |
| `lb_binary_package-lists.patch` | `/usr/lib/live/build/lb_binary_package-lists` | Bind-mount `/run` and mount `proc` into the chroot, and run `apt-get update` before the `--download-only` step for binary package lists (the stock script downloads against stale/absent indices); unmount after. |
| `999-ubuntu-image-customization.chroot.patch` | `.../ubuntu-cpc/hooks.d/chroot/999-ubuntu-image-customization.chroot` | Also take the nocloud-datasource-on-boot-partition path when `IMAGE_TARGETS` contains `non-cloud`, not only when `IMAGEFORMAT=none` — our `disk-image-non-cloud` target needs the same cloud-init seeding. |
| `config.patch` | `.../live-build/auto/config` | (a) Double `--ext-resize-blocks` (536870912 → ×2) in **all** of its occurrences (3 on resolute) so the rootfs can later be resized to fill the Tachyon system partition; (b) add an `IMAGE_FORCE_HOOKS` escape hatch so binary hooks are kept even when `IMAGEFORMAT=none` logic would remove them. |
| `disk-image-uefi.patch` | `.../ubuntu-cpc/hooks.d/base/disk-image-uefi.binary` | Bump the amd64/arm64/armhf disk image size 3.5 GiB → 4.5 GiB (our rootfs doesn't fit the stock size). Drop this patch if upstream ever raises the default to ≥ 4.5 GiB. |
| `functions.patch` | `.../live-build/functions` | (a) Double the ext4 `-E resize=` limit in `make_ext4_partition` (same rationale as config.patch (a) — both places must agree). (b) Force `should_include_sbom=false` in `create_manifest`: resolute's cpc hooks generate an SPDX SBOM via the `cpc-sbom` snap, which requires snapd — unavailable inside the build container — and we don't ship the SBOM. |

## Re-deriving against a new livecd-rootfs/live-build

1. In an `ubuntu:26.04` container: `apt-get update && apt-get download livecd-rootfs live-build`,
   then `dpkg-deb -R` both into a scratch dir → pristine `orig/` copies of the 7 target files.
2. Copy `orig/` → `work/`; try each existing patch with `patch --dry-run -F3 work/<file> stuff/<patch>`.
   Where it applies, apply and **review the result in context** (fuzz can misplace hunks);
   where it fails, re-apply the intent from the table above by hand.
3. For `config.patch`, grep `work/config` for **every** `ext-resize-blocks` occurrence and make
   sure all are doubled — the count has changed between series before.
4. Regenerate: `diff -u --label <installed-path>.orig --label <installed-path> orig/<file> work/<file>`.
5. Gate: fresh `orig/` copies must take every regenerated patch with **zero fuzz/offset output**
   and end up byte-identical to `work/`.
