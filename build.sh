#!/bin/bash
set -e

PKGNAME="citronics-initramfs"

TAG=$(git describe --tags --exact-match 2>/dev/null) || {
  echo "ERROR: No git tag found on current commit. Create a tag first: git tag v1.0.8" >&2
  exit 1
}
# Map release-candidate tags to Debian pre-release versions:
# v1.1.1-rc1 -> 1.1.1~rc1 (git tags cannot contain '~', but only '~rc'
# sorts BELOW the final 1.1.1 in dpkg version ordering; '-rc1' or 'rc1'
# would sort above it and apt would never upgrade RC -> final).
VERSION=$(echo "${TAG#v}" | sed 's/-rc/~rc/')

CONTROL_FILE="./initramfs/DEBIAN/control"
sed -i "s/^Version: .*/Version: $VERSION/" "$CONTROL_FILE"

# --root-owner-group, or every file keeps the uid/gid of whoever built it: the
# 1.1.2.1 deb installed /usr/share/citronics/detect-dtb.sh as 1001:1001, the
# GitHub runner's own user, as seen on the phone. That file is *sourced by root*
# from /etc/kernel/postinst.d/zz-citronics-boot, so on a machine where uid 1001
# is an ordinary user, that user could rewrite what root runs on the next kernel
# upgrade.
dpkg-deb --root-owner-group --build initramfs "$PKGNAME-$VERSION.deb"
echo "Built $PKGNAME-$VERSION.deb"
