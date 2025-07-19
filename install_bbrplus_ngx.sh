#!/bin/bash
set -e

GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
NC="\033[0m"

echo -e "${CYAN}======== BBRPlus DKMS + NGINX + Cloudflare 优化一键安装脚本 ========${NC}"
echo -e "${GREEN}当前系统内核版本：$(uname -r)${NC}"

read -p "是否继续安装 BBRPlus DKMS 模块并配置 NGINX 优化？[Y/N]: " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}操作已取消${NC}"
  exit 1
fi

echo -e "${GREEN}[1/10] 安装依赖包：dkms、build-essential、linux-headers、wget、unzip ...${NC}"
sudo apt update
sudo apt install -y dkms build-essential linux-headers-$(uname -r) wget unzip nginx

echo -e "${GREEN}[2/10] 清理旧的 BBRPlus DKMS 模块（如果有）...${NC}"
if dkms status | grep -q "tcp_bbrplus"; then
  sudo dkms remove tcp_bbrplus/0.1 --all || true
  sudo rm -rf /usr/src/tcp_bbrplus-0.1
  echo -e "${GREEN}旧模块已删除${NC}"
else
  echo -e "${GREEN}无旧模块，跳过删除${NC}"
fi

echo -e "${GREEN}[3/10] 下载 BBRPlus DKMS 源码 ZIP ...${NC}"
TMPDIR=$(mktemp -d)
wget -qO "$TMPDIR/tcp_bbrplus.zip" https://github.com/KozakaiAya/TCP_BBR/archive/refs/heads/master.zip

echo -e "${GREEN}[4/10] 解压源码到 /usr/src/tcp_bbrplus-0.1 ...${NC}"
sudo rm -rf /usr/src/tcp_bbrplus-0.1
sudo unzip -q "$TMPDIR/tcp_bbrplus.zip" -d /usr/src/
sudo mv /usr/src/TCP_BBR-master /usr/src/tcp_bbrplus-0.1
rm -rf "$TMPDIR"

echo -e "${GREEN}[5/10] 生成 dkms.conf 文件...${NC}"
sudo tee /usr/src/tcp_bbrplus-0.1/dkms.conf > /dev/null << EOF
PACKAGE_NAME="tcp_bbrplus"
PACKAGE_VERSION="0.1"
MAKE[0]="make -C ./code tcp_bbrplus.ko"
BUILT_MODULE_NAME[0]="tcp_bbrplus"
DEST_MODULE_LOCATION[0]="/kernel/net/ipv4/"
AUTOINSTALL="yes"
EOF

echo -e "${GREEN}[6/10] 添加 DKMS 模块...${NC}"
sudo dkms add -m tcp_bbrplus -v 0.1

echo -e "${GREEN}[7/10] 编译并安装 DKMS 模块...${NC}"
sudo dkms build -m tcp_bbrplus -v 0.1
sudo dkms install -m tcp_bbrplus -v 0.1

echo -e "${GREEN}[8/10] 加载 bbrplus 模块并设置 TCP 拥塞控制...${NC}"
sudo modprobe tcp_bbrplus

if ! grep -q "tcp_bbrplus" /etc/sysctl.conf; then
  echo -e "\n# BBRPlus 配置" | sudo tee -a /etc/sysctl.conf
  echo "net.core.default_qdisc = fq" | sudo tee -a /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control = tcp_bbrplus" | sudo tee -a /etc/sysctl.conf
fi

sudo sysctl -p

echo -e "${GREEN}[9/10] 优化 NGINX 配置，启用 gzip 和 Cloudflare 真实 IP 支持...${NC}"
sudo tee /etc/nginx/conf.d/optim.conf > /dev/null << EOF
server {
    listen 80 default_server;
    server_name _;

    location / {
        root /var/www/html;
        index index.html;
    }

    gzip on;
    gzip_types text/plain application/xml application/javascript text/css application/json;
    gzip_vary on;
    gzip_min_length 1024;

    # Cloudflare IP段列表
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 131.0.72.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    real_ip_header CF-Connecting-IP;
}
EOF

sudo systemctl restart nginx

echo -e "${GREEN}[10/10] 安装完成！${NC}"
echo -e "${GREEN}当前 TCP 拥塞控制算法：$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')${NC}"
echo -e "${GREEN}NGINX 版本：$(nginx -v 2>&1)${NC}"
echo -e "${YELLOW}建议重启系统确保内核模块完全生效：sudo reboot${NC}"
