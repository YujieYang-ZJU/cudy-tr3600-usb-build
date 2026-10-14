#!/usr/bin/env python3
"""Fail the build if the device metadata or required packages are incorrect."""
import json
import pathlib
import sys

artifact_dir = pathlib.Path(sys.argv[1])
image_name = "openwrt-mediatek-filogic-cudy_tr3600-v1-squashfs-sysupgrade.bin"
manifest_name = "openwrt-mediatek-filogic-cudy_tr3600-v1.manifest"
image = artifact_dir / image_name
if not image.is_file() or not 5_000_000 < image.stat().st_size < 100_000_000:
    raise SystemExit("Missing or implausibly sized firmware image")

metadata = json.loads((artifact_dir / "image-metadata.json").read_text())
supported = metadata.get("supported_devices", [])
if "cudy,tr3600-v1" not in supported:
    raise SystemExit(f"TR3600 V1 identity missing: {supported!r}")
if metadata.get("version", {}).get("target") != "mediatek/filogic":
    raise SystemExit("Unexpected firmware target")

packages = {}
for line in (artifact_dir / manifest_name).read_text().splitlines():
    if " - " in line:
        name, version = line.split(" - ", 1)
        packages[name] = version

required = {
    "kernel", "kmod-usb-core", "kmod-usb-net", "kmod-usb-net-cdc-ether",
    "kmod-usb-net-rndis", "kmod-usb-net-cdc-ncm", "usbutils", "usb-modeswitch",
    "luci-ssl", "firewall4", "dnsmasq", "netifd", "wpad-basic-mbedtls",
}
missing = required.difference(packages)
if missing:
    raise SystemExit(f"Required packages absent from the image: {sorted(missing)}")
if not packages["kernel"].startswith("6.12."):
    raise SystemExit(f"Unexpected kernel for the pinned stable source: {packages['kernel']}")

print("Device metadata verified: Cudy TR3600 V1, mediatek/filogic")
print(f"Kernel: {packages['kernel']}")
print("USB network drivers and router/Wi-Fi management packages verified")
