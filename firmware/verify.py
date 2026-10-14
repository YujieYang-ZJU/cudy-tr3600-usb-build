#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import json
from pathlib import Path
import re
import sys

folder=Path(sys.argv[1])
image=folder/'openwrt-mediatek-filogic-cudy_tr3600-v1-squashfs-sysupgrade.bin'
assert image.is_file() and 5_000_000 < image.stat().st_size < 240_000_000
metadata=json.loads((folder/'image-metadata.json').read_text())
assert 'cudy,tr3600-v1' in metadata['supported_devices']
assert metadata['version']['target']=='mediatek/filogic'
packages=dict(line.split(' - ',1) for line in (folder/'openwrt-mediatek-filogic-cudy_tr3600-v1.manifest').read_text().splitlines() if ' - ' in line)
required={'kernel','kmod-usb-core','kmod-usb-net','kmod-usb-net-cdc-ether','kmod-usb-net-rndis','kmod-usb-net-cdc-ncm','kmod-mii','luci-ssl','luci-compat','luci-app-openclash','luci-i18n-base-zh-cn','dnsmasq-full','firewall4','netifd','wpad-basic-mbedtls','usbutils','usb-modeswitch','kmod-tun','kmod-nft-tproxy','ruby-yaml'}
assert not required-packages.keys(),sorted(required-packages.keys())
kernel=packages['kernel']
assert re.fullmatch(r'6\.18\.54~[a-f0-9]{32}-r\d+',kernel),kernel
assert packages['luci-app-openclash'].startswith('0.48.002')
for name in ['kmod-mii','kmod-usb-net','kmod-usb-net-cdc-ether','kmod-usb-net-rndis','kmod-usb-net-cdc-ncm']:
    text=(folder/(name+'.metadata.txt')).read_text()
    assert 'kernel='+kernel in text,(name,kernel)
    assert 'arch: aarch64_cortex-a53' in text
report={'device':'cudy,tr3600-v1','target':'mediatek/filogic','kernel':kernel,'required_packages_present':sorted(required),'normal_kernel_dependencies_verified':True,'physical_firmware_flash_tested':False,'openclash_core_included':False}
(folder/'VERIFICATION.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
