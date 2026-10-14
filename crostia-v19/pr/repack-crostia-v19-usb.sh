#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Repackage only modules already tested on Crostia v1.9; not a general ABI bypass.
set -euo pipefail

cd "${1:-$HOME/build/openwrt-v19}"
root=$(pwd -P)
kernel="$root/build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/linux-6.18.54"
packages="$root/bin/targets/mediatek/filogic/packages"
expected=65a6123c8ad58cc9838d7f2e4fb4e60a
version="6.18.54~${expected}-r1"
names=(kmod-mii kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis)

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ -f "$kernel/.config.set" ]] || fail 'Missing existing kernel build.'
[[ -x staging_dir/host/bin/apk ]] || fail 'Missing OpenWrt host apk tool.'
command -v readelf >/dev/null || fail 'Install binutils first.'
[[ $(git rev-parse HEAD) == 31ef8052449426249b8ea364444df9adab80bfef ]] || fail 'Unexpected source commit; review compatibility again.'
grep -q '^CONFIG_TARGET_mediatek_filogic_DEVICE_cudy_tr3600-v1=y$' .config || fail 'Wrong device profile.'
grep -q '^# CONFIG_MODVERSIONS is not set$' "$kernel/.config" || fail 'Unexpected symbol-version configuration.'

baseline=$(grep '=[ym]' "$kernel/.config.set" |
  grep -vE '^CONFIG_(USB_USBNET|USB_NET_CDCETHER|USB_NET_RNDIS_HOST)=' |
  LC_ALL=C sort | md5sum | awk '{print $1}')
[[ "$baseline" == "$expected" ]] || fail "Baseline hash differs: $baseline"
current=$(grep '=[ym]' "$kernel/.config.set" | LC_ALL=C sort | md5sum | awk '{print $1}')
[[ "$current" == d276c938a20ad6318401925aa33b82de ]] || fail "Unexpected module configuration: $current"

modules=(drivers/net/mii.ko drivers/net/usb/usbnet.ko drivers/net/usb/cdc_ether.ko drivers/net/usb/rndis_host.ko)
for module in "${modules[@]}"; do
  [[ -s "$kernel/$module" ]] || fail "Missing $module"
  readelf -p .modinfo "$kernel/$module" | grep -q 'vermagic=6.18.54 SMP mod_unload aarch64$' || fail "Unexpected vermagic: $module"
done

# Preserve old packages and force their packaging targets to run again.
output=$(mktemp -d "$root/usb-apk-v19.XXXXXX")
mkdir "$output/original-apk"
(cd "$kernel" && sha256sum "${modules[@]}") > "$output/tested-modules.SHA256SUMS"
for name in "${names[@]}"; do
  source="$packages/$name-6.18.54-r1.apk"
  [[ -s "$source" ]] || fail "Missing $source"
done
for name in "${names[@]}"; do
  mv "$packages/$name-6.18.54-r1.apk" "$output/original-apk/"
done

# Command-line assignment changes package dependency metadata only.
# Never distribute the generated kernel package or unrelated packages.
if ! make -j2 package/kernel/linux/compile LINUX_VERMAGIC="$expected" V=s > "$output/repack.log" 2>&1; then
  for name in "${names[@]}"; do
    if [[ ! -e "$packages/$name-6.18.54-r1.apk" ]]; then
      cp "$output/original-apk/$name-6.18.54-r1.apk" "$packages/"
    fi
  done
  tail -n 60 "$output/repack.log"
  fail "Repack failed; originals saved in $output/original-apk"
fi

# Do not treat a freshly changed binary as the one already tested on the router.
(cd "$kernel" && sha256sum -c "$output/tested-modules.SHA256SUMS") || fail 'Module binaries changed during repack; test these binaries again before distribution.'

for name in "${names[@]}"; do
  package="$packages/$name-6.18.54-r1.apk"
  [[ -s "$package" ]] || fail "No rebuilt package: $name"
  staging_dir/host/bin/apk adbdump "$package" > "$output/$name.metadata.txt"
  grep -qF "kernel=$version" "$output/$name.metadata.txt" || fail "Wrong kernel dependency: $name"
  grep -q 'arch: aarch64_cortex-a53$' "$output/$name.metadata.txt" || fail "Wrong architecture: $name"
  cp "$package" "$output/"
done
(cd "$output" && sha256sum ./*.apk > SHA256SUMS)
printf '\nFour packages collected in: %s\n' "$output"
printf 'Kernel dependency: %s\n' "$version"
printf 'APK installation and reboot verification are still required.\n'
