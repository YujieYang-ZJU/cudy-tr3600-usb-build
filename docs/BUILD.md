# 构建与源码

## 固定版本

- OpenWrt：`31ef8052449426249b8ea364444df9adab80bfef`
- TR3600 V1 硬件补丁：`soapmancn/openwrt@6d99cc1ee93424cae10285f83f015fc8a7c31713`，补丁仅重定位上下文。
- 四驱动 PR 配方：`a7158db3f89c751dbc028082c1dd613df7b925b6`。
- Linux：`6.18.54`，上游 tar.xz SHA256 为 `9df30b02dd8102bbd0be52556288ef6889ddbe7f1ddb96fbf847d0becf3eacac`。
- GCC：OpenWrt GCC 14.4.0 / musl / Linux x86_64 外部工具链，原归档 SHA256 为 `03071eac19d1f3906e79dc66d0f41c492aa40a005e3d3e2a8b5e33ca7b2a54c4`。

## 在 Linux 构建

使用 Ubuntu 24.04 的 GitHub Actions 配方，或自行安装相同构建依赖。构建不需要 root，只有系统依赖安装需要 sudo。

```sh
sudo apt-get update
sudo apt-get install -y build-essential clang flex bison g++ gawk gettext git \
  libncurses-dev libssl-dev python3 python3-setuptools rsync unzip zlib1g-dev \
  file wget curl libelf-dev swig xsltproc zstd time
git clone https://github.com/YujieYang-ZJU/cudy-tr3600-usb-build.git
cd cudy-tr3600-usb-build
export USB_NCM=1 BUILD_JOBS=4
for phase in prepare configure tools kernel package-ncm; do
  bash crostia-v19/build.sh "$phase" || break
done
```

也可以手动运行 Actions 的 **Build F50 Pro NCM driver for Crostia v1.9** 工作流。成功后收集 `usb-artifacts/`，保留 `usb-audit/`。

滚动 snapshots 的工具链 URL 可能失效；如果提前缓存了原归档，将完整文件放到仓库根目录即可复用，脚本仍会校验 SHA256。Release 的 `openwrt-source.bundle` 和 `linux-6.18.54.tar.xz` 也可放在根目录离线复用。不要用未经验证的其他编译器覆盖此兼容性发布，也不要关闭配置或模块一致性检查。工具链本身的后续归档/源码构建方式将在完整固件配方中单独固定。

## 对应源码资产

Release 同时提供：

- Linux 6.18.54 原始源码包，包含自身版权、许可和接口定义。
- 固定提交的 OpenWrt Git bundle 源码归档，含 Linux/OpenWrt 补丁和内核构建脚本，可用 `git clone openwrt-source.bundle openwrt-source` 查看。
- 本项目源代码、硬件补丁、两次构建的配置及模块核对记录；源码中保留上游许可。

Linux 源码放入 OpenWrt 的 `dl/` 后可供构建脚本校验和使用。实际完整内核配置位于发布包的构建记录中；`crostia-v19/reference/kernel.config.usb4` 保存原四驱动构建配置。

五个 APK 包含两次构建的结果：四个基础 APK 来自已安装并验证的四驱动构建，NCM APK 来自随后 NCM 构建。NCM 构建的四个基础模块 payload 与前次逐字节相同；模块结构为 704 字节、64 字节对齐，vermagic 为 `6.18.54 SMP mod_unload aarch64`。这些检查不构成其他内核的通用兼容保证。

## 完整固件的区别

完整固件会在同一构建中生成 kernel 和 USB 驱动，发布其正常匹配的软件包、源码和校验值。补装旧固件时使用的 kernel 依赖元数据适配不会用于该固件的普通 kmod 打包。固件镜像检查通过与真机刷写验证分开记录。
