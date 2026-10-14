# Cudy TR3600 V1 USB 上网适配

让 Cudy TR3600 V1 使用中兴 F50 Pro 的 USB 网络共享。首个版本提供适配 **Crostia v1.9 特定内核构建**的五个 APK、构建脚本、源码与安装教程；后续准备内置 USB 驱动的社区固件。

本项目基于 OpenWrt、Crostia 的固件及社区设备补丁，保留上游作者和许可证。它是社区适配项目，与 Cudy、中兴或 OpenWrt 官方发布没有隶属关系。

## 下载与适用范围

[下载驱动和对应源码](https://github.com/YujieYang-ZJU/cudy-tr3600-usb-build/releases/tag/crostia-v1.9-usb-20261014) · [安装教程](docs/INSTALL.md) · [实测记录](docs/TESTED.md) · [构建说明](docs/BUILD.md)

| 项目 | 必须匹配 |
|---|---|
| 路由器 | Cudy TR3600 **V1** |
| 参考固件 | [Crostia v1.9](https://github.com/Crostia/openwrt-Cudy-TR3600-v1/releases/tag/v1.9) |
| 平台 | mediatek/filogic，aarch64_cortex-a53 |
| 内核 | `6.18.54` |
| 完整 kernel 包版本 | **`6.18.54~65a6123c8ad58cc9838d7f2e4fb4e60a-r1`** |

仅版本号 `6.18.54` 相同不足以判断兼容。安装前必须核对完整 kernel 包版本；其他固件需要重新构建和验证，不能强制安装本版本的 APK。

## 已验证的设备

2026-10-14，在一台 TR3600 V1 上完成 APK 安装、F50 Pro 的 CDC NCM 识别、DHCP 获取地址、USB 公网访问、关闭无线客户端后的终端上网；使用者确认重启后 USB 上网自动恢复。

该 F50 Pro 的 USB ID 为 `19d2:1354`，通信接口为 `02/0d/00`，实际使用 **`cdc_ncm`**。在此设备组合中生成的网卡名为 `eth2`，其他配置应以实际网卡名为准。

| APK | 内核模块 | 实测范围 |
|---|---|---|
| kmod-mii | mii | 加载成功 |
| kmod-usb-net | usbnet | 加载成功，NCM 基础依赖 |
| kmod-usb-net-cdc-ether | cdc_ether | 加载成功，NCM 依赖 |
| kmod-usb-net-rndis | rndis_host | 加载成功，未接入 RNDIS 设备实测 |
| kmod-usb-net-cdc-ncm | cdc_ncm | F50 Pro USB IPv4 上网成功 |

实际 USB 协商速度为 **480 Mbit/s**。本次没有验证 USB 3.x 协商、吞吐量上限、IPv6 公网接入或 OpenClash。未宣称所有手机、随身 Wi-Fi 或固件通用兼容。

## 实现方式

1. 固定 OpenWrt 源码到 `31ef8052449426249b8ea364444df9adab80bfef`，应用 TR3600 V1 硬件补丁。
2. 根据 Crostia v1.9 的构建信息恢复原有内核选项，再添加 USB 网络模块。
3. 使用固定 GCC 14.4.0 工具链；校验内核配置差异、架构、模块 vermagic 和模块结构。
4. 参考[上游 PR #1](https://github.com/Crostia/openwrt-Cudy-TR3600-v1/pull/1)的方法，仅针对这个已验证构建适配 APK 的 kernel 依赖元数据；NCM 扩展另外核对原四个模块内容完全相同。
5. 将新包安装到原固件，完成实机网络验证。

`LINUX_VERMAGIC` 元数据适配不是通用的 ABI 兼容方法。配置和模块检查通过后仍需实测；此处的发布范围仅限上表中的完整 kernel 版本。

## 完整固件

正在准备沿用上述源码基线、内置 USB 网络驱动、中文 LuCI 及 OpenClash 界面和依赖的[社区固件候选版](docs/FIRMWARE.md)。新固件及其 kmod 将同次构建、同期归档，使用自身正常的 kernel 依赖，不沿用旧固件的依赖元数据适配。

完整固件发布前需完成镜像检查和真机测试。历史的 `build-firmware.sh` 与 `config/` 是已停止推进的 25.12 实验配方，不能作为当前已实测驱动方案的安装入口。

## 来源与许可

- [OpenWrt](https://github.com/openwrt/openwrt) 与 Linux 内核：原许可证和作者信息保留。
- [Crostia/openwrt-Cudy-TR3600-v1](https://github.com/Crostia/openwrt-Cudy-TR3600-v1)：v1.9 固件与构建信息。
- [soapmancn/openwrt 设备补丁](https://github.com/soapmancn/openwrt/commit/6d99cc1ee93424cae10285f83f015fc8a7c31713)：TR3600 V1 硬件支持；本项目仅调整补丁上下文。
- [352508290-source 的 PR #1](https://github.com/Crostia/openwrt-Cudy-TR3600-v1/pull/1)：四个 USB 驱动的特定构建打包方法。
- 本项目新增构建脚本与文档：GPL-2.0-only，见 [LICENSE](LICENSE)；其他文件依各自原许可证，见 [NOTICE.txt](NOTICE.txt)。

二进制发布同时提供对应 Linux 源码、OpenWrt 构建源码、补丁、构建配置和安装/构建脚本。当前项目不包含使用者的密码、私钥、订阅、配置备份或设备唯一标识。
