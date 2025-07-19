#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/bbrplus_install.log"
exec 2>>"$LOGFILE"

GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"

function log() {
  echo -e "$1" | tee -a "$LOGFILE"
}

log "${CYAN}======== BBRPlus DKMS 自动安装脚本 ========${NC}"
log "${GREEN}当前系统内核：$(uname -r)${NC}"

read -p "是否继续安装 BBRPlus DKMS 模块？[Y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  log "${YELLOW}安装已取消${NC}"
  exit 1
fi

log "${GREEN}[1/8] 安装依赖包...${NC}"
sudo apt update -y
sudo apt install -y dkms build-essential linux-headers-$(uname -r) wget unzip || {
  log "${RED}错误：依赖安装失败，请检查网络或apt源${NC}"
  exit 1
}

log "${GREEN}[2/8] 清理旧模块（若存在）...${NC}"
if dkms status | grep -q "tcp_bbrplus, 0.1"; then
  sudo dkms remove tcp_bbrplus/0.1 --all && log "${GREEN}旧模块已卸载${NC}"
  sudo rm -rf /usr/src/tcp_bbrplus-0.1
else
  log "${GREEN}未检测到旧模块，跳过${NC}"
fi

log "${GREEN}[3/8] 下载源码（最多重试3次）...${NC}"
TMPDIR=$(mktemp -d)
ZIPURL="https://github.com/KozakaiAya/TCP_BBR/archive/refs/heads/master.zip"
for i in {1..3}; do
  if wget -qO "$TMPDIR/tcp_bbrplus.zip" "$ZIPURL"; then
    log "${GREEN}源码下载成功（第${i}次）${NC}"
    break
  else
    log "${YELLOW}下载失败，第${i}次重试...${NC}"
    sleep 2
  fi
  [[ $i -eq 3 ]] && {
    log "${RED}错误：源码下载失败，请检查网络或URL${NC}"
    exit 1
  }
done

log "${GREEN}[4/8] 解压源码并准备 DKMS 目录...${NC}"
sudo rm -rf /usr/src/tcp_bbrplus-0.1
sudo unzip -q "$TMPDIR/tcp_bbrplus.zip" -d /usr/src/
sudo mv /usr/src/TCP_BBR-master /usr/src/tcp_bbrplus-0.1
rm -rf "$TMPDIR"

log "${GREEN}[5/8] 生成 dkms.conf...${NC}"
sudo tee /usr/src/tcp_bbrplus-0.1/dkms.conf > /dev/null << 'EOF'
PACKAGE_NAME="tcp_bbrplus"
PACKAGE_VERSION="0.1"
MAKE[0]="make -C ./code tcp_bbrplus.ko"
BUILT_MODULE_NAME[0]="tcp_bbrplus"
DEST_MODULE_LOCATION[0]="/kernel/net/ipv4/"
AUTOINSTALL="yes"
EOF

log "${GREEN}[6/8] 添加并构建 DKMS 模块...${NC}"
sudo dkms add -m tcp_bbrplus -v 0.1
sudo dkms build -m tcp_bbrplus -v 0.1 || {
  log "${RED}错误：模块构建失败，查看 $LOGFILE/make.log 获取详情${NC}"
  exit 1
}
sudo dkms install -m tcp_bbrplus -v 0.1

log "${GREEN}[7/8] 加载模块并设置 sysctl...${NC}"
if lsmod | grep -q tcp_bbrplus; then
  log "${YELLOW}模块已加载，跳过 modprobe${NC}"
else
  sudo modprobe tcp_bbrplus
fi

# 去重追加 sysctl
if ! grep -q "net.ipv4.tcp_congestion_control.*bbrplus" /etc/sysctl.conf; then
  sudo tee -a /etc/sysctl.conf > /dev/null << EOF

# BBRPlus 加速配置
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = tcp_bbrplus
EOF
fi
sudo sysctl -p

log "${GREEN}[8/8] 安装完成！${NC}"
log "${GREEN}当前拥塞控制算法：$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')${NC}"
log "${YELLOW}建议重启系统后，确保模块完全生效：sudo reboot${NC}"

exit 0
