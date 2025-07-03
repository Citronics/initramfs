# Initramfs deb package

This repository contains all the needed files to build a Debian or Ubuntu initramfs package. It installs all the needed files for initramfs-tools to work on the target system.

## Building

Simply run

```./build.sh```

To create the deb package.

## Kernel command line params

This initramfs uses several command line params to shape it's behaviour.

| Param      | Usage      |
| ------------- | ------------- |
| rootfs= | Used to tell the initramfs which subpartition is used for the rootfs. Since it relies on kpartx to map subpartitions, it should be similar to `/dev/mmcblkXpYpZ` where X is the device, Y the partition where the subpartitions are present, and Z the subpartition itself |
| bootpart= | Similar to `rootfs=` except its for the boot partition. It will be mounted under `/sysroot/boot` in the initramfs. It's value should also be of the type `/dev/mmcblkXpYpZ` |
| debug_console=1 | In case you want to skip mounting partitions and go straight to a shell. This also starts a small dhcp server to connect over USB in device mode, and starts a telnet server. |
| resize_rootfs=1 | Use it if you want the rootfs to be resized to the max available space. Useful for full distros, such as Ubuntu/Debian. |

You can set these in your `extlinux.conf` when creating your buildroot image or when building your Debian/Ubuntu image. It can also be changed after booting by modifying it in `/boot/extlinux/extlinux.conf`.
