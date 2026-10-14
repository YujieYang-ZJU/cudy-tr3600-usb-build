#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tarfile
import tempfile

root,folder,audit=map(lambda value:Path(value).resolve(),sys.argv[1:])
image=folder/'openwrt-mediatek-filogic-cudy_tr3600-v1-squashfs-sysupgrade.bin'
filesystem=audit/'rootfs.squashfs'
with tarfile.open(image) as t:
    members=[m for m in t if m.name.endswith('/root') and m.isfile()]
    assert len(members)==1
    filesystem.write_bytes(t.extractfile(members[0]).read())
unsquash=root/'staging_dir/host/bin/unsquashfs4'
apk=root/'staging_dir/host/bin/apk'
def read(path):
    return subprocess.check_output([str(unsquash),'-cat',str(filesystem),path])
modules={'kmod-mii':'mii.ko','kmod-usb-net':'usbnet.ko','kmod-usb-net-cdc-ether':'cdc_ether.ko','kmod-usb-net-rndis':'rndis_host.ko','kmod-usb-net-cdc-ncm':'cdc_ncm.ko'}
report={}
vermagics=set()
for name,module in modules.items():
    path='lib/modules/6.18.54/'+module
    data=read(path)
    assert data[:6]==b'\x7fELF\x02\x01' and struct.unpack_from('<H',data,18)[0]==183
    vermagic=re.search(rb'(?:^|\x00)vermagic=([^\x00]*)',data).group(1).decode()
    assert vermagic.startswith('6.18.54 ') and vermagic.endswith(' aarch64')
    vermagics.add(vermagic)
    with tempfile.TemporaryDirectory(prefix='full-apk-check-') as dest:
        subprocess.run([str(apk),'extract','--allow-untrusted','--no-chown','--destination',dest,str(folder/(name+'-6.18.54-r1.apk'))],check=True)
        assert (Path(dest)/path).read_bytes()==data
    report[name]={'module':module,'sha256':hashlib.sha256(data).hexdigest(),'firmware_and_apk_payload_identical':True}
assert len(vermagics)==1
assert b'cdc_ncm' in read('etc/modules.d/usb-net-cdc-ncm')
assert b"network.usbwan.device='eth2'" in read('etc/uci-defaults/99-tr3600-usbwan')
assert re.search(rb"option\s+enable\s+['\"]?0['\"]?",read('etc/config/openclash'))
assert b'MIT License' in read('usr/share/licenses/luci-app-openclash/LICENSE')
(folder/'ROOTFS-VERIFICATION.json').write_text(json.dumps({'modules':report,'shared_vermagic':vermagics.pop(),'ncm_autoload_present':True,'openclash_disabled_by_default':True,'physical_firmware_flash_tested':False},indent=2)+'\n')
print('Actual sysupgrade rootfs, APK module payloads, NCM autoload and disabled OpenClash default verified.')
