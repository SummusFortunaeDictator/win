#!/bin/bash
set -e

GREEN="\033[1;32m"
RED="\033[1;31m"
NC="\033[0m"

echo -e "${GREEN}=== BBRPlus DKMS 自动安装脚本 ===${NC}"

read -p "是否继续安装 BBRPlus DKMS 模块？[Y/N]: " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
  echo -e "${RED}操作已取消${NC}"
  exit 1
fi

echo -e "${GREEN}[1/7] 安装依赖 dkms、build-essential、linux-headers 等...${NC}"
sudo apt update
sudo apt install -y dkms build-essential linux-headers-$(uname -r) wget unzip

echo -e "${GREEN}[2/7] 检查并删除旧的 BBRPlus 模块（如果存在）...${NC}"
if dkms status | grep -q "tcp_bbrplus"; then
  sudo dkms remove tcp_bbrplus/0.1 --all || true
  sudo rm -rf /usr/src/tcp_bbrplus-0.1
  echo -e "${GREEN}旧模块已删除${NC}"
else
  echo -e "${GREEN}无旧模块，跳过删除${NC}"
fi

echo -e "${GREEN}[3/7] 下载源码 ZIP...${NC}"
TMPDIR=$(mktemp -d)
wget -qO "$TMPDIR/tcp_bbrplus.zip" https://github.com/KozakaiAya/TCP_BBR/archive/refs/heads/master.zip

echo -e "${GREEN}[4/7] 解压源码到 /usr/src/tcp_bbrplus-0.1 ...${NC}"
sudo rm -rf /usr/src/tcp_bbrplus-0.1
sudo unzip -q "$TMPDIR/tcp_bbrplus.zip" -d /usr/src/
sudo mv /usr/src/TCP_BBR-master /usr/src/tcp_bbrplus-0.1
rm -rf "$TMPDIR"

echo -e "${GREEN}[5/7] 生成 dkms.conf 文件...${NC}"
sudo tee /usr/src/tcp_bbrplus-0.1/dkms.conf > /dev/null << EOF
PACKAGE_NAME="tcp_bbrplus"
PACKAGE_VERSION="0.1"
MAKE[0]="make -C ./code tcp_bbrplus.ko"
BUILT_MODULE_NAME[0]="tcp_bbrplus"
DEST_MODULE_LOCATION[0]="/kernel/net/ipv4/"
AUTOINSTALL="yes"
EOF

echo -e "${GREEN}[6/7] 添加、构建、安装 DKMS 模块...${NC}"
sudo dkms add -m tcp_bbrplus -v 0.1
sudo dkms build -m tcp_bbrplus -v 0.1
sudo dkms install -m tcp_bbrplus -v 0.1

echo -e "${GREEN}[7/7] 加载模块并配置系统参数...${NC}"
sudo modprobe tcp_bbrplus

# 写入 sysctl 配置，避免重复写入
if ! grep -q "tcp_bbrplus" /etc/sysctl.conf; then
  echo -e "\n# BBRPlus 配置" | sudo tee -a /etc/sysctl.conf
  echo "net.core.default_qdisc = fq" | sudo tee -a /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control = tcp_bbrplus" | sudo tee -a /etc/sysctl.conf
fi

sudo sysctl -p

echo -e "${GREEN}\n✅ BBRPlus 安装并启用成功！当前拥塞控制算法为：$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')${NC}"
