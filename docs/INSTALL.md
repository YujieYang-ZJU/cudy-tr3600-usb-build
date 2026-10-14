# 安装五个 USB 网络驱动

适用范围见 [README](../README.md)。这是给现有 Crostia v1.9 固件补装驱动的方案，不需要刷机。

## 1. 核对路由器内核

在路由器终端执行：

```sh
uname -r
apk list --installed kernel
```

必须分别为 `6.18.54` 和 `kernel-6.18.54~65a6123c8ad58cc9838d7f2e4fb4e60a-r1`。不匹配时停止，不能忽略依赖或强制安装。

## 2. 上传、校验和安装

从 [Release](https://github.com/YujieYang-ZJU/cudy-tr3600-usb-build/releases/tag/crostia-v1.9-usb-20261014) 下载 `TR3600-v1-Crostia-v1.9-USB-all-drivers.zip`，解压并上传整个目录到路由器 `/tmp/`。保持现有无线联网可用。

下面以管理地址 `192.168.10.1` 为例，在电脑上执行；地址按你的实际设置修改：

```sh
scp -O -r ./TR3600-v1-Crostia-v1.9-USB-all-drivers root@192.168.10.1:/tmp/
ssh root@192.168.10.1
```

在路由器执行：

```sh
cd /tmp/TR3600-v1-Crostia-v1.9-USB-all-drivers
sha256sum -c SHA256SUMS
apk add --simulate --no-network --allow-untrusted ./*.apk
```

全部文件为 `OK`、模拟安装无依赖冲突后再安装：

```sh
apk add --no-network --allow-untrusted ./*.apk
modprobe cdc_ncm
ip link show
dmesg | tail -n 60
```

`--allow-untrusted` 用于本地构建包的签名尚未加入路由器信任库，并不跳过 kernel 依赖检查。`--no-network` 下缺少软件源索引缓存的 WARNING 与依赖冲突不同；最后应显示安装成功。

已经安装本项目原四个包的用户，只需校验并安装 Release 中的 `kmod-usb-net-cdc-ncm-6.18.54-r1.apk`。

## 3. 新建 USB 上网接口

插入已开启 USB 网络共享的 F50 Pro，日志应出现 `cdc_ncm ... eth2: register`。网卡名可能不同，以输出为准。

LuCI → 网络 → 接口 → 添加新接口：

| 设置 | 值 |
|---|---|
| 名称 | usbwan |
| 协议 | DHCP 客户端 |
| 设备 | 实际 USB 网卡，本次为 eth2 |
| 防火墙区域 | 已有 wan 区域 |
| 高级设置：路由跃点 | 50 |

保持使用默认网关和对端 DNS，保存并应用。USB 获得的网段不能与 Cudy 的 LAN 网段重叠；F50 USB 与无线同用一个上游网段时，还需核对两个接口的 IP 不重复、路由跃点不同。

```sh
ifstatus usbwan
ip -4 route
ping -I eth2 -c 20 192.168.0.1
ping -I eth2 -c 20 223.5.5.5
ip -6 route
```

网卡名和网关按实际输出修改。先验证 USB 网关及公网，不能仅根据路由器普通 ping 判断是否走 USB。

## 4. USB 成为首选后，再关闭无线客户端

若原无线接口名称为 `wwan`，USB 和无线测试通过后可以：

```sh
uci set network.usbwan.metric='10'
uci set network.wwan.metric='100'
uci commit network
ubus call network reload
```

无线接口名称不同则相应修改。等待接口恢复后检查：

```sh
ip -4 route get 223.5.5.5
ip -4 route
ip -6 route
```

IPv4 首选应为 USB 网卡；IPv6 若有公网默认路由也须核对出口。电脑、手机连接 Cudy 的 Wi-Fi/LAN 测试新网页，手机测试时关闭移动数据。

终端上网正常后，网络 → 无线，只停用连接 F50 的 **Client/STA 条目**；保留 Cudy 自己的 **Master/AP 条目**。保存并应用，再检查路由、路由器公网访问与终端网页。

最后重启 Cudy，确认 USB 网卡、DHCP、默认路由和终端上网自动恢复。保留无线客户端配置便于恢复，不必删除。后续启用 OpenClash、策略路由或多线路功能时，需要重新检查相应出口。
