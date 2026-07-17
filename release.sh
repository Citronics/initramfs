#!/bin/bash
set -e

TAG=$(git describe --tags --exact-match)
# Same tag -> version mapping as build.sh (v1.1.1-rc1 -> 1.1.1~rc1)
VERSION=$(echo "${TAG#v}" | sed 's/-rc/~rc/')

echo "Building citronics-initramfs $VERSION..."
./build.sh

DEB="citronics-initramfs-${VERSION}.deb"
if [ ! -f "$DEB" ]; then
  echo "ERROR: Expected $DEB not found"
  exit 1
fi

# Mark release candidates as GitHub pre-releases
PRERELEASE=""
case "$TAG" in
  *-rc*) PRERELEASE="--prerelease" ;;
esac

echo "Creating GitHub release $TAG..."
gh release create "$TAG" "$DEB" $PRERELEASE \
  --repo Citronics/initramfs \
  --title "citronics-initramfs $VERSION" \
  --notes "Release $VERSION"

echo "Done. Release $TAG published with $DEB"
