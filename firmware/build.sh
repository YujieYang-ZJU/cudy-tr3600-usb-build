#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
recipe=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$recipe/.." && pwd)
source_dir="$root/full-openwrt"
audit="$root/full-audit"
artifacts="$root/full-artifacts"
cache=${SOURCE_CACHE:-$root/input-cache}
jobs=${BUILD_JOBS:-4}
phase=${1:?Specify prepare, configure, download, tools, firmware, collect or source}
external=${USE_EXTERNAL_TOOLCHAIN:-0}
[[ $(uname -s) == Linux ]]
[[ "$external" == 0 || "$external" == 1 ]]
mkdir -p "$audit"
pin() {
    python3 - "$recipe/sources.json" "$1" "$2" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]])
PY
}
checkout() {
    local name="$1" dest="$2" commit
    commit=$(pin "$name" commit)
    [[ ! -e "$dest" ]]
    git init "$dest"
    git -C "$dest" remote add origin "$(pin "$name" url)"
    if [[ -f "$cache/$name.bundle" ]]; then
        git -C "$dest" fetch "$cache/$name.bundle" HEAD
        printf '%s\n' "$commit" > "$dest/.git/shallow"
    else
        git -C "$dest" fetch --depth=1 origin "$commit"
    fi
    git -C "$dest" checkout --detach FETCH_HEAD
    [[ $(git -C "$dest" rev-parse HEAD) == "$commit" ]]
}
if [[ "$phase" == prepare ]]; then
    checkout openwrt "$source_dir"
    git -C "$source_dir" apply --check "$root/crostia-v19/tr3600-support-rebased.patch"
    git -C "$source_dir" apply "$root/crostia-v19/tr3600-support-rebased.patch"
    checkout packages "$root/full-feed-packages"
    checkout luci "$root/full-feed-luci"
    checkout openclash "$root/full-openclash"
    mkdir -p "$source_dir/package/custom" "$source_dir/dl"
    cp -a "$root/full-openclash/luci-app-openclash" "$source_dir/package/custom/"
    cp "$root/full-openclash/LICENSE" "$source_dir/package/custom/luci-app-openclash/LICENSE"
    python3 - "$source_dir/package/custom/luci-app-openclash/Makefile" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
text=p.read_text()
assert 'PKG_NAME:=luci-app-openclash\n' in text
p.write_text(text.replace('PKG_NAME:=luci-app-openclash\n','PKG_NAME:=luci-app-openclash\nPKG_LICENSE:=MIT\nPKG_LICENSE_FILES:=LICENSE\n',1))
PY
    printf 'src-link packages %s\nsrc-link luci %s\n' "$root/full-feed-packages" "$root/full-feed-luci" > "$source_dir/feeds.conf"
    if [[ -f "$cache/linux-6.18.54.tar.xz" ]]; then
        printf '%s  %s\n' 9df30b02dd8102bbd0be52556288ef6889ddbe7f1ddb96fbf847d0becf3eacac "$cache/linux-6.18.54.tar.xz" | sha256sum -c -
        cp "$cache/linux-6.18.54.tar.xz" "$source_dir/dl/"
    fi
    if [[ "$external" == 1 ]]; then
        archive=openwrt-toolchain-mediatek-filogic_gcc-14.4.0_musl.Linux-x86_64.tar.zst
        if [[ ! -f "$cache/$archive" ]]; then
            mkdir -p "$cache"
            curl --fail --location --retry 3 "https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/$archive" -o "$cache/$archive"
        fi
        printf '%s  %s\n' 03071eac19d1f3906e79dc66d0f41c492aa40a005e3d3e2a8b5e33ca7b2a54c4 "$cache/$archive" | sha256sum -c -
        mkdir "$root/full-toolchain"
        tar --zstd -xf "$cache/$archive" -C "$root/full-toolchain"
        compiler=$(find "$root/full-toolchain" -path '*/bin/aarch64-openwrt-linux-musl-gcc' -print -quit)
        [[ $("$compiler" -dumpfullversion) == 14.4.0 ]]
        dirname "$(dirname "$compiler")" > "$audit/toolchain-root.txt"
        "$compiler" -v -E -x c /dev/null -o /dev/null 2> "$audit/compiler-version.txt"
    fi
    exit 0
fi
cd "$source_dir"
case "$phase" in
    configure)
        ./scripts/feeds update -a 2>&1 | tee "$root/full-feeds-update.log"
        ./scripts/feeds install -a 2>&1 | tee "$root/full-feeds-install.log"
        cp "$recipe/config.seed" .config
        if [[ "$external" == 1 ]]; then
            ./scripts/ext-toolchain.sh --toolchain "$(cat "$audit/toolchain-root.txt")" --overwrite-config --config mediatek/filogic
        else
            make defconfig
        fi
        for option in luci-ssl luci-i18n-base-zh-cn luci-compat luci-app-openclash dnsmasq-full kmod-mii kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-usb-net-cdc-ncm usbutils usb-modeswitch kmod-tun kmod-inet-diag kmod-nft-tproxy kmod-nft-socket ruby-yaml; do
            grep -qx "CONFIG_PACKAGE_$option=y" .config || { echo "Required package missing: $option" >&2; exit 1; }
        done
        grep -qx '# CONFIG_PACKAGE_dnsmasq is not set' .config
        grep -qx 'CONFIG_GCC_VERSION="14.4.0"' .config
        cp -a "$recipe/files" .
        chmod 0755 files/etc/uci-defaults/99-tr3600-usbwan
        mkdir -p files/usr/share/licenses/luci-app-openclash
        cp "$root/full-openclash/LICENSE" files/usr/share/licenses/luci-app-openclash/LICENSE
        cp .config "$audit/build.config"
        cp "$recipe/sources.json" "$audit/"
        ;;
    download)
        make -j"$jobs" download 2>&1 | tee "$root/full-download.log"
        # Include the source of runtime libraries copied from the external compiler.
        for spec in \
            'gcc-14.4.0.tar.xz 752b6f567beac83159c77a7680b1316bdd784738bff9a9d070112c09da90f6d9 https://ftp.gnu.org/gnu/gcc/gcc-14.4.0/gcc-14.4.0.tar.xz' \
            'musl-1.2.6.tar.gz d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a https://musl.libc.org/releases/musl-1.2.6.tar.gz'; do
            read -r file digest url <<< "$spec"
            if [[ ! -f "dl/$file" ]]; then curl --fail --location --retry 3 "$url" -o "dl/$file"; fi
            printf '%s  %s\n' "$digest" "dl/$file" | sha256sum -c -
        done
        ;;
    tools)
        make -j"$jobs" tools/install 2>&1 | tee "$root/full-tools.log"
        make -j"$jobs" toolchain/install 2>&1 | tee "$root/full-toolchain.log"
        ;;
    firmware)
        make -j"$jobs" 2>&1 | tee "$root/full-build.log"
        ;;
    collect)
        mkdir -p "$artifacts/packages"
        target=bin/targets/mediatek/filogic
        image=openwrt-mediatek-filogic-cudy_tr3600-v1-squashfs-sysupgrade.bin
        manifest=openwrt-mediatek-filogic-cudy_tr3600-v1.manifest
        cp "$target/$image" "$target/$manifest" "$artifacts/"
        cp .config "$artifacts/build.config"
        cp "$recipe/sources.json" "$artifacts/"
        cp "$root/NOTICE.txt" "$root/LICENSE" "$artifacts/"
        staging_dir/host/bin/fwtool -i "$artifacts/image-metadata.json" "$artifacts/$image"
        for name in kmod-mii kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-usb-net-cdc-ncm; do
            file="$target/packages/$name-6.18.54-r1.apk"
            cp "$file" "$artifacts/"
            staging_dir/host/bin/apk adbdump "$file" > "$artifacts/$name.metadata.txt"
        done
        cp -a "$target/packages" "$artifacts/packages/target"
        cp -a bin/packages/aarch64_cortex-a53 "$artifacts/packages/feeds"
        [[ ! -f key-build.pub ]] || cp key-build.pub "$artifacts/build-signing-key.pub"
        tar -czf "$artifacts/same-build-packages.tar.gz" -C "$artifacts/packages" .
        python3 "$recipe/verify.py" "$artifacts"
        python3 "$recipe/verify-rootfs.py" "$source_dir" "$artifacts" "$audit"
        printf 'Community firmware candidate. Physical flash testing not performed.\nOpenClash UI/dependencies included; proxy core and user configuration not included.\nNormal same-build kernel dependencies; no compatibility metadata override.\nRecipe commit: %s\n' "${GITHUB_SHA:-local}" > "$artifacts/BUILD-INFO.txt"
        (cd "$artifacts" && sha256sum ./*.bin ./*.apk ./*.tar.gz BUILD-INFO.txt > SHA256SUMS)
        ;;
    source)
        bash "$recipe/source-archive.sh" "$root" "$artifacts"
        ;;
    *) echo "Unknown phase: $phase" >&2; exit 1 ;;
esac
