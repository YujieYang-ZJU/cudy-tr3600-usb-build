#!/usr/bin/env bash
set -euo pipefail
recipe=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$recipe/.." && pwd)
source_dir="$root/usb-openwrt"
audit="$root/usb-audit"
artifacts="$root/usb-artifacts"
commit=31ef8052449426249b8ea364444df9adab80bfef
expected=65a6123c8ad58cc9838d7f2e4fb4e60a
jobs=${BUILD_JOBS:-2}
phase=${1:?Specify a build phase}
mkdir -p "$audit"

if [[ "$phase" == prepare ]]; then
  [[ $(uname -s) == Linux ]]
  [[ ! -e "$source_dir" ]]
  git init "$source_dir"
  git -C "$source_dir" remote add origin https://github.com/openwrt/openwrt.git
  git -C "$source_dir" fetch --depth=1 origin "$commit"
  git -C "$source_dir" checkout --detach FETCH_HEAD
  git -C "$source_dir" apply --check "$recipe/tr3600-support-rebased.patch"
  git -C "$source_dir" apply "$recipe/tr3600-support-rebased.patch"
  archive=openwrt-toolchain-mediatek-filogic_gcc-14.4.0_musl.Linux-x86_64.tar.zst
  curl --fail --location --retry 3 "https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/$archive" -o "$root/$archive"
  printf '%s  %s\n' 03071eac19d1f3906e79dc66d0f41c492aa40a005e3d3e2a8b5e33ca7b2a54c4 "$root/$archive" | sha256sum -c -
  mkdir "$root/usb-toolchain"
  tar --zstd -xf "$root/$archive" -C "$root/usb-toolchain"
  compiler=$(find "$root/usb-toolchain" -path '*/bin/aarch64-openwrt-linux-musl-gcc' -print -quit)
  [[ -x "$compiler" ]]
  [[ $("$compiler" -dumpfullversion) == 14.4.0 ]]
  dirname "$(dirname "$compiler")" > "$audit/toolchain-root.txt"
  "$compiler" -v -E -x c /dev/null -o /dev/null 2> "$audit/compiler-version.txt"
  exit 0
fi

cd "$source_dir"
case "$phase" in
  configure)
    # Every shipped kernel package is selected to preserve the kernel Kconfig.
    # User-space plugin feeds are not needed to compile these four core drivers.
    python3 - "$recipe/reference" <<'PY'
from pathlib import Path
import sys
ref = Path(sys.argv[1])
lines = ['CONFIG_TARGET_mediatek=y', 'CONFIG_TARGET_mediatek_filogic=y',
         'CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3600-v1=y']
for item in (ref / 'openwrt-mediatek-filogic-cudy_tr3600-v1.manifest').read_text().splitlines():
    if item.startswith('kmod-'):
        lines.append('CONFIG_PACKAGE_' + item.split(' - ', 1)[0] + '=y')
for item in (ref / 'config.buildinfo').read_text().splitlines():
    if item.startswith(('CONFIG_KERNEL_', '# CONFIG_KERNEL_')):
        lines.append(item)
for package in ['mii', 'usb-net', 'usb-net-cdc-ether', 'usb-net-rndis']:
    lines.append('CONFIG_PACKAGE_kmod-' + package + '=m')
Path('.config').write_text('\n'.join(lines) + '\n')
PY
    ./scripts/ext-toolchain.sh --toolchain "$(cat "$audit/toolchain-root.txt")" --overwrite-config --config mediatek/filogic 2>&1 | tee "$root/usb-configure.log"
    for name in mii usb-net usb-net-cdc-ether usb-net-rndis; do
      grep -qx "CONFIG_PACKAGE_kmod-$name=m" .config
    done
    python3 "$recipe/check-kernel-plan.py" "$source_dir" "$audit" 2>&1 | tee "$root/usb-plan-check.log"
    cp .config "$audit/build.config"
    ;;
  tools)
    make -j"$jobs" tools/download target/linux/download 2>&1 | tee "$root/usb-download.log"
    make -j"$jobs" tools/install 2>&1 | tee "$root/usb-tools.log"
    make -j"$jobs" toolchain/install 2>&1 | tee "$root/usb-toolchain.log"
    make -j"$jobs" package/system/apk/host/compile 2>&1 | tee "$root/usb-apk-host.log"
    ;;
  kernel)
    make -j"$jobs" target/compile 2>&1 | tee "$root/usb-kernel.log"
    kernel="$source_dir/build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/linux-6.18.54"
    cmp "$audit/kernel.config.set.plan" "$kernel/.config.set"
    [[ $(cat "$kernel/.vermagic") == d276c938a20ad6318401925aa33b82de ]]
    grep -qx '# CONFIG_MODVERSIONS is not set' "$kernel/.config"
    cp "$kernel/.config" "$audit/kernel.config.actual"
    ;;
  package)
    kernel="$source_dir/build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/linux-6.18.54"
    modules=(drivers/net/mii.ko drivers/net/usb/usbnet.ko drivers/net/usb/cdc_ether.ko drivers/net/usb/rndis_host.ko)
    for module in "${modules[@]}"; do
      readelf -p .modinfo "$kernel/$module" | grep -q 'vermagic=6.18.54 SMP mod_unload aarch64$'
    done
    (cd "$kernel" && sha256sum "${modules[@]}") > "$audit/modules-before-packaging.SHA256SUMS"
    make -j"$jobs" package/kernel/linux/compile V=s 2>&1 | tee "$root/usb-package.log"
    # The PR checks the original hash after removing only three new Kconfig lines.
    # This gate must pass before changing any APK dependency metadata.
    python3 "$recipe/check-kernel-plan.py" "$source_dir" "$audit"
    bash "$recipe/pr/repack-crostia-v19-usb.sh" "$source_dir" 2>&1 | tee "$root/usb-repack.log"
    (cd "$kernel" && sha256sum -c "$audit/modules-before-packaging.SHA256SUMS")
    mkdir -p "$artifacts/metadata"
    for name in kmod-mii kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis; do
      package="bin/targets/mediatek/filogic/packages/$name-6.18.54-r1.apk"
      staging_dir/host/bin/apk adbdump "$package" > "$artifacts/metadata/$name.txt"
      grep -qF "kernel=6.18.54~$expected-r1" "$artifacts/metadata/$name.txt"
      grep -q 'arch: aarch64_cortex-a53$' "$artifacts/metadata/$name.txt"
      cp "$package" "$artifacts/"
    done
    # Keep the unstripped modules and exact configuration for independent inspection.
    mkdir -p "$artifacts/module-audit"
    for module in "${modules[@]}"; do cp "$kernel/$module" "$artifacts/module-audit/"; done
    cp "$audit/kernel-plan-check.json" "$audit/build.config" "$audit/kernel.config.actual" "$artifacts/metadata/"
    python3 "$recipe/verify-packages.py" "$source_dir" "$artifacts"
    {
      printf 'OpenWrt source: %s\n' "$commit"
      printf 'Hardware patch: soapmancn/openwrt@6d99cc1ee93424cae10285f83f015fc8a7c31713 (context rebased)\n'
      printf 'PR recipe: 352508290-source/openwrt-Cudy-TR3600-v1@a7158db3f89c751dbc028082c1dd613df7b925b6\n'
      printf 'Build recipe: %s\n' "${GITHUB_SHA:-local}"
      printf 'Build run: %s/%s/actions/runs/%s\n' "${GITHUB_SERVER_URL:-local}" "${GITHUB_REPOSITORY:-local}" "${GITHUB_RUN_ID:-local}"
      printf 'This is a new build reproducing the PR configuration; NOT the original device-tested binaries.\n'
      printf 'Package dependency was adapted to Crostia v1.9 after configuration gates passed. Physical device testing remains required.\n'
    } > "$artifacts/BUILD-INFO.txt"
    (cd "$artifacts" && sha256sum ./*.apk BUILD-INFO.txt > SHA256SUMS && sha256sum -c SHA256SUMS)
    ;;
  *) echo "Unknown build phase: $phase" >&2; exit 1 ;;
esac
