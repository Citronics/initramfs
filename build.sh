#!/bin/bash
set -e

PKGNAME="citronics-initramfs"

TAG=$(git describe --tags --exact-match 2>/dev/null) || {
  echo "ERROR: No git tag found on current commit. Create a tag first: git tag v1.0.8" >&2
  exit 1
}
VERSION=${TAG#v}

CONTROL_FILE="./initramfs/DEBIAN/control"
sed -i "s/^Version: .*/Version: $VERSION/" "$CONTROL_FILE"

dpkg-deb --build initramfs "$PKGNAME-$VERSION.deb"
echo "Built $PKGNAME-$VERSION.deb"
