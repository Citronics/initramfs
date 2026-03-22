# Citronics Initramfs

Custom initramfs package for Debian and Ubuntu on the Citronics Lime (Fairphone 2) board. Installs all the necessary files for initramfs-tools to work on the target system.

## Prerequisites

- `dpkg-deb` (available on any Debian/Ubuntu system)
- `gh` CLI (for publishing releases)

## Building

Tag the commit you want to release, then run the build script:

```
git tag v1.0.9
./build.sh
```

This produces `citronics-initramfs-<version>.deb`.

## Releasing

To build and publish a release to GitHub in one step:

```
git tag v1.0.9
git push origin v1.0.9
./release.sh
```

`release.sh` calls `build.sh`, then uploads the `.deb` to a GitHub Release. After releasing, trigger the [deb-packages](https://github.com/Citronics/deb-packages) workflow to update the APT repository.

## Kernel command line params

This initramfs uses several command line params to shape its behaviour.

| Param | Usage |
| --- | --- |
| `rootfs=` | Tells the initramfs which subpartition is used for the rootfs. Since it relies on kpartx to map subpartitions, it should be similar to `/dev/mmcblkXpYpZ` where X is the device, Y the partition where the subpartitions are present, and Z the subpartition itself. |
| `bootpart=` | Similar to `rootfs=` except it's for the boot partition. It will be mounted under `/sysroot/boot` in the initramfs. Its value should also be of the type `/dev/mmcblkXpYpZ`. |
| `debug_console=1` | Skip mounting partitions and go straight to a shell. Also starts a small DHCP server for USB device mode connectivity and a telnet server. |
| `resize_rootfs=1` | Resize the rootfs to the max available space. Useful for full distros such as Ubuntu/Debian. |

You can set these in your `extlinux.conf` when creating your buildroot image or when building your Debian/Ubuntu image. They can also be changed after booting by modifying `/boot/extlinux/extlinux.conf`.
