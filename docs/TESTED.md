# 实机验证记录

日期：2026-10-14。证据来自使用者提供的终端输出和操作确认；为保护隐私，不发布原始配置、认证信息、MAC、序列号或终端截图。

| 检查 | 结果 |
|---|---|
| 设备 | Cudy TR3600 V1 + 中兴 F50 Pro |
| 固件基线 | Crostia v1.9 / OpenWrt SNAPSHOT r0-31ef805 |
| kernel 完整版本 | 6.18.54~65a6123c8ad58cc9838d7f2e4fb4e60a-r1 |
| 四个基础 APK | SHA256 校验、离线模拟与正式安装成功 |
| 四个基础模块 | mii、usbnet、cdc_ether、rndis_host 加载成功 |
| NCM APK | 模拟安装成功，安装后 kmodloader 自动加载 |
| USB 识别 | 19d2:1354；CDC NCM 02/0d/00；cdc_ncm 绑定 eth2 |
| USB 链路速度 | 480 Mbit/s，未协商到 SuperSpeed |
| DHCP | 获取独立 IPv4 地址、上游网关和默认路由 |
| USB 到 F50 网关 | 17 发 17 收、0% 丢包，平均 1.931 ms |
| USB 到公网 223.5.5.5 | 20 发 20 收、0% 丢包，平均 25.133 ms |
| 默认路由 | USB metric 10、无线 metric 100；route get 显示 eth2 |
| 关闭无线客户端后 | 使用者确认终端正常上网 |
| 重启恢复 | 使用者明确确认重启后 USB 上网正常 |
| IPv6 公网 | 未验证；当时只有 ULA/link-local，无公网默认路由 |
| OpenClash | 本次验证时未启用 |

对照：USB 到 1.1.1.1 的一次短测为 14 发 11 收；无线到同一目标为 20 发 15 收。丢包并非仅发生在 USB 路径，不能单凭该目标认定 USB 故障。20 次轻载 ICMP 和一次重启确认不等于长期稳定性或大吞吐测试。

原 PR 实际测试的是 CDC Ethernet；本项目 F50 Pro 实际使用 NCM，不能把两次设备验证混为一谈。RNDIS 模块虽已加载，RNDIS 设备接入尚未测试。

原始构建产物中的 `physical_device_tested: false` 和 BUILD-INFO 是构建当时的状态，本项目保留其原文；后续实测结论以本文件为准。
