#!/bin/bash
set -e

PKGNAME="citronics-initramfs"
VERSION_FILE="./initramfs/VERSION"
VERSION=$(cat "$VERSION_FILE")

# Optional: auto-increment patch version
if [ "$1" == "bump" ]; then
  MAJOR=$(echo $VERSION | cut -d. -f1)
  MINOR=$(echo $VERSION | cut -d. -f2)
  PATCH=$(echo $VERSION | cut -d. -f3)
  PATCH=$((PATCH + 1))
  VERSION="$MAJOR.$MINOR.$PATCH"
  echo $VERSION > "$VERSION_FILE"
  echo "Bumped version to $VERSION"
fi

# Update the control file
CONTROL_FILE="./initramfs/DEBIAN/control"
sed -i "s/^Version: .*/Version: $VERSION/" "$CONTROL_FILE"

# Build the .deb
dpkg-deb --build initramfs "$PKGNAME-$VERSION.deb"
echo "Built $PKGNAME-$VERSION.deb"
