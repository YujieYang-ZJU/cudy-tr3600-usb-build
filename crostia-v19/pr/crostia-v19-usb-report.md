# Crostia v1.9：USB 网络驱动补充及实机结果

## 适用范围

- Cudy TR3600 v1，Crostia v1.9。
- mediatek/filogic，aarch64_cortex-a53。
- 已安装内核包：`6.18.54~65a6123c8ad58cc9838d7f2e4fb4e60a-r1`。
- 编译基础提交：`31ef8052449426249b8ea364444df9adab80bfef`。
- TR3600 支持补丁：soapmancn/openwrt 的 `6d99cc1ee93424cae10285f83f015fc8a7c31713`。

这是针对一个已验证构建和固件的补充，不能仅凭内核版本号把驱动安装到其他构建。

## 编译与配置观察

新增选择：

```text
CONFIG_PACKAGE_kmod-mii=m
CONFIG_PACKAGE_kmod-usb-net=m
CONFIG_PACKAGE_kmod-usb-net-cdc-ether=m
CONFIG_PACKAGE_kmod-usb-net-rndis=m
```

生成的四个 APK 原始内核依赖哈希为 `d276c938a20ad6318401925aa33b82de`。
按本地 `include/kernel-defaults.mk` 的规则，对 `.config.set` 中启用项排序后计算 MD5：

```bash
grep '=[ym]' "$k/.config.set" |
  grep -vE '^CONFIG_(USB_USBNET|USB_NET_CDCETHER|USB_NET_RNDIS_HOST)=' |
  LC_ALL=C sort | md5sum
```

结果是固件的 `65a6123c8ad58cc9838d7f2e4fb4e60a`。

需要注意：`.config.target` 和 `.config.set` 中 `CONFIG_MII=y`，但实际内核 `.config` 中 `CONFIG_MII=m`，并生成 `drivers/net/mii.ko`。不能仅依据 `.config.set` 判断 MII 已内置。

## 已完成的实机验证

由用户在其路由器上执行并提供输出：

- 按 `mii`、`usbnet`、`cdc_ether`、`rndis_host` 顺序加载模块成功。
- 三个 USB 模块和路由器已有模块的 ELF vermagic 均为 `6.18.54 SMP mod_unload aarch64`。
- 中兴设备启用 USB 网络共享后，日志显示 `ZTE CDC Ethernet Device`，通过 **cdc_ether** 创建 `usb0`。
- `usbwan` 配置为 DHCP、设备 `usb0`，加入 WAN 防火墙区域。
- `ifstatus usbwan` 显示 `up: true`，获取 IPv4 地址、网关及 DNS。
- `ping -I usb0 -c 3 1.1.1.1`：3 发 3 收，0% 丢包。

上述设备实测是 CDC Ethernet。RNDIS 驱动已加载，但尚没有 RNDIS 设备连接测试。尚未验证电脑客户端转发、重启后的自动加载或 APK 安装。

## 建议作者补充

1. 在后续固件中加入四个内核模块，或提供与相应 Release 一起构建的 APK。
2. 归档 Release 对应的 kmods、构建配置、补丁及工具链信息，避免 rolling snapshots 无法安装旧内核模块。
3. 文档列出 CDC Ethernet 和 RNDIS 两种 USB 共享模式，避免仅安装 RNDIS 单包而遗漏依赖。

## 当前 v1.9 APK 打包提案

`repack-crostia-v19-usb.sh` 使用既有构建树，先检查基础提交、目标设备、配置哈希和模块 vermagic，再备份原四个 APK，使用命令行 `LINUX_VERMAGIC=65a6123c8ad58cc9838d7f2e4fb4e60a` 重新生成包的依赖元数据。只收集四个 USB 相关 APK，不分发生成的 kernel 包或其他内核模块。

这个步骤是对已实机加载模块的特定构建进行依赖适配，并非通用的兼容性判定或强制安装方法。APK 安装和重启验证通过以前，包不应标注为已验证发行物。

运行：

```bash
bash repack-crostia-v19-usb.sh ~/build/openwrt-v19
```

完成后输出独立目录，包含四个 APK、原始 APK 备份、metadata、打包日志和 SHA256SUMS。安装时校验路由器内核完整依赖版本；本地签名如未被路由器信任，可对这些自行构建的包使用 `--allow-untrusted`，但不能绕过依赖检查。

升级固件或内核后需要重新匹配，不能直接沿用本次驱动。
