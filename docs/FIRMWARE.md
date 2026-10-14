# TR3600 V1 社区固件候选版

固件沿用 `31ef8052449426249b8ea364444df9adab80bfef` 的 OpenWrt / Linux 6.18.54 基线及本项目 TR3600 V1 硬件补丁，并固定 packages、LuCI 和 OpenClash 的提交，见 [sources.json](../firmware/sources.json)。

内置中文 LuCI HTTPS 管理、五个 USB 网络驱动、USB 诊断工具、OpenClash 0.48.002 界面及依赖、dnsmasq-full、TUN 与 nftables TProxy 支持。OpenClash 沿用其 MIT 许可，版权说明写入镜像。代理内核、订阅、节点和个人配置不内置，OpenClash 默认未启用；首次使用需要下载匹配的代理内核并导入自己的配置。

新固件的 kernel 和驱动在同次构建中生成，使用其自身正常的 kernel 依赖。Crostia v1.9 补装包的特定元数据适配不用于完整固件。

## 构建

Actions 手动运行 **Build TR3600 V1 community firmware with USB and OpenClash**。默认从源码构建固定 GCC 14.4.0 工具链，避免依赖滚动 snapshots 的预编译工具链 URL。

Linux 本地构建先按 [BUILD.md](BUILD.md) 安装依赖，然后：

```sh
export BUILD_JOBS=4 USE_EXTERNAL_TOOLCHAIN=0
for phase in prepare configure download tools firmware collect source; do
  bash firmware/build.sh "$phase" || break
done
```

构建输出 `full-artifacts/` 包含 sysupgrade 镜像、五个同构建 APK、完整包归档、配置、实际 rootfs 检查记录、对应源码和 SHA256 校验值。对应源码归档包含固定 OpenWrt/feed/OpenClash 源码、构建配方和补丁、实际配置及下载的软件组件源码，不包含私有签名密钥。

## 默认网络与使用范围

- 首次使用全新配置时，沿用 OpenWrt 默认 LAN 设置；通常是 `192.168.1.1`。保留配置升级时地址以原配置为准。
- 全新配置增加 `usbwan`：DHCP 客户端、设备 `eth2`、跃点 10、加入已有 wan 防火墙区域。本次 F50 Pro 实测使用 eth2；其他 USB 设备的网卡名不同时需要手动调整。
- 已存在的 usbwan 配置保持原设置。Wi-Fi 设置沿用 OpenWrt 默认或用户保留的配置，不预置共享密码或个人 SSID。
- 接入 F50 前检查上游网段与 LAN 不重叠。启用 OpenClash 后需要重新验证直连、代理、DNS 和 IPv6 出口。

## 候选版与实测

镜像检查包括正确的设备标识、清单内必须存在的包、各 APK 与 kernel 依赖一致、从实际 sysupgrade rootfs 中读取的模块与 APK payload 完全一致、NCM 自动加载文件存在、OpenClash 默认关闭。

这些构建检查不能代替刷机测试。本项目驱动补装方案已在现有固件上实测；新完整固件必须另外验证启动、两路 Wi-Fi、LAN/WAN、USB 上网、重启恢复及 OpenClash。未进行完整固件刷写验证时，构建产物保持“候选版”标识。

首次刷写候选版前备份原配置和原固件，确认 TR3600 V1 的恢复方式。这里不提供自动刷写脚本；构建不会访问或修改路由器。
