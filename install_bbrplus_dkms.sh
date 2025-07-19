#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/bbrplus_dkms_install.log"
exec > >(tee -a "$LOGFILE") 2>&1

GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
NC="\033[0m"

log(){ echo -e "$1"; }

log "${CYAN}======== 一键安装 BBRPlus DKMS 模块 ========${NC}"
log "当前系统内核：$(uname -r)"

# 1. 安装依赖
log "${GREEN}[1/6] 安装编译依赖...${NC}"
sudo apt update -y
sudo apt install -y dkms build-essential linux-headers-$(uname -r) wget unzip || { log "安装依赖失败"; exit 1; }

# 2. 清理旧模块
log "${GREEN}[2/6] 清理旧的 BBRPlus 模块...${NC}"
if dkms status | grep -q "tcp_bbrplus, 0.1"; then
  sudo dkms remove tcp_bbrplus/0.1 --all || true
  sudo rm -rf /usr/src/tcp_brrplus-0.1
  log "旧模块已移除"
else
  log "未检测到旧模块"
fi

# 3. 下载源码
log "${GREEN}[3/6] 下载源码 ZIP...${NC}"
TMPDIR=$(mktemp -d)
wget -qO "$TMPDIR/tcp_bbrplus.zip" https://github.com/KozakaiAya/TCP_BBR/archive/refs/heads/master.zip

# 4. 解压并准备目录
log "${GREEN}[4/6] 解压源码...${NC}"
sudo rm -rf /usr/src/tcp_bbrplus-0.1
sudo unzip -q "$TMPDIR/tcp_bbrplus.zip" -d /usr/src/
sudo mv /usr/src/TCP_BBR-master /usr/src/tcp_bbrplus-0.1
rm -rf "$TMPDIR"

# 5. 生成 dkms.conf
log "${GREEN}[5/6] 生成 dkms.conf...${NC}"
sudo tee /usr/src/tcp_bbrplus-0.1/dkms.conf > /dev/null << 'EOF'
PACKAGE_NAME="tcp_bbrplus"
PACKAGE_VERSION="0.1"
MAKE[0]="make -C ./code tcp_bbrplus.ko"
BUILT_MODULE_NAME[0]="tcp_bbrplus"
DEST_MODULE_LOCATION[0]="/kernel/net/ipv4/"
AUTOINSTALL="yes"
EOF

# 6. 编译 & 安装模块
log "${GREEN}[6/6] 添加、编译、安装模块...${NC}"
sudo dkms add -m tcp_bbrplus -v 0.1
sudo dkms build -m tcp_bbrplus -v 0.1
sudo dkms install -m tcp_bbrplus -v 0.1

# 加载模块 & 配置 sysctl
log "加载模块并配置 sysctl 参数"
sudo modprobe tcp_bbrplus || true
if ! grep -q "tcp_bbrplus" /etc/sysctl.conf; then
  sudo tee -a /etc/sysctl.conf > /dev/null << 'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=tcp_bbrplus
EOF
fi
sudo sysctl -p

log "${GREEN}BBRPlus DKMS 模块安装完成，当前拥塞控制：$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')${NC}"
