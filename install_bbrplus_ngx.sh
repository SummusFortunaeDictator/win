#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/bbrplus_ngx_install.log"
exec > >(tee -a "$LOGFILE") 2>&1

GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
NC="\033[0m"

log(){ echo -e "$1"; }

log "${CYAN}======== BBRPlus DKMS + NGINX + Cloudflare 优化一键脚本 ========${NC}"
log "当前系统内核：$(uname -r)"

# 安装 NGINX
log "${GREEN}[1/4] 安装 NGINX...${NC}"
sudo apt update -y
sudo apt install -y nginx || { log "NGINX 安装失败"; exit 1; }

# 配置 NGINX 优化
log "${GREEN}[2/4] 写入 optim.conf...${NC}"
sudo tee /etc/nginx/conf.d/optim.conf > /dev/null << 'EOF'
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

    # Cloudflare IP 段
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

log "${GREEN}[3/4] 重启 NGINX...${NC}"
sudo systemctl restart nginx || { log "NGINX 重启失败"; exit 1; }

log "${GREEN}[4/4] 优化完成，NGINX 版本：$(nginx -v 2>&1)${NC}"
