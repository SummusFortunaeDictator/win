#!/bin/bash
# 安装 BBRPlus DKMS 模块（适配 Ubuntu 24.04+6.x）
set -e

echo "======== 开始安装 BBRPlus DKMS 模块（KozakaiAya/TCP_BBR） ========"

read -p "是否继续安装？[Y/N]: " confirm
if [[ $confirm != "Y" && $confirm != "y" ]]; then
  echo "操作取消"
  exit 1
fi

# 安装依赖
echo "[1/6] 安装 dkms、构建工具、headers、wget、unzip..."
sudo apt update
sudo apt install -y dkms build-essential linux-headers-$(uname -r) wget unzip

# 清理旧模块
if dkms status | grep -q "tcp_bbr, bbrplus"; then
  echo "[2/6] 卸载旧的 bbrplus 模块..."
  sudo dkms remove -m tcp_bbr -v bbrplus --all
else
  echo "[2/6] 无旧模块，跳过"
fi

# 下载源码 ZIP
echo "[3/6] 下载 KozakaiAya/TCP_BBR ZIP..."
TMP=$(mktemp -d)
wget -qO "$TMP/tcp_bbr.zip" \
  https://github.com/KozakaiAya/TCP_BBR/archive/refs/heads/master.zip

echo "[4/6] 解压源码到 /usr/src/tcp_bbr-bbrplus..."
sudo rm -rf /usr/src/tcp_bbr-bbrplus
sudo unzip -q "$TMP/tcp_bbr.zip" -d /usr/src/
sudo mv /usr/src/TCP_BBR-master /usr/src/tcp_bbr-bbrplus
rm -rf "$TMP"

# 添加 DKMS, 编译安装
echo "[5/6] 添加到 DKMS..."
cat << 'EOF' | sudo tee /usr/src/tcp_bbr-bbrplus/dkms.conf
PACKAGE_NAME="tcp_bbr"
PACKAGE_VERSION="bbrplus"
MAKE[0]="make -C ./code tcp_bbrplus.ko"
BUILT_MODULE_NAME[0]="tcp_bbrplus"
DEST_MODULE_LOCATION[0]="/kernel/net/ipv4/"
AUTOINSTALL="yes"
EOF

sudo dkms add -m tcp_bbr -v bbrplus
sudo dkms build -m tcp_bbr -v bbrplus
sudo dkms install -m tcp_bbr -v bbrplus

# 加载模块 & sysctl
echo "[6/6] 加载 tcp_bbrplus 并配置 sysctl..."
sudo modprobe tcp_bbrplus
sudo tee -a /etc/sysctl.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbrplus
EOF
sudo sysctl -p

echo -e "\n✅ 安装完成！当前拥塞控制算法：\033[1;32m$(sysctl net.ipv4.tcp_congestion_control)\033[0m"
