#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Mirror Kernel/Configure/Default for a fast pre-compilation hash check."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
audit = Path(sys.argv[2]).resolve()
audit.mkdir(parents=True, exist_ok=True)
config = (root / '.config').read_text()

def run(*args):
    return subprocess.check_output(args, cwd=root, text=True)

files = []
for folder in ['generic', 'mediatek', 'mediatek/filogic']:
    options = [root / 'target/linux' / folder / name for name in ['config-6.18', 'config-default']]
    files += [str(next(p for p in options if p.is_file()))] if any(p.is_file() for p in options) else []
base = run('perl', 'scripts/kconfig.pl', *(['+'] * (len(files) - 1)), *files)
for line in config.splitlines():
    if re.match(r'^(#\s+)?CONFIG_KERNEL', line):
        base += line.replace('CONFIG_KERNEL_', 'CONFIG_', 1) + '\n'
base += '# CONFIG_KALLSYMS_EXTRA_PASS is not set\n# CONFIG_KALLSYMS_ALL is not set\nCONFIG_KALLSYMS_UNCOMPRESSED=y\n'
(audit / 'kernel.target').write_text(base)
override = run('perl', 'scripts/package-metadata.pl', 'kconfig', 'tmp/.packageinfo', '.config', '6.18')
(audit / 'kernel.override').write_text(override)
merged = run('perl', 'scripts/kconfig.pl', 'm+', '+', str(audit / 'kernel.target'), '/dev/null', str(audit / 'kernel.override'))
merged = ''.join(line + '\n' for line in merged.splitlines() if 'INITRAMFS' not in line)
merged += 'CONFIG_INITRAMFS_SOURCE=""\n# CONFIG_INITRAMFS_FORCE is not set\n# CONFIG_INITRAMFS_PRESERVE_MTIME is not set\n'
if 'CONFIG_TARGET_ROOTFS_INITRAMFS_SEPARATE=y\n' in config:
    merged += 'CONFIG_BLK_DEV_INITRD=y\n'
    for algo in ['GZIP', 'BZIP2', 'LZMA', 'LZO', 'XZ', 'LZ4', 'ZSTD']:
        enabled = f'CONFIG_TARGET_INITRAMFS_COMPRESSION_{algo}=y\n' in config
        merged += f'CONFIG_RD_{algo}=y\n' if enabled else f'# CONFIG_RD_{algo} is not set\n'
(audit / 'kernel.config.set.plan').write_text(merged)
enabled = [line for line in merged.splitlines() if re.search('=[ym]', line)]
added = {'CONFIG_USB_USBNET=m', 'CONFIG_USB_NET_CDCETHER=m', 'CONFIG_USB_NET_RNDIS_HOST=m'}
with_ncm = os.environ.get('USB_NCM') == '1'
if with_ncm:
    added.add('CONFIG_USB_NET_CDC_NCM=m')
assert added.issubset(enabled), 'USB driver options differ from the PR'
baseline = [line for line in enabled if line not in added]

def digest(lines):
    return hashlib.md5(('\n'.join(sorted(lines)) + '\n').encode()).hexdigest()

report = {'expected_baseline': '65a6123c8ad58cc9838d7f2e4fb4e60a',
          'baseline': digest(baseline), 'with_usb': digest(enabled),
          'expected_with_usb': ('4c829362dbf0dcf539a4282b820a6327' if with_ncm
                                else 'd276c938a20ad6318401925aa33b82de'),
          'with_ncm': with_ncm, 'added_options': sorted(added)}
(audit / 'kernel-plan-check.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
assert report['baseline'] == report['expected_baseline'], 'Original kernel configuration not reproduced'
assert report['with_usb'] == report['expected_with_usb'], 'USB configuration differs from the tested PR'
