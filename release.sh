#!/bin/bash
set -e

TAG=$(git describe --tags --exact-match)
VERSION=${TAG#v}

echo "Building citronics-initramfs $VERSION..."
./build.sh

DEB="citronics-initramfs-${VERSION}.deb"
if [ ! -f "$DEB" ]; then
  echo "ERROR: Expected $DEB not found"
  exit 1
fi

echo "Creating GitHub release $TAG..."
gh release create "$TAG" "$DEB" \
  --repo Citronics/initramfs \
  --title "citronics-initramfs $VERSION" \
  --notes "Release $VERSION"

echo "Done. Release $TAG published with $DEB"
