#!/bin/bash

# Docker 镜像源修复脚本

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Docker 镜像源修复脚本${NC}"
echo ""

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用 sudo 运行此脚本${NC}"
    exit 1
fi

# 备份现有配置
if [ -f /etc/docker/daemon.json ]; then
    echo "备份现有 Docker 配置..."
    cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
    echo -e "${GREEN}✓ 已备份到 /etc/docker/daemon.json.backup${NC}"
fi

# 创建新配置
echo ""
echo "配置 Docker 镜像源..."

cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.mirrors.sjtug.sjtu.edu.cn",
    "https://docker.nju.edu.cn",
    "https://mirror.baidubce.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

echo -e "${GREEN}✓ Docker 配置已更新${NC}"

# 重启 Docker
echo ""
echo "重启 Docker 服务..."
systemctl daemon-reload
systemctl restart docker

# 等待 Docker 启动
sleep 3

# 检查 Docker 状态
if systemctl is-active --quiet docker; then
    echo -e "${GREEN}✓ Docker 服务运行正常${NC}"
else
    echo -e "${RED}✗ Docker 服务启动失败${NC}"
    exit 1
fi

# 显示配置
echo ""
echo "当前 Docker 镜像源配置:"
docker info | grep -A 10 "Registry Mirrors" || echo "未找到镜像源信息"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Docker 镜像源修复完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "现在可以重新部署了:"
echo "  cd /path/to/license-server"
echo "  ./deploy.sh"
echo ""

