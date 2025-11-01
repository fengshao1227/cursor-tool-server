#!/bin/bash

# License Server 健康检查脚本
# 使用方法: ./health-check.sh

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 加载环境变量
if [ -f .env ]; then
    source .env
fi

PORT=${PORT:-8080}

echo "License Server 健康检查"
echo "========================================"
echo ""

# 使用 docker compose 或 docker-compose
DOCKER_COMPOSE="docker compose"
if ! docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
fi

# 1. 检查 Docker 容器状态
echo "1. Docker 容器状态:"
$DOCKER_COMPOSE ps
echo ""

# 2. 检查健康端点
echo "2. 健康检查端点:"
if curl -f http://localhost:${PORT}/healthz > /dev/null 2>&1; then
    echo -e "   ${GREEN}✓ /healthz: OK${NC}"
else
    echo -e "   ${RED}✗ /healthz: FAILED${NC}"
fi
echo ""

# 3. 检查磁盘空间
echo "3. 磁盘空间:"
df -h | grep -E "Filesystem|/$" | awk '{print "   " $0}'
echo ""

# 4. 检查内存使用
echo "4. 内存使用:"
free -h | awk '{print "   " $0}'
echo ""

# 5. 检查容器日志（最后10行）
echo "5. 最近日志:"
$DOCKER_COMPOSE logs --tail=10 license-server | sed 's/^/   /'
echo ""

# 6. 检查端口监听
echo "6. 端口监听:"
if netstat -tlnp 2>/dev/null | grep ":${PORT}" > /dev/null; then
    echo -e "   ${GREEN}✓ Port ${PORT}: Listening${NC}"
else
    echo -e "   ${RED}✗ Port ${PORT}: Not listening${NC}"
fi
echo ""

echo "========================================"
echo "健康检查完成"

