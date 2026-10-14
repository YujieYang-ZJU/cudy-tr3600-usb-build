#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

BUILD_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OPENWRT_COMMIT=046aec0dccd90f5a156cb8e9725c121c81955dd3
REFERENCE_COMMIT=58d04dab73dd482f7c288cbdf3b3e30de29f0ae7
SOURCE_DIR="$BUILD_ROOT/openwrt"
ARTIFACT_DIR="$BUILD_ROOT/artifacts"
JOBS=${BUILD_JOBS:-2}
PHASE=${1:-all}

if [[ $(uname -s) != Linux ]]; then
  printf 'This firmware build requires Linux. Use the included GitHub Actions workflow.\n' >&2
  exit 1
fi
if [[ "$PHASE" == all ]]; then
  for phase in prepare configure download toolchain kernel firmware collect; do
    bash "$BUILD_ROOT/build-firmware.sh" "$phase"
  done
  exit 0
fi

if [[ "$PHASE" == prepare ]]; then
  if [[ -e "$SOURCE_DIR" ]]; then
    printf 'The openwrt build directory already exists; use a clean workspace.\n' >&2
    exit 1
  fi
  git init "$SOURCE_DIR"
  git -C "$SOURCE_DIR" remote add origin https://github.com/openwrt/openwrt.git
  git -C "$SOURCE_DIR" fetch --depth=1 origin "$OPENWRT_COMMIT"
  git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD
  [[ $(git -C "$SOURCE_DIR" rev-parse HEAD) == "$OPENWRT_COMMIT" ]]
  git -C "$SOURCE_DIR" apply --check "$BUILD_ROOT/patches/cudy-tr3600-v1-fixes.patch"
  git -C "$SOURCE_DIR" apply "$BUILD_ROOT/patches/cudy-tr3600-v1-fixes.patch"
  cp "$BUILD_ROOT/config/feeds.conf" "$SOURCE_DIR/feeds.conf"
  exit 0
fi

cd "$SOURCE_DIR"
case "$PHASE" in
  configure)
    ./scripts/feeds update -a 2>&1 | tee "$BUILD_ROOT/feeds-update.log"
    ./scripts/feeds install luci-ssl luci-i18n-base-zh-cn luci-proto-wireguard usbutils 2>&1 | tee "$BUILD_ROOT/feeds-install.log"
    cp "$BUILD_ROOT/config/tr3600-usb.config" .config
    make defconfig 2>&1 | tee "$BUILD_ROOT/defconfig.log"
    for setting in \
      CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3600-v1 \
      CONFIG_PACKAGE_luci-ssl \
      CONFIG_PACKAGE_kmod-usb-net \
      CONFIG_PACKAGE_kmod-usb-net-cdc-ether \
      CONFIG_PACKAGE_kmod-usb-net-rndis \
      CONFIG_PACKAGE_kmod-usb-net-cdc-ncm \
      CONFIG_PACKAGE_usbutils \
      CONFIG_PACKAGE_usb-modeswitch; do
      if ! grep -qx "${setting}=y" .config; then
        printf 'Required setting missing after defconfig: %s\n' "$setting" >&2
        exit 1
      fi
    done
    ;;
  download)
    make -j"$JOBS" download 2>&1 | tee "$BUILD_ROOT/download.log"
    ;;
  toolchain)
    make -j"$JOBS" tools/install 2>&1 | tee "$BUILD_ROOT/tools.log"
    make -j"$JOBS" toolchain/install 2>&1 | tee "$BUILD_ROOT/toolchain.log"
    ;;
  kernel)
    make -j"$JOBS" target/compile 2>&1 | tee "$BUILD_ROOT/kernel.log"
    ;;
  firmware)
    if ! make -j"$JOBS" 2>&1 | tee "$BUILD_ROOT/build.log"; then
      make -j1 V=s 2>&1 | tee "$BUILD_ROOT/build-retry.log"
    fi
    ;;
  collect)
    TARGET_DIR="$SOURCE_DIR/bin/targets/mediatek/filogic"
    IMAGE_NAME=openwrt-mediatek-filogic-cudy_tr3600-v1-squashfs-sysupgrade.bin
    MANIFEST_NAME=openwrt-mediatek-filogic-cudy_tr3600-v1.manifest
    mkdir -p "$ARTIFACT_DIR"
    cp "$TARGET_DIR/$IMAGE_NAME" "$ARTIFACT_DIR/"
    cp "$TARGET_DIR/$MANIFEST_NAME" "$ARTIFACT_DIR/"
    cp .config "$ARTIFACT_DIR/build.config"
    cp feeds.conf "$ARTIFACT_DIR/feeds.conf"
    cp "$BUILD_ROOT/NOTICE.txt" "$ARTIFACT_DIR/"
    staging_dir/host/bin/fwtool -i "$ARTIFACT_DIR/image-metadata.json" "$ARTIFACT_DIR/$IMAGE_NAME"
    python3 "$BUILD_ROOT/verify-artifacts.py" "$ARTIFACT_DIR"
    {
      printf 'OpenWrt source: https://github.com/openwrt/openwrt/tree/%s\n' "$OPENWRT_COMMIT"
      printf 'Hardware fixes: https://github.com/hyqhyq3/openwrt-cudy-tr3600/tree/%s\n' "$REFERENCE_COMMIT"
      printf 'Build repository commit: %s\n' "${GITHUB_SHA:-local}"
      printf 'Build run: %s/%s/actions/runs/%s\n' "${GITHUB_SERVER_URL:-local}" "${GITHUB_REPOSITORY:-local}" "${GITHUB_RUN_ID:-local}"
      printf 'Built at UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'Feeds:\n'
      for feed in packages luci routing telephony video; do
        printf '%s %s\n' "$feed" "$(git -C "feeds/$feed" rev-parse HEAD)"
      done
    } > "$ARTIFACT_DIR/build-info.txt"
    cd "$ARTIFACT_DIR"
    sha256sum "$IMAGE_NAME" "$MANIFEST_NAME" image-metadata.json build.config feeds.conf NOTICE.txt build-info.txt > SHA256SUMS
    sha256sum -c SHA256SUMS
    ;;
  *)
    printf 'Unknown build phase: %s\n' "$PHASE" >&2
    exit 1
    ;;
esac
