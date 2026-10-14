#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
recipe=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_dir=${1:?source directory}
audit=${2:?audit directory}
artifacts=${3:?artifact directory}
kernel=${4:?kernel directory}
expected=65a6123c8ad58cc9838d7f2e4fb4e60a
[[ ${USB_NCM:-0} == 1 ]]
cd "$source_dir"
[[ $(git rev-parse HEAD) == 31ef8052449426249b8ea364444df9adab80bfef ]]
python3 "$recipe/check-kernel-plan.py" "$source_dir" "$audit"
cmp "$audit/kernel.config.set.plan" "$kernel/.config.set"
grep -qx '# CONFIG_MODVERSIONS is not set' "$kernel/.config"
python3 - "$recipe/reference/kernel.config.usb4" "$kernel/.config" <<'PY'
from pathlib import Path
import json, sys
def options(path):
    return {line for line in Path(path).read_text().splitlines()
            if line.startswith(('CONFIG_', '# CONFIG_'))}
before, after = map(options, sys.argv[1:])
assert before - after == {'# CONFIG_USB_NET_CDC_NCM is not set'}, sorted(before - after)
assert after - before == {'CONFIG_USB_NET_CDC_NCM=m'}, sorted(after - before)
print('Actual kernel configuration differs from the installed four-driver build only by enabling NCM as a module.')
PY
modules=(drivers/net/mii.ko drivers/net/usb/usbnet.ko drivers/net/usb/cdc_ether.ko drivers/net/usb/rndis_host.ko drivers/net/usb/cdc_ncm.ko)
for module in "${modules[@]}"; do
  readelf -p .modinfo "$kernel/$module" | grep -q 'vermagic=6.18.54 SMP mod_unload aarch64$'
done
(cd "$kernel" && sha256sum "${modules[@]}") > "$audit/modules-before-packaging.SHA256SUMS"
make -j"${BUILD_JOBS:-2}" package/kernel/linux/compile LINUX_VERMAGIC="$expected" V=s 2>&1 | tee "$source_dir/../usb-ncm-package.log"
(cd "$kernel" && sha256sum -c "$audit/modules-before-packaging.SHA256SUMS")
mkdir -p "$artifacts/metadata" "$artifacts/module-audit"
names=(kmod-mii kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-usb-net-cdc-ncm)
for name in "${names[@]}"; do
  package="bin/targets/mediatek/filogic/packages/$name-6.18.54-r1.apk"
  staging_dir/host/bin/apk adbdump "$package" > "$artifacts/metadata/$name.txt"
  grep -qF "kernel=6.18.54~$expected-r1" "$artifacts/metadata/$name.txt"
  grep -q 'arch: aarch64_cortex-a53$' "$artifacts/metadata/$name.txt"
  cp "$package" "$artifacts/"
done
for module in "${modules[@]}"; do cp "$kernel/$module" "$artifacts/module-audit/"; done
cp "$audit/kernel-plan-check.json" "$audit/build.config" "$audit/kernel.config.actual" "$artifacts/metadata/"
python3 "$recipe/verify-packages.py" "$source_dir" "$artifacts"
python3 - "$recipe/reference/usb4-package-inspection.json" "$artifacts" <<'PY'
from pathlib import Path
import json, struct, sys
before = json.loads(Path(sys.argv[1]).read_text())
folder = Path(sys.argv[2])
after = json.loads((folder / 'PACKAGE-INSPECTION.json').read_text())
results = {}
for name, old in before['packages'].items():
    new = after['packages'][name]
    assert old['module_sha256'] == new['module_sha256'], (name, old['module_sha256'], new['module_sha256'])
    results[name] = {'module_sha256': new['module_sha256'], 'identical_to_installed_build': True}
data = (folder / 'module-audit/cdc_ncm.ko').read_bytes()
offset = struct.unpack_from('<Q', data, 40)[0]
entsize, count, stridx = struct.unpack_from('<HHH', data, 58)
sections = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i * entsize) for i in range(count)]
table = sections[stridx]
strings = data[table[4]:table[4] + table[5]]
for section in sections:
    label = strings[section[0]:].split(b'\0', 1)[0]
    if label == b'.gnu.linkonce.this_module':
        assert section[5] == 704 and section[8] == 64, section
        results['cdc_ncm.ko'] = {'module_structure_size': 704, 'module_structure_alignment': 64}
assert 'cdc_ncm.ko' in results
(folder / 'CORE-MODULE-CHECK.json').write_text(json.dumps(results, indent=2) + '\n')
print(json.dumps(results, indent=2))
PY
{
  printf 'OpenWrt source: 31ef8052449426249b8ea364444df9adab80bfef\n'
  printf 'Hardware patch: soapmancn/openwrt@6d99cc1ee93424cae10285f83f015fc8a7c31713 (context rebased)\n'
  printf 'NCM extension of PR #1 approach; new driver is NOT covered by the PR device test.\n'
  printf 'Build recipe: %s\n' "${GITHUB_SHA:-local}"
  printf 'Build run: %s/%s/actions/runs/%s\n' "${GITHUB_SERVER_URL:-local}" "${GITHUB_REPOSITORY:-local}" "${GITHUB_RUN_ID:-local}"
  printf 'Core module payloads must exactly match the four already installed APKs.\n'
  printf 'Physical testing of cdc_ncm remains required.\n'
} > "$artifacts/BUILD-INFO.txt"
(cd "$artifacts" && sha256sum ./*.apk BUILD-INFO.txt > SHA256SUMS && sha256sum -c SHA256SUMS)
