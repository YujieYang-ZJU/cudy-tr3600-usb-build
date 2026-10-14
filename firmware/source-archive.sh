#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
root=${1:?project root}
artifacts=${2:?artifact directory}
stage=$(mktemp -d "$root/full-source.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
for pair in 'openwrt full-openwrt' 'packages full-feed-packages' 'luci full-feed-luci' 'openclash full-openclash'; do
    read -r name directory <<< "$pair"
    git -C "$root/$directory" archive --format=tar --prefix="$name/" -o "$stage/$name-source.tar" HEAD
done
mkdir "$stage/recipe" "$stage/build-records"
# Explicit public inputs; do not copy the build root or its private signing key.
for name in .github .gitignore LICENSE COPYING NOTICE.txt README.md build-firmware.sh verify-artifacts.py config crostia-v19 docs firmware patches; do
    cp -a "$root/$name" "$stage/recipe/"
done
find "$stage/recipe" -type d -name __pycache__ -prune -exec rm -rf {} +
cp "$artifacts/build.config" "$artifacts/sources.json" "$artifacts/VERIFICATION.json" "$artifacts/ROOTFS-VERIFICATION.json" "$artifacts/BUILD-INFO.txt" "$stage/build-records/"
cp -a "$root/full-openwrt/dl" "$stage/downloads"
cp "$root/LICENSE" "$stage/"
printf 'Corresponding source for this firmware and its same-build package archive.\nIncludes pinned OpenWrt/feed/OpenClash source, recipe and patches, actual configuration, and downloaded component sources.\nExtract openwrt-source.tar; apply the hardware patch from recipe/crostia-v19; firmware/build.sh records the remaining transformations.\nPrivate signing keys, credentials and personal router configurations are not included.\n' > "$stage/README-SOURCE.txt"
tar --owner=0 --group=0 --numeric-owner -czf "$artifacts/corresponding-source.tar.gz" -C "$stage" .
(cd "$artifacts" && sha256sum corresponding-source.tar.gz >> SHA256SUMS)
