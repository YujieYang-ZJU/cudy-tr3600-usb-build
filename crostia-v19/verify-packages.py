#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Inspect APK payloads without installing packages or running their scripts."""
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
artifacts = Path(sys.argv[2]).resolve()
apk = root / 'staging_dir/host/bin/apk'
names = {'kmod-mii': 'mii.ko', 'kmod-usb-net': 'usbnet.ko',
         'kmod-usb-net-cdc-ether': 'cdc_ether.ko', 'kmod-usb-net-rndis': 'rndis_host.ko'}
if os.environ.get('USB_NCM') == '1':
    names['kmod-usb-net-cdc-ncm'] = 'cdc_ncm.ko'
report = {'kernel_dependency': '6.18.54~65a6123c8ad58cc9838d7f2e4fb4e60a-r1',
          'physical_device_tested': False, 'original_pr_tested_binaries': False, 'packages': {}}
for name, module in names.items():
    package = artifacts / (name + '-6.18.54-r1.apk')
    with tempfile.TemporaryDirectory(prefix='usb-apk-inspect-') as dest:
        subprocess.run([str(apk), 'extract', '--allow-untrusted', '--no-chown',
                        '--destination', dest, str(package)], check=True)
        folder = Path(dest)
        payload = folder / 'lib/modules/6.18.54' / module
        modules = list(folder.rglob('*.ko'))
        assert modules == [payload], (name, modules)
        data = payload.read_bytes()
        assert data[:6] == b'\x7fELF\x02\x01', (name, 'ELF64 LE required')
        assert struct.unpack_from('<H', data, 18)[0] == 183, (name, 'AArch64 required')
        info = {k.decode(): v.decode() for k, v in
                re.findall(rb'(?:^|\x00)(vermagic|depends)=([^\x00]*)', data)}
        assert info.get('vermagic') == '6.18.54 SMP mod_unload aarch64', (name, info)
        autoload = {str(p.relative_to(folder)): p.read_text()
                    for p in folder.glob('etc/modules*.d/*') if p.is_file()}
        report['packages'][name] = {'filename': package.name, 'bytes': package.stat().st_size,
            'sha256': hashlib.sha256(package.read_bytes()).hexdigest(),
            'module_sha256': hashlib.sha256(data).hexdigest(), 'module': module,
            'architecture': 'AArch64', **info, 'autoload': autoload}
(artifacts / 'PACKAGE-INSPECTION.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
